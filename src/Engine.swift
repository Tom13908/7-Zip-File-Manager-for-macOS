// 7zz 引擎封装：进程调用、列表解析、进度解析。
//
// 所有归档操作都走官方引擎（随包里的 7zz），GUI 自己不做任何编解码——
// 这一点和 Windows 版一样：7zFM.exe 也是把活交给 7z.dll。

import Foundation

// MARK: - 引擎位置与版本

enum Engine {

    /// 随包的引擎，在 Contents/Resources/7zz。
    /// 系统里那份 7zz 只是兜底，正常安装不该走到那一步。
    static let path: String = {
        if let p = Res.url("7zz", ext: "")?.path { return p }
        if let env = ProcessInfo.processInfo.environment["SEVENZIP_ENGINE"],
           FileManager.default.isExecutableFile(atPath: env) { return env }
        return "/usr/local/bin/7zz"
    }()

    /// 引擎不在随包位置时（比如没装好）给界面用的一句话
    static var isBundled: Bool { path.hasPrefix(Res.root.path) }

    static var version: String = "26.03"

    static func probeVersion() {
        guard let out = try? runSync([], timeout: 5) else { return }
        // "7-Zip (z) 26.03 (arm64) : Copyright ..."
        for line in out.stdout.split(separator: "\n") {
            if line.hasPrefix("7-Zip") {
                let parts = line.split(separator: " ").map(String.init)
                if parts.count >= 3 { version = parts[2] }
                break
            }
        }
    }
}

// MARK: - 进度信息

struct ProgressInfo {
    var percent: Int = 0
    var itemNumber: Int = 0
    var operation: String = ""
    var currentFile: String = ""
}

struct RunResult {
    var exitCode: Int32
    var stdout: String
    var stderr: String
    var messages: [String] = []
    var wasCancelled = false

    var allText: String { stdout + "\n" + stderr }

    /// 7-Zip 的退出码语义（见 7-Zip 文档 Exit Codes）
    var succeeded: Bool { exitCode == 0 || exitCode == 1 }
}

enum EngineError: LocalizedError {
    case passwordRequired
    case notAnArchive(String)
    case failed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .passwordRequired: return S.cantOpenEncrypted
            .replacingOccurrences(of: "'{0}'", with: "")
            .replacingOccurrences(of: "{0}", with: "")
        case .notAnArchive(let p): return S.cantOpenArchive.replacingOccurrences(of: "{0}", with: p)
        case .failed(let m): return m
        case .cancelled: return S.cancelled
        }
    }
}

// MARK: - 进程执行

final class EngineTask {
    let process = Process()
    private var outPipe = Pipe()
    private var errPipe = Pipe()
    private var outBuf = Data()
    private var errBuf = Data()
    private var lineCarry = ""      // 被 \r、\n 或退格切开的残段
    private var lastWasBackspace = false
    private let lock = NSRecursiveLock()

    /// 回调投递队列。UI 用主队列；同步调用（runSync）必须换掉，
    /// 否则从主线程发起同步调用会自己把自己锁死。
    let callbackQueue: DispatchQueue

    var onProgress: ((ProgressInfo) -> Void)?
    var onMessage: ((String) -> Void)?
    var onFinish: ((RunResult) -> Void)?

    private(set) var messages: [String] = []
    private(set) var lastProgress = ProgressInfo()
    private var didReportProgress = false
    private(set) var stdoutText = ""
    private(set) var stderrText = ""
    private(set) var cancelled = false
    private var paused = false

    private static let progressRe = try! NSRegularExpression(
        pattern: #"^\s*(\d{1,3})%(?:\s+(\d+))?(?:\s+([+\-UR.]))?(?:\s+(.*))?$"#)

    init(arguments: [String], currentDirectory: String? = nil,
         callbackQueue: DispatchQueue = .main) {
        self.callbackQueue = callbackQueue
        process.executableURL = URL(fileURLWithPath: Engine.path)
        process.arguments = arguments
        if let cwd = currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        process.standardOutput = outPipe
        process.standardError = errPipe
        // 必须堵住 stdin：7zz 需要密码时会去读标准输入，不堵住会一直挂着
        process.standardInput = FileHandle.nullDevice

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            self?.consume(d, isError: false)
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            self?.consume(d, isError: true)
        }
    }

    func run() {
        do {
            try process.run()
        } catch {
            let r = RunResult(exitCode: -1, stdout: "", stderr: "\(error)",
                              messages: ["Cannot start 7zz: \(error)"])
            self.callbackQueue.async { self.onFinish?(r) }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            process.waitUntilExit()
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            // 收尾：把管道里剩下的读完
            if let d = try? outPipe.fileHandleForReading.readToEnd() { consume(d, isError: false) }
            if let d = try? errPipe.fileHandleForReading.readToEnd() { consume(d, isError: true) }
            flushCarry()

            let code = process.terminationStatus
            lock.lock()
            let r = RunResult(exitCode: code,
                              stdout: stdoutText,
                              stderr: stderrText,
                              messages: messages,
                              wasCancelled: cancelled)
            lock.unlock()
            self.callbackQueue.async { self.onFinish?(r) }
        }
    }

    /// 请求 7-Zip 停下（它把 SIGTERM 当作 Break，会清理临时文件）
    func cancel() {
        cancelled = true
        if process.isRunning { process.terminate() }
    }

