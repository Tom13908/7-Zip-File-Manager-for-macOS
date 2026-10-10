// 各种归档操作的参数拼装、执行，以及进度窗口。
//
// 归档类操作全部交给 7zz 引擎（和 Windows 版把活交给 7z.dll 是一个道理）；
// 纯文件系统的复制 / 移动 / 删除不经过引擎。

import AppKit

// MARK: - 参数

struct ExtractOptions {
    var destination: String = ""
    var pathMode: ExtractPathMode = .full
    var overwrite: ExtractOverwriteMode = .ask
    var eliminateDuplicate: Bool = false
    var password: String = ""
}

/// 「Options」那层里的开关。默认值是按引擎实测的默认行为填的：
/// 默认只存修改时间，符号链接按普通文件存（加 -snl 才存成链接）。
struct AdvancedOptions {
    var symLinks = false
    var hardLinks = false
    var storeMTime = true
    var storeCTime = false
    var storeATime = false
    var archiveTimeLatest = false
    var preserveATime = false

    /// 只把与引擎默认不同的项变成开关，命令短且行为可预期
    var arguments: [String] {
        var a: [String] = []
        if symLinks { a.append("-snl") }
        if hardLinks { a.append("-snh") }
        if !storeMTime { a.append("-mtm=off") }
        if storeCTime { a.append("-mtc=on") }
        if storeATime { a.append("-mta=on") }
        if archiveTimeLatest { a.append("-stl") }
        if preserveATime { a.append("-ssp") }
        return a
    }
}

struct AddOptions {
    var format: String = "7z"
    var level: CompressionLevel = .normal
    /// 引擎的方法名；空 = 由级别自动决定（下拉里的 "*  xxx" 那一项）
    var method: String = ""
    /// 字典大小，形如 "32m"；空 = 自动
    var dictionary: String = ""
    var wordSize: String = ""
    /// 空 = 自动；"off" = 非固实；"on" = 全固实；其余是带后缀的字节数
    var solidBlock: String = ""
    var threads: String = ""
    var volumeSize: String = ""
    var parameters: String = ""
    var updateMode: UpdateMode = .update
    var deleteAfter: Bool = false
    var sharedFiles: Bool = false
    var password: String = ""
    var encryptFileNames: Bool = false
    var advanced = AdvancedOptions()
}

// MARK: - 进度模型

final class ProgressModel {
    enum Kind {
        case extract, compress, test, hash, copy, move, delete, split, benchmark

        var title: String {
            switch self {
            case .extract: return S.progressExtracting
            case .compress: return S.progressCompressing
            case .test: return S.progressTesting
            case .hash: return S.calcChecksum
            case .copy: return S.progressCopying
            case .move: return S.progressMoving
            case .delete: return S.progressDeleting
            case .split: return S.progressSplitting
            case .benchmark: return "Benchmark"
            }
        }
    }

    let kind: Kind
    var subject: String
    var totalBytes: Int64 = 0
    var processedBytes: Int64 = 0
    var percent: Int = 0
    var currentFile: String = ""
    var errors: [String] = []
    var finished = false
    var succeeded = true
    /// 压缩完成后引擎报告的产出体积，用来算压缩率
    var outputBytes: Int64 = 0

    private let started = Date()

    init(kind: Kind, subject: String) {
        self.kind = kind
        self.subject = subject
    }

    var elapsed: Double { Date().timeIntervalSince(started) }

    var speedBytesPerSec: Double {
        let t = elapsed
        guard t > 0.4, processedBytes > 0 else { return 0 }
        return Double(processedBytes) / t
    }

    var remaining: Double {
        let s = speedBytesPerSec
        guard s > 1, totalBytes > processedBytes else { return 0 }
        return Double(totalBytes - processedBytes) / s
    }

    var ratio: String {
        guard kind == .compress, processedBytes > 0, outputBytes > 0 else { return "" }
        return String(format: "%.0f%%", Double(processedBytes) / Double(outputBytes) * 100)
    }

    func update(percent p: Int, file: String) {
        percent = max(0, min(100, p))
        if totalBytes > 0 { processedBytes = totalBytes * Int64(percent) / 100 }
        if !file.isEmpty { currentFile = file }
    }

