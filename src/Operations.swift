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
        // 压缩率 = 产出体积 / 原始体积。原来写反了，而且 outputBytes 一直取不到值。
        return String(format: "%.0f%%", Double(outputBytes) / Double(processedBytes) * 100)
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

// MARK: - 解压前的冲突预检

/// 「在覆盖前询问」的保护层。
///
/// 7zz 的覆盖询问走 stdin，而 EngineTask 把 stdin 接到了 /dev/null。
/// 原来 ask 不加开关却照样带 -y，等于对每个冲突都答 Yes，用户看到的是
/// 静默覆盖。这里在解压前先读出条目清单，算出会落在哪些路径，问一次，
/// 再把选择换成 -aoa / -aos / -aot 交给引擎。
private enum ExtractGuard {

    /// 读 `l -slt -ba` 里的 Path 行。读不出来（缺密码、坏包）返回 nil，
    /// 调用方按「不改任何已有文件」处理，不猜。
    static func entryPaths(archive: String, password: String) -> [String]? {
        var args = ["l", "-slt", "-ba"]
        if !password.isEmpty { args.append("-p" + password) }
        args.append("--")
        args.append(archive)
        guard let r = try? Engine.runSync(args), r.exitCode == 0 else { return nil }
        var paths: [String] = []
        r.stdout.enumerateLines { line, _ in
            guard line.hasPrefix("Path = ") else { return }
            let p = String(line.dropFirst(7))
            if !p.isEmpty { paths.append(p) }
        }
        return paths.isEmpty ? nil : paths
    }

    /// 把归档内部路径换算成会落地的目标路径。
    /// 引擎会消毒 ".." 和绝对路径；越出目标目录的一律不算冲突。
    static func landingPaths(_ paths: [String], names: [String],
                             options: ExtractOptions) -> [String] {
        var selected = paths
        if !names.isEmpty {
            selected = selected.filter { p in
                names.contains { n in p == n || p.hasPrefix(n + "/") }
            }
        }
        if options.eliminateDuplicate, let root = commonRoot(selected) {
            selected = selected.compactMap {
                $0 == root ? nil : String($0.dropFirst(root.count + 1))
            }
        }
        let dest = (options.destination as NSString).standardizingPath
        return selected.compactMap { p -> String? in
            let raw = options.pathMode == .noPaths
                ? (p as NSString).lastPathComponent
                : p
            // -spf2 用的是归档里写的绝对路径，落地位置根本不在 destination 下面。
            // 这里若还按 destination 拼，冲突预检会查错地方：真正的目标没查，
            // 反倒可能报一个假的冲突。
            if options.pathMode == .absolute {
                let abs = (raw as NSString).standardizingPath
                return abs.hasPrefix("/") ? abs : nil
            }
            let joined = (dest as NSString).appendingPathComponent(raw)
            let std = (joined as NSString).standardizingPath
            guard std == dest || std.hasPrefix(dest + "/") else { return nil }
            return std
        }
    }

    /// -spe 会去掉所有条目共用的那一层根目录
    private static func commonRoot(_ paths: [String]) -> String? {
        guard let first = paths.first else { return nil }
        let root = (first as NSString).pathComponents.first ?? ""
        guard !root.isEmpty, root != "/",
              paths.allSatisfy({ ($0 as NSString).pathComponents.first == root }),
              // 只有一条孤零零的目录记录不算「共享根目录」；要真有下级条目
              // 才轮得到 -spe 去剥掉这一层。
              paths.contains(where: { $0.contains("/") }) else { return nil }
        return root
    }

    /// 目标目录里已经存在的落地路径，去重后给出名字
    static func existing(_ landing: [String]) -> [String] {
        let fm = FileManager.default
        var out: [String] = []
        for p in landing where fm.fileExists(atPath: p) {
            let name = (p as NSString).lastPathComponent
            if !out.contains(name) { out.append(name) }
        }
        return out
    }

    /// e（无路径）模式下，不同目录里的同名条目会落到同一个位置
    static func duplicateNames(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        var dup: Set<String> = []
        for p in paths {
            let n = (p as NSString).lastPathComponent
            if !seen.insert(n).inserted { dup.insert(n) }
        }
        return dup.sorted()
    }
}