    func togglePause() -> Bool {
        guard process.isRunning else { return false }
        let pid = process.processIdentifier
        if paused {
            kill(pid, SIGCONT); paused = false
        } else {
            kill(pid, SIGSTOP); paused = true
        }
        return paused
    }

    var isPaused: Bool { paused }

    // MARK: 输出解析

    private func consume(_ data: Data, isError: Bool) {
        // 整段解析必须在锁里跑完：stdout 和 stderr 各有一个 readabilityHandler，
        // 它们在不同的调度队列上并发调进这里，而 lineCarry 是两边共用的当前行。
        // 只锁住缓冲区的读写、把解析留在锁外的话，两边的 append 会撞在同一个
        // String 上（实测是 SIGSEGV in _StringGuts.append）。lock 是递归锁，
        // 下面 handleSegment 里再进一次没有关系。
        lock.lock()
        defer { lock.unlock() }

        if isError { errBuf.append(data) } else { outBuf.append(data) }
        let text = String(decoding: data, as: UTF8.self)
        if isError { stderrText += text }

        // 7-Zip 输出进度靠「退格」而不是 \r：先发 n 个 \x08 退回去，再写新内容盖住旧的，
        // 整个过程没有换行。只按 \r / \n 切段的话，这一长串进度会一直堆在 lineCarry 里
        // 出不来 —— 进度条就永远停在 0%，直到进程退出才被 flush 成一行乱码。
        for ch in text {
            switch ch {
            case "\n", "\r":
                handleSegment(lineCarry, isError: isError)
                lineCarry = ""
                lastWasBackspace = false
            case "\u{08}":
                // 只认整个退格块的第一格。7-Zip 擦一行是连着发一串 \x08，
                // 块首那一格对应的正是刚写完的完整一行；跟着的每一格都会把
                // 文件名一节一节吃掉（"big.bin" 一路退成 "b"）。
                if !lastWasBackspace { reportProgress(lineCarry) }
                if !lineCarry.isEmpty { lineCarry.removeLast() }
                lastWasBackspace = true
            default:
                lineCarry.append(ch)
                lastWasBackspace = false
            }
        }
    }

    private func flushCarry() {
        lock.lock()
        defer { lock.unlock() }
        if !lineCarry.isEmpty {
            handleSegment(lineCarry, isError: false)
            lineCarry = ""
        }
    }

    private func handleSegment(_ seg: String, isError: Bool) {
        // 调用它的 consume / flushCarry 已经持有递归锁
        let line = seg.trimmingCharacters(in: .whitespaces)
        if line.isEmpty {
            // 空行不能丢：`l -slt` 正是用空行分隔每个条目，
            // 吞掉它会让整个归档塌成一条记录。
            if !isError {
                lock.lock(); stdoutText += "\n"; lock.unlock()
            }
            return
        }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        if !isError, EngineTask.progressRe.firstMatch(in: line, range: range) != nil {
            reportProgress(line)
            return
        }

        lock.lock()
        stdoutText += seg + "\n"
        messages.append(line)
        lock.unlock()
        callbackQueue.async { self.onMessage?(line) }
    }

    /// 解析一行进度并回调。只认进度，不往 stdout / messages 里写 ——
    /// 进度行会被反复重画，当成普通输出收进去就会在列表结果里留下残渣。
    private func reportProgress(_ seg: String) {
        let line = seg.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let m = EngineTask.progressRe.firstMatch(in: line, range: range) else { return }

        var p = ProgressInfo()
        if let r = Range(m.range(at: 1), in: line), let v = Int(line[r]) { p.percent = v }
        if let r = Range(m.range(at: 2), in: line), let v = Int(line[r]) { p.itemNumber = v }
        if let r = Range(m.range(at: 3), in: line) { p.operation = String(line[r]) }
        if let r = Range(m.range(at: 4), in: line) { p.currentFile = String(line[r]) }
        if p.currentFile.isEmpty { p.currentFile = lastProgress.currentFile }
        // 退格会把同一个数字退回来重画多次，过滤掉重复的没有意义的回调
        if didReportProgress, p.percent == lastProgress.percent,
           p.currentFile == lastProgress.currentFile, p.itemNumber == lastProgress.itemNumber {
            return
        }
        lastProgress = p
        didReportProgress = true
        callbackQueue.async { self.onProgress?(p) }
    }
}

extension Engine {

    /// 同步跑一条命令（列表、探测用，不出进度）
    @discardableResult
    static func runSync(_ arguments: [String], timeout: TimeInterval? = nil) throws -> RunResult {
        // 同步调用不能用主队列回调，否则死锁
        let task = EngineTask(arguments: arguments,
                              callbackQueue: DispatchQueue(label: "7zz.sync"))
        let sem = DispatchSemaphore(value: 0)
        var result: RunResult?
        task.onFinish = { r in result = r; sem.signal() }
        task.run()
        let wait = timeout.map { DispatchTime.now() + $0 } ?? .distantFuture
        if sem.wait(timeout: wait) == .timedOut {
            task.cancel()
            _ = sem.wait(timeout: .now() + 5)
        }
        guard let r = result else { throw EngineError.failed("7zz 没有返回结果") }
        return r
    }
}