    func update(bytes: Int64) {
        processedBytes = bytes
        if totalBytes > 0 { percent = Int(min(100, bytes * 100 / totalBytes)) }
    }
}

// MARK: - 进度窗口（结构照 ProgressDialog2.rc）

final class ProgressWindowController: NSWindowController {

    let model: ProgressModel
    private let titleLabel = NSTextField(labelWithString: "")
    private let overallBar = NSProgressIndicator()
    private let overallPercent = NSTextField(labelWithString: "0%")
    private let fileBar = NSProgressIndicator()
    private let currentFileLabel = NSTextField(labelWithString: "")
    private let leftInfo = NSTextField(labelWithString: "")
    private let rightInfo = NSTextField(labelWithString: "")
    private let totalValue = NSTextField(labelWithString: "")
    private let processedValue = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(labelWithString: "")
    private let pauseButton = NSButton()
    private let actionButton = NSButton()
    private let cancelButton = NSButton()
    private let errorBox = NSScrollView()
    private let errorText = NSTextView()
    private var stack: NSStackView!

    private var timer: Timer?
    private(set) var task: EngineTask?

    func attach(_ t: EngineTask) { task = t }

    init(model: ProgressModel) {
        self.model = model
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 236),
                         styleMask: [.titled, .closable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "7-Zip"
        w.isReleasedWhenClosed = false
        super.init(window: w)
        build()
        w.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    private var isPaused = false

    private func build() {
        guard let content = window?.contentView else { return }

        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)

        for bar in [overallBar, fileBar] {
            bar.isIndeterminate = false
            bar.minValue = 0
            bar.maxValue = 100
            bar.doubleValue = 0
            bar.controlSize = .small
        }
        overallPercent.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        overallPercent.alignment = .right

        for f in [totalValue, processedValue] {
            f.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            f.alignment = .right
        }
        currentFileLabel.font = NSFont.systemFont(ofSize: 11)
        currentFileLabel.lineBreakMode = .byTruncatingMiddle
        currentFileLabel.textColor = .secondaryLabelColor
        leftInfo.font = NSFont.systemFont(ofSize: 11)
        leftInfo.textColor = .secondaryLabelColor
        rightInfo.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        rightInfo.textColor = .secondaryLabelColor
        errorLabel.font = NSFont.systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed

        errorText.isEditable = false
        errorText.drawsBackground = false
        errorText.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        errorBox.documentView = errorText
        errorBox.hasVerticalScroller = true
        errorBox.borderType = .bezelBorder
        errorBox.isHidden = true
        errorBox.translatesAutoresizingMaskIntoConstraints = false
        errorBox.heightAnchor.constraint(equalToConstant: 96).isActive = true

        pauseButton.title = S.pPause
        pauseButton.bezelStyle = .rounded
        pauseButton.target = self
        pauseButton.action = #selector(togglePause)

        actionButton.title = S.pBackground
        actionButton.bezelStyle = .rounded
        actionButton.target = self
        actionButton.action = #selector(primaryAction)

        cancelButton.title = S.cancel
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(doCancel)

        let buttons = NSStackView(views: [actionButton, pauseButton, cancelButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let barRow = NSStackView(views: [overallBar, overallPercent])
        barRow.orientation = .horizontal
        barRow.spacing = 8
        overallBar.widthAnchor.constraint(equalToConstant: 400).isActive = true
        overallPercent.widthAnchor.constraint(equalToConstant: 44).isActive = true

        let totalsRow = NSStackView(views: [
            caption(S.pTotalSize), totalValue,
            caption(S.pProcessed), processedValue,
        ])
        totalsRow.orientation = .horizontal
        totalsRow.spacing = 6

        let fileRow = NSStackView(views: [caption(S.pCurrentFile), currentFileLabel])
        fileRow.orientation = .horizontal
        fileRow.spacing = 6
        currentFileLabel.widthAnchor.constraint(equalToConstant: 400).isActive = true

        fileBar.widthAnchor.constraint(equalToConstant: 400).isActive = true

        stack = NSStackView(views: [
            titleLabel,
            barRow,
            totalsRow,
            fileRow,
            fileBar,
            rightInfo,
            leftInfo,
            errorLabel,
            errorBox,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false

        let bottom = NSStackView(views: [buttons])
        bottom.orientation = .horizontal
        bottom.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(stack)
        content.addSubview(bottom)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -18),

            errorBox.widthAnchor.constraint(equalToConstant: 496),

            bottom.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 12),
            bottom.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            bottom.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
    }

    private func caption(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = NSFont.systemFont(ofSize: 11)
        return l
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                self?.tick()
            }
        }
        tick()
    }