/// 自定义参数框里的分词。原来按空格硬切，填 `-m0=LZMA2 "a b.txt"`
/// 会把引号里的名字拆成两个 argv。这里按 shell 的规则认引号和反斜杠。
enum CommandLineSplitting {
    static func split(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var quote: Character?
        var escaped = false
        for ch in s {
            if escaped { cur.append(ch); escaped = false; continue }
            if ch == "\\", quote != "'" { escaped = true; continue }
            if let q = quote {
                if ch == q { quote = nil } else { cur.append(ch) }
                continue
            }
            if ch == "'" || ch == "\"" { quote = ch; continue }
            if ch == " " || ch == "\t" || ch == "\n" {
                if !cur.isEmpty { out.append(cur); cur = "" }
                continue
            }
            cur.append(ch)
        }
        if escaped { cur.append("\\") }
        if !cur.isEmpty { out.append(cur) }
        return out
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
                 totalBytes: Int64, parent: NSWindow?,
                 completion: (() -> Void)? = nil) -> ProgressWindowController? {
        var options = options

        // 「在覆盖前询问」和「不使用路径」是两件会悄悄丢数据的事，
        // 都在启动引擎之前问清楚。
        if options.overwrite == .ask || options.pathMode == .noPaths {
            let paths = ExtractGuard.entryPaths(archive: archive, password: options.password)
            if paths == nil, options.overwrite == .ask {
                // 读不出清单（缺密码、坏包）时不能猜。按「跳过已存在」走，
                // 引擎随后会把真正的原因报出来，总比静默覆盖掉文件好。
                options.overwrite = .skip
            }
            if let paths, options.overwrite == .ask {
                let hits = ExtractGuard.existing(
                    ExtractGuard.landingPaths(paths, names: names, options: options))
                if hits.isEmpty {
                    options.overwrite = .overwrite
                } else {
                    guard let choice = OverwritePrompt.resolve(
                        conflicts: hits, destination: options.destination, parent: parent)
                    else { return nil }
                    options.overwrite = choice
                }
            }
            if let paths, options.pathMode == .noPaths {
                let dup = ExtractGuard.duplicateNames(paths)
                if !dup.isEmpty {
                    let list = dup.prefix(10).joined(separator: "\n")
                    guard DialogKit.confirm(S.pathsNo, S.duplicateNamesNoPaths + "\n\n" + list,
                                            parent: parent) else { return nil }
                }
            }
        }

        let model = ProgressModel(kind: .extract, subject: (archive as NSString).lastPathComponent)
        model.totalBytes = totalBytes

        var args: [String] = [options.pathMode == .noPaths ? "e" : "x"]
        args.append("-o" + options.destination)
        args.append("-y")
        // 符号链接的危险判定分两级，源码里是两个不同的阈值：
        //   5  还是默认值，只看链接原文。见到第一个 ".." 就判危险，
        //      于是 "legal/x/LICENSE -> ../java.base/LICENSE" 这种标准写法
        //      被拒绝，位置留成 0 字节空文件，归档里 App 的签名随之失效。
        //   9  -snld 的默认值，改成拼上链接所在目录再算路径。上面那种问题
        //      没了，但还会检查「经由另一个链接」。mac 的 framework 都是
        //      "MPClasses -> Versions/Current/MPClasses" 套一层链接，
        //      于是又被判危险。
        //   10 跳过「经由另一个链接」这一条，同时保留越界路径检查：
        //      "../../../../../../../tmp/x" 仍然被拒。
        args.append("-snld10")
        if let ao = options.overwrite.argument { args.append(ao) }
        if options.pathMode == .absolute { args.append("-spf2") }
        if options.eliminateDuplicate { args.append("-spe") }
        if !options.password.isEmpty { args.append("-p" + options.password) }
        args.append("-bsp1")
        // -- 之后全是文件名。没有它，归档内以 - 或 @ 开头的条目会被当成
        // 开关或列表文件，解压和改名直接报 Command Line Error。
        args.append("--")
        args.append(archive)
        args.append(contentsOf: names)

        return launch(args: args, model: model, parent: parent, completion: completion)
    }

    // MARK: 压缩