    private func tick() {
        if model.finished {
            titleLabel.stringValue = "\(model.kind.title) — \(model.succeeded ? "OK" : "finished with errors")  \(model.subject)"
        } else {
            titleLabel.stringValue = "\(model.kind.title)  \(model.subject)"
        }

        overallBar.doubleValue = Double(model.percent)
        overallPercent.stringValue = "\(model.percent)%"
        fileBar.doubleValue = Double(model.percent)

        totalValue.stringValue = model.totalBytes > 0 ? Fmt.size(model.totalBytes) : ""
        processedValue.stringValue = model.processedBytes > 0 ? Fmt.size(model.processedBytes) : ""
        currentFileLabel.stringValue = model.currentFile

        leftInfo.stringValue = "\(S.pElapsed) \(Fmt.duration(model.elapsed))    "
            + "\(S.pRemaining) \(model.remaining > 0 ? Fmt.duration(model.remaining) : "--:--")"

        var right = ""
        let sp = model.speedBytesPerSec
        if sp > 0 { right = "\(S.pSpeed) \(Self.humanSpeed(sp))" }
        let r = model.ratio
        if !r.isEmpty { right += (right.isEmpty ? "" : "    ") + "\(S.pRatio) \(r)" }

        if !model.errors.isEmpty {
            right += (right.isEmpty ? "" : "    ") + "\(S.pErrors) \(model.errors.count)"
        }
        rightInfo.stringValue = right

        if !model.errors.isEmpty, errorBox.isHidden {
            errorBox.isHidden = false
            errorText.string = model.errors.joined(separator: "\n")
            window?.setContentSize(NSSize(width: 540, height: 360))
        }
        if !model.errors.isEmpty {
            errorText.string = model.errors.joined(separator: "\n")
        }
    }

    private static func humanSpeed(_ bps: Double) -> String {
        if bps > 1_000_000_000 { return String(format: "%.1f GB/s", bps / 1_000_000_000) }
        if bps > 1_000_000 { return String(format: "%.1f MB/s", bps / 1_000_000) }
        if bps > 1_000 { return String(format: "%.1f KB/s", bps / 1_000) }
        return String(format: "%.0f B/s", bps)
    }

    @objc private func togglePause() {
        guard let task else { return }
        isPaused = task.togglePause()
        pauseButton.title = isPaused ? S.btnContinue : S.pPause
    }

    @objc private func primaryAction() {
        if model.finished {
            window?.orderOut(nil)
            window?.close()
        } else {
            window?.orderOut(nil)   // 转到后台继续跑
        }
    }

    @objc private func doCancel() {
        task?.cancel()
    }

    func finish() {
        model.finished = true
        timer?.invalidate()
        timer = nil
        if model.errors.isEmpty {
            // 解压一个几十 MB 的包常常快到来不及产生第二行进度（引擎只在百分比变化时
            // 才打印），进度条会停在 0%。任务已经做完了，不该让它留在 0% 上。
            model.percent = 100
            model.processedBytes = max(model.processedBytes, model.totalBytes)
        }
        tick()

        guard model.errors.isEmpty else {
            // 出错时窗口要留着：里面是用户唯一能看到失败原因的地方
            pauseButton.isHidden = true
            cancelButton.isHidden = true
            actionButton.title = S.close
            window?.makeKeyAndOrderFront(nil)
            return
        }

        // 成功就自己关掉（Windows 版也是做完即关）。留一个再也不会变的窗口在那儿，
        // 看起来就像操作卡死了 —— 而且它要是唯一的窗口，App 还得一直陪它挂着。
        window?.orderOut(nil)
        window?.close()

        // 校验归档的结果就是那一句 OK：窗口一关就什么都不剩了，得单独说一声。
        // 别的操作做完自然看得见结果（文件在、体积在），不用再弹一次。
        if model.kind == .test {
            DialogKit.alert(S.everythingIsOk, model.subject, style: .informational, parent: nil)
        }
    }
}

// MARK: - 操作执行

final class Operations {

    private var activeWindows: [ProgressWindowController] = []

    private func keep(_ wc: ProgressWindowController) {
        activeWindows.append(wc)
        if activeWindows.count > 8 { activeWindows.removeFirst(activeWindows.count - 8) }
    }

    // MARK: 解压

    /// 7-Zip 的默认解压目录：归档文件所在目录下、去掉扩展名的同名文件夹
    static func defaultExtractFolder(archive: String, fallbackDir: String) -> String {
        let base = (archive as NSString).lastPathComponent
        let name = (base as NSString).deletingPathExtension
        if name.isEmpty { return fallbackDir }
        return (fallbackDir as NSString).appendingPathComponent(name)
    }

    @discardableResult
    func extract(archive: String, names: [String], options: ExtractOptions,
                 totalBytes: Int64, parent: NSWindow?) -> ProgressWindowController {
        let model = ProgressModel(kind: .extract, subject: (archive as NSString).lastPathComponent)
        model.totalBytes = totalBytes

        var args: [String] = [options.pathMode == .noPaths ? "e" : "x"]
        args.append("-o" + options.destination)
        args.append("-y")
        if let ao = options.overwrite.argument { args.append(ao) }
        if options.pathMode == .absolute { args.append("-spf2") }
        if options.eliminateDuplicate { args.append("-spe") }
        if !options.password.isEmpty { args.append("-p" + options.password) }
        args.append("-bsp1")
        args.append(archive)
        args.append(contentsOf: names)

        return launch(args: args, model: model, parent: parent)
    }

    // MARK: 压缩

    @discardableResult
    func add(archive: String, files: [String], workingDirectory: String, options: AddOptions,
             totalBytes: Int64, parent: NSWindow?) -> ProgressWindowController {
        let model = ProgressModel(kind: .compress, subject: (archive as NSString).lastPathComponent)
        model.totalBytes = totalBytes
        model.outputBytes = 0

        var args = ["a", "-t" + options.format]
        args.append("-mx\(options.level.rawValue)")
        if !options.method.isEmpty { args.append("-m0=" + options.method) }
        if !options.dictionary.isEmpty { args.append("-md=" + options.dictionary) }
        if !options.wordSize.isEmpty { args.append("-mfb=" + options.wordSize) }
        if !options.solidBlock.isEmpty { args.append("-ms=" + options.solidBlock) }
        if !options.threads.isEmpty { args.append("-mmt=" + options.threads) }
        if !options.volumeSize.isEmpty { args.append("-v" + options.volumeSize) }
        if options.sharedFiles { args.append("-ssw") }
        if !options.password.isEmpty {
            args.append("-p" + options.password)
            if options.encryptFileNames { args.append("-mhe=on") }
        }
        if options.deleteAfter { args.append("-sdel") }
        args.append(contentsOf: options.advanced.arguments)
        if !options.parameters.isEmpty {
            args.append(contentsOf: options.parameters.split(separator: " ").map(String.init))
        }
        args.append(contentsOf: options.updateMode.arguments)
        args.append("-bsp1")
        args.append(archive)
        args.append(contentsOf: files)

        return launch(args: args, model: model, parent: parent, workingDirectory: workingDirectory)
    }

    // MARK: 测试

    @discardableResult
    func test(archives: [String], password: String?, totalBytes: Int64,
              parent: NSWindow?) -> ProgressWindowController {
        let model = ProgressModel(kind: .test,
                                  subject: archives.first.map { ($0 as NSString).lastPathComponent } ?? "")
        model.totalBytes = totalBytes
        var args = ["t", "-bsp1"]
        if let p = password, !p.isEmpty { args.append("-p" + p) }
        args.append(contentsOf: archives)
        return launch(args: args, model: model, parent: parent)
    }