    @discardableResult
    func add(archive: String, files: [String], workingDirectory: String, options: AddOptions,
             totalBytes: Int64, parent: NSWindow?,
             completion: (() -> Void)? = nil) -> ProgressWindowController {
        let model = ProgressModel(kind: .compress, subject: (archive as NSString).lastPathComponent)
        model.totalBytes = totalBytes
        model.outputBytes = 0

        let fmt = options.format
        // 各格式能接受的方法开关不是同一套。以下都是拿随包 7zz 逐个实测过的：
        //   7z / zip / xz      -m0=方法
        //   gzip / tar / bzip2 -mm=方法（-m0= 必报 E_INVALIDARG）
        //   wim / hash         不收方法开关
        // hash 还额外不收 -mx；它靠输出文件的扩展名决定算法（.sha1 / .sha256）。
        let methodFlag: String? = {
            switch fmt {
            case "7z", "zip", "xz": return "-m0="
            case "gzip", "tar", "bzip2": return "-mm="
            default: return nil
            }
        }()
        let isHash = fmt == "hash"
        let supportsOrder = !["tar", "bzip2", "wim", "hash"].contains(fmt)
        let supportsDict = ["7z", "zip", "xz"].contains(fmt)
        let supportsSolid = fmt == "7z" || fmt == "xz"
        let canEncrypt = fmt == "7z" || fmt == "zip"
        let canEncryptNames = fmt == "7z"

        var args = ["a", "-t" + fmt]
        if !isHash { args.append("-mx\(options.level.rawValue)") }
        if !options.method.isEmpty, let flag = methodFlag {
            args.append(flag + options.method)
        }
        if !options.dictionary.isEmpty, supportsDict {
            args.append("-md=" + options.dictionary)
        }
        // PPMd 的字长叫 order，开关是 -mo=；写 -mfb= 必报 E_INVALIDARG。
        if !options.wordSize.isEmpty, supportsOrder {
            args.append((options.method == "PPMd" ? "-mo=" : "-mfb=") + options.wordSize)
        }
        if !options.solidBlock.isEmpty, supportsSolid { args.append("-ms=" + options.solidBlock) }
        if !options.threads.isEmpty { args.append("-mmt=" + options.threads) }
        if !options.volumeSize.isEmpty { args.append("-v" + options.volumeSize) }
        if options.sharedFiles { args.append("-ssw") }
        // 不支持加密的格式带上 -p / -mhe=on 会直接报 E_INVALIDARG，
        // 而且会让用户以为文件被加密了。两种情形下都忽略密码。
        if !options.password.isEmpty, canEncrypt {
            args.append("-p" + options.password)
            if options.encryptFileNames, canEncryptNames { args.append("-mhe=on") }
        }
        if options.deleteAfter { args.append("-sdel") }
        args.append(contentsOf: options.advanced.arguments)
        if !options.parameters.isEmpty {
            args.append(contentsOf: CommandLineSplitting.split(options.parameters))
        }
        args.append(contentsOf: options.updateMode.arguments)
        args.append("-bsp1")
        args.append("--")
        args.append(archive)
        args.append(contentsOf: files)

        return launch(args: args, model: model, parent: parent,
                      workingDirectory: workingDirectory, outputPath: archive,
                      completion: completion)
    }

    // MARK: 测试

    @discardableResult
    func test(archives: [String], password: String?, totalBytes: Int64,
              parent: NSWindow?) -> ProgressWindowController {
        let subject: String
        if archives.count == 1 { subject = (archives[0] as NSString).lastPathComponent }
        else if let first = archives.first {
            subject = "\((first as NSString).lastPathComponent) +\(archives.count - 1)"
        } else { subject = "" }
        let model = ProgressModel(kind: .test, subject: subject)
        model.totalBytes = totalBytes

        func argsFor(_ a: String) -> [String] {
            var args = ["t", "-bsp1"]
            if let p = password, !p.isEmpty { args.append("-p" + p) }
            args.append("--")
            args.append(a)
            return args
        }

        guard !archives.isEmpty else {
            model.errors.append(S.mustSelectArchives)
            model.succeeded = false
            let wc = ProgressWindowController(model: model)
            keep(wc)
            wc.show()
            wc.finish()
            return wc
        }
        if archives.count == 1 {
            return launch(args: argsFor(archives[0]), model: model, parent: parent)
        }

        // 7zz 的 t 只收一个归档，第二个会被当成「要测的条目名」。实测
        // t a.7z corrupt.7z 回 exit=0 / Files: 0 / Everything is Ok，
        // 坏包被整个漏掉。多选取串行逐个测，结果合进同一个进度窗。
        let wc = ProgressWindowController(model: model)
        keep(wc)
        wc.show()
        var allOK = true

        func run(at i: Int) {
            guard i < archives.count else {
                model.succeeded = allOK && model.errors.isEmpty
                wc.finish()
                return
            }
            let task = EngineTask(arguments: argsFor(archives[i]))
            wc.attach(task)
            task.onMessage = { line in
                if line.hasPrefix("ERROR:") || line.hasPrefix("WARNING:") {
                    model.errors.append(line)
                }
            }
            task.onProgress = { p in
                model.update(percent: (i * 100 + p.percent) / archives.count,
                             file: p.currentFile)
            }
            task.onFinish = { [weak self] r in
                allOK = (self?.classify(r, model: model) ?? false) && allOK
                run(at: i + 1)
            }
            task.run()
        }
        run(at: 0)
        return wc
    }

    // MARK: 校验和（结果直接给一个文本窗口）

    func hash(files: [String], kind: HashKind, workingDirectory: String,
              parent: NSWindow?) {
        var args = ["h"]
        if let v = kind.switchValue { args.append("-scrc" + v) }
        args.append("--")
        args.append(contentsOf: files)

        DispatchQueue.global(qos: .userInitiated).async {
            // 文件系统那一路传进来的是相对名，必须给进程设工作目录。
            // 原来 runSync 没有这个参数，7zz 在默认目录里找不到文件，
            // 回 exit=1，结果窗口里只有 stderr。
            let result: Result<RunResult, Error>
            do {
                result = .success(try Engine.runSync(args, currentDirectory: workingDirectory))
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async {
                switch result {
                case .failure(let e):
                    TextWindow.show(title: S.calcChecksum, text: e.localizedDescription)
                case .success(let r):
                    // 7zz 的哈希行是 "AF083B2D   12  hello.txt"，里面没有 " = "。
                    // 原来按 " = " 过滤，窗口里只剩几条分隔线。整段原文都留着。
                    let out = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    let err = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    var text = out
                    if r.exitCode != 0, !err.isEmpty {
                        text += (text.isEmpty ? "" : "\n\n") + err
                    }
                    TextWindow.show(title: r.exitCode == 0 ? kind.title : S.calcChecksum,
                                    text: text.isEmpty ? err : text)
                }
            }
        }
    }

    // MARK: 归档内改名 / 删除

    @discardableResult
    func renameInArchive(archive: String, pairs: [(from: String, to: String)],
                         password: String?, parent: NSWindow?,
                         completion: (() -> Void)? = nil) -> ProgressWindowController {
        let model = ProgressModel(kind: .compress, subject: (archive as NSString).lastPathComponent)
        var args = ["rn", "-bsp1"]
        if let p = password, !p.isEmpty { args.append("-p" + p) }
        args.append("--")
        args.append(archive)
        for p in pairs { args.append(p.from); args.append(p.to) }
        return launch(args: args, model: model, parent: parent, completion: completion)
    }

    @discardableResult
    func deleteInArchive(archive: String, names: [String], password: String?,
                         parent: NSWindow?,
                         completion: (() -> Void)? = nil) -> ProgressWindowController {
        let model = ProgressModel(kind: .delete, subject: (archive as NSString).lastPathComponent)
        var args = ["d", "-bsp1", "-y"]
        if let p = password, !p.isEmpty { args.append("-p" + p) }
        args.append("--")
        args.append(archive)
        args.append(contentsOf: names)
        return launch(args: args, model: model, parent: parent, completion: completion)
    }

    // MARK: 复制 / 移动 / 删除（纯文件系统）

    @discardableResult
    func copyOrMove(_ urls: [URL], to destination: String, move: Bool,
                    parent: NSWindow?,
                    completion: (() -> Void)? = nil) -> ProgressWindowController {
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
                completion?()
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
        guard let r = try? Engine.runSync(["l", "-slt", "-ba", "--", path]) else { return 0 }
        var total: Int64 = 0
        r.stdout.enumerateLines { line, _ in
            guard line.hasPrefix("Size = ") else { return }
            if let n = Int64(line.dropFirst(7).trimmingCharacters(in: .whitespaces)) { total += n }
        }
        return total
    }

    // MARK: 拆分文件

    /// 拆分会产生 `<文件名>.7z` 和 `<文件名>.7z.001`… 这一组文件。
    /// 重做之前必须先清掉旧的：7zz 对多分卷归档不支持增量更新，直接再跑一次
    /// 只会回 "Updating for multivolume archives is not implemented"。
    /// 只认三位数字的分卷后缀，别把 `x.7z.backup` 也算进来。
    static func splitOutputs(for file: String) -> [String] {
        let dir = (file as NSString).deletingLastPathComponent
        let stem = (file as NSString).lastPathComponent + ".7z"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return names.filter { name in
            if name == stem { return true }
            guard name.hasPrefix(stem + ".") else { return false }
            let tail = name.dropFirst(stem.count + 1)
            return tail.count == 3 && tail.allSatisfy(\.isNumber)
        }.sorted().map { (dir as NSString).appendingPathComponent($0) }
    }

    @discardableResult
    func split(file: String, volumeBytes: Int64, parent: NSWindow?,
               completion: (() -> Void)? = nil) -> ProgressWindowController {
        let model = ProgressModel(kind: .split, subject: (file as NSString).lastPathComponent)
        model.totalBytes = Self.sizeOfItem(at: file)
        let dir = (file as NSString).deletingLastPathComponent
        let base = (file as NSString).lastPathComponent
        // 归档名给到 .7z 就行，.001 是引擎自己加的
        // （实测给 out.7z.001 会得到 out.7z.001.001）
        let args = ["a", "-t7z", "-mx0", "-v\(volumeBytes)b", "-bsp1", "--",
                    dir + "/" + base + ".7z", base]
        return launch(args: args, model: model, parent: parent, workingDirectory: dir,
                      completion: completion)
    }

    // MARK: 引擎任务统一驱动

    /// 把引擎的退出码与它自己写在输出里的话翻成进度窗里的错误。
    /// 返回这次调用算不算成功。
    private func classify(_ r: RunResult, model: ProgressModel) -> Bool {
        // 缺密码时不同命令给的退出码不一样：l -slt 回 255，t 回 2，
        // 但两者都会自己写 "Enter password:"。先按系统原文认这件事，
        // 再按退出码分类，免得把「要密码」报成中断或者丢一整段输出。
        if r.exitCode != 0 {
            let text = r.allText
            if text.contains("Enter password") || text.contains("Wrong password")
                || text.contains("Cannot open encrypted") {
                model.errors.append(S.cantOpenEncrypted
                    .replacingOccurrences(of: "'{0}'", with: "")
                    .replacingOccurrences(of: "{0}", with: ""))
                return false
            }
        }
        switch r.exitCode {
        case 0:
            break
        case 1:
            // exit=1 是 Warning。引擎未必写 "WARNING:" 前缀，先把系统
            // 自己写在输出里的 WARN 行找出来，读不到才给一句通用说明。
            if model.errors.isEmpty {
                let warn = r.allText.split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .last { $0.localizedCaseInsensitiveContains("warn") }
                if let w = warn, !w.isEmpty { model.errors.append(w) }
                else { model.errors.append("7-Zip: warning (exit 1)") }
            }
        case 255:
            // 走到这里说明不是缺密码，才是真的被中断（Break signaled）。
            model.errors.append(S.breakSignaled)
        case 8:
            model.errors.append(S.notEnoughMemory)
        default:
            // 进程没起来时 exitCode 是 -1。原来的 <= 1 会把它判成成功。
            // 这里一律带上引擎自己的原文，实在没有才给退出码。
            let tail = r.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let out = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = tail.isEmpty ? out : tail
            if model.errors.isEmpty, !message.isEmpty { model.errors.append(message) }
            if model.errors.isEmpty { model.errors.append("7-Zip: exit code \(r.exitCode)") }
        }
        return (r.exitCode == 0 || r.exitCode == 1) && model.errors.isEmpty
    }

    private func launch(args: [String], model: ProgressModel, parent: NSWindow?,
                        workingDirectory: String? = nil,
                        outputPath: String? = nil,
                        completion: (() -> Void)? = nil) -> ProgressWindowController {
        let wc = ProgressWindowController(model: model)
        keep(wc)

        let task = EngineTask(arguments: args, currentDirectory: workingDirectory)
        wc.attach(task)

        task.onProgress = { p in
            model.update(percent: p.percent, file: p.currentFile)
        }
        task.onMessage = { line in
            if line.hasPrefix("ERROR:") || line.hasPrefix("WARNING:") {
                model.errors.append(line)
            }
        }
        task.onFinish = { [weak self] r in
            model.succeeded = self?.classify(r, model: model) ?? false
            // 压缩率要用归档的真实路径去量。原来拿 model.subject（只有
            // 文件名）去 stat，永远取不到值，所以这一项一直不显示。
            if model.kind == .compress, let outputPath {
                let sz = Self.sizeOfItem(at: outputPath)
                if sz > 0 { model.outputBytes = sz }
            }
            wc.finish()
            completion?()
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