    // MARK: 校验和（结果直接给一个文本窗口）

    func hash(files: [String], kind: HashKind, workingDirectory: String,
              parent: NSWindow?) {
        var args = ["h"]
        if let v = kind.switchValue { args.append("-scrc" + v) }
        args.append(contentsOf: files)

        DispatchQueue.global(qos: .userInitiated).async {
            let r = try? Engine.runSync(args)
            var lines: [String] = []
            for line in (r?.stdout ?? "").split(separator: "\n") {
                let s = String(line)
                if s.contains(" = ") || s.hasPrefix("----") { lines.append(s) }
            }
            DispatchQueue.main.async {
                if lines.isEmpty {
                    TextWindow.show(title: "7-Zip", text: (r?.stderr ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    TextWindow.show(title: kind.title, text: lines.joined(separator: "\n"))
                }
            }
        }
    }

    // MARK: 归档内改名 / 删除

    @discardableResult
    func renameInArchive(archive: String, pairs: [(from: String, to: String)],
                         password: String?, parent: NSWindow?) -> ProgressWindowController {
        let model = ProgressModel(kind: .compress, subject: (archive as NSString).lastPathComponent)
        var args = ["rn", "-bsp1"]
        if let p = password, !p.isEmpty { args.append("-p" + p) }
        args.append(archive)
        for p in pairs { args.append(p.from); args.append(p.to) }
        return launch(args: args, model: model, parent: parent)
    }

    @discardableResult
    func deleteInArchive(archive: String, names: [String], password: String?,
                         parent: NSWindow?) -> ProgressWindowController {
        let model = ProgressModel(kind: .delete, subject: (archive as NSString).lastPathComponent)
        var args = ["d", "-bsp1", "-y"]
        if let p = password, !p.isEmpty { args.append("-p" + p) }
        args.append(archive)
        args.append(contentsOf: names)
        return launch(args: args, model: model, parent: parent)
    }

    // MARK: 复制 / 移动 / 删除（纯文件系统）

    @discardableResult
    func copyOrMove(_ urls: [URL], to destination: String, move: Bool,
                    parent: NSWindow?) -> ProgressWindowController {
        let model = ProgressModel(kind: move ? .move : .copy, subject: destination)
        let total = urls.reduce(Int64(0)) { $0 + Self.sizeOfItem(at: $1.path) }
        model.totalBytes = total

        let wc = ProgressWindowController(model: model)
        keep(wc)
        wc.show()

        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var done: Int64 = 0
            var errors: [String] = []
            for u in urls {
                let dst = (destination as NSString).appendingPathComponent(u.lastPathComponent)
                // 目标就是文件自己（把文件拖回它所在的目录）：下面那句「先删目标再复制」
                // 会先把源删掉，复制随即失败 —— 结果是文件凭空消失。这种情况直接跳过。
                if Self.samePath(u.path, dst) {
                    done += Self.sizeOfItem(at: u.path)
                    continue
                }
                do {
                    if fm.fileExists(atPath: dst) { try fm.removeItem(atPath: dst) }
                    if move {
                        try fm.moveItem(at: u, to: URL(fileURLWithPath: dst))
                    } else {
                        try fm.copyItem(at: u, to: URL(fileURLWithPath: dst))
                    }
                } catch {
                    errors.append("\(u.lastPathComponent): \(error.localizedDescription)")
                }
                done += Self.sizeOfItem(at: u.path)
                DispatchQueue.main.async {
                    model.update(bytes: done)
                    model.currentFile = u.lastPathComponent
                }
            }
            DispatchQueue.main.async {
                model.errors = errors
                model.succeeded = errors.isEmpty
                wc.finish()
            }
        }
        return wc
    }

    /// 删除 -> 移到废纸篓（对应 Windows 版的「移到回收站」）
    func trash(_ urls: [URL], completion: @escaping ([String]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var errors: [String] = []
            for u in urls {
                do {
                    try FileManager.default.trashItem(at: u, resultingItemURL: nil)
                } catch {
                    errors.append("\(u.lastPathComponent): \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async { completion(errors) }
        }
    }

    /// 两个路径是不是同一个文件（消掉 `..`、多余斜杠和符号链接）
    static func samePath(_ a: String, _ b: String) -> Bool {
        func norm(_ p: String) -> String {
            URL(fileURLWithPath: p).resolvingSymlinksInPath().standardizedFileURL.path
        }
        return norm(a) == norm(b)
    }

    static func sizeOfItem(at path: String) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            guard let n = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber
            else { return 0 }
            return n.int64Value
        }
        var total: Int64 = 0
        if let en = FileManager.default.enumerator(atPath: path) {
            for case let sub as String in en {
                let full = (path as NSString).appendingPathComponent(sub)
                if let n = try? FileManager.default.attributesOfItem(atPath: full)[.size] as? NSNumber {
                    total += n.int64Value
                }
            }
        }
        return total
    }

    /// 归档里所有条目的未压缩总大小，用来给进度条定标。
    /// 读的是引擎自己给的清单（l -slt），不是猜的。
    static func archiveTotalSize(at path: String) -> Int64 {
        guard let r = try? Engine.runSync(["l", "-slt", "-ba", path]) else { return 0 }
        var total: Int64 = 0
        r.stdout.enumerateLines { line, _ in
            guard line.hasPrefix("Size = ") else { return }
            if let n = Int64(line.dropFirst(7).trimmingCharacters(in: .whitespaces)) { total += n }
        }
        return total
    }

    // MARK: 拆分文件

    @discardableResult
    func split(file: String, volumeBytes: Int64, parent: NSWindow?) -> ProgressWindowController {
        let model = ProgressModel(kind: .split, subject: (file as NSString).lastPathComponent)
        model.totalBytes = Self.sizeOfItem(at: file)
        let dir = (file as NSString).deletingLastPathComponent
        let base = (file as NSString).lastPathComponent
        // 归档名给到 .7z 就行，.001 是引擎自己加的
        // （实测给 out.7z.001 会得到 out.7z.001.001）
        let args = ["a", "-t7z", "-mx0", "-v\(volumeBytes)b", "-bsp1",
                    dir + "/" + base + ".7z", base]
        return launch(args: args, model: model, parent: parent, workingDirectory: dir)
    }

    // MARK: 引擎任务统一驱动

    private func launch(args: [String], model: ProgressModel, parent: NSWindow?,
                        workingDirectory: String? = nil) -> ProgressWindowController {
        let wc = ProgressWindowController(model: model)
        keep(wc)

        let task = EngineTask(arguments: args, currentDirectory: workingDirectory)
        wc.attach(task)

        task.onProgress = { p in
            model.update(percent: p.percent, file: p.currentFile)
        }
        task.onMessage = { [weak self] line in
            if line.hasPrefix("ERROR:") || line.hasPrefix("WARNING:") {
                model.errors.append(line)
            }
            _ = self
        }
        task.onFinish = { [weak self] r in
            model.succeeded = r.exitCode <= 1 && model.errors.isEmpty
            switch r.exitCode {
            case 0, 1: break
            case 255: model.errors.append(S.breakSignaled)
            case 8: model.errors.append(S.notEnoughMemory)
            default:
                let tail = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                if model.errors.isEmpty, !tail.isEmpty { model.errors.append(tail) }
            }
            if model.kind == .compress {
                let sz = Self.sizeOfItem(at: model.subject)
                if sz > 0 { model.outputBytes = sz }
            }
            wc.finish()
            _ = self
        }

        wc.show()
        task.run()
        return wc
    }
}

// MARK: - 只读文本窗口（校验和结果、Diff、引擎信息都用它）

enum TextWindow {
    private static var windows: [NSWindowController] = []

    static func show(title: String, text: String, width: CGFloat = 720, height: CGFloat = 420) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false

        let scroll = NSScrollView(frame: w.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true

        let tv = NSTextView(frame: scroll.bounds)
        tv.isEditable = false
        tv.isRichText = false
        tv.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.string = text
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: 4000, height: CGFloat.greatestFiniteMagnitude)

        scroll.documentView = tv
        w.contentView?.addSubview(scroll)

        let wc = NSWindowController(window: w)
        windows.append(wc)
        if windows.count > 6 { windows.removeFirst() }
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
