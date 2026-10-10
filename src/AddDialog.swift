// 「Add to Archive」对话框。
//
// 字段、分组、可选项、启用规则逐条对着 Windows 版的
// CPP/7zip/UI/GUI/CompressDialog.rc 与 CompressDialog.cpp 摆。
// 这里出现的每个默认值都有出处，不是估的：
//
//   各格式能选的压缩级别   g_Formats[].LevelsMask 里置位的位
//   各格式的方法列表       g_Formats[].MethodIDs
//                          （7z 那条另按 SetMethod2 的 is7z 分支剔了 Copy / Deflate / Deflate64）
//   默认字典大小           CompressDialog.cpp 的 _auto_Dict 公式
//                          （与 C/LzmaEnc.c 的 LzmaEncProps_Normalize 同源）
//   默认字长               CompressDialog.cpp SetOrder2 里按方法给的 _auto_Order
//   默认固实块             SetSolidBlockSize2 里算的 blockSize
//   下拉项的写法与顺序      Combo_AddDict2 / Add_Size / AddOrder_Auto / AddVolumeItems
//   哪些开关真能用         对随包 7zz 逐个实测
//                          （-sni / -sns 在 macOS 上返回 E_NOTIMPL，所以不列出来）
//
// 与 Windows 版的两处差异，都是平台事实造成的：
//   * 没有「Create SFX archive」：macOS 包里没有 sfx 模块，
//     `7zz a -sfx` 实测报 "errno=2 : No such file or directory"。
//   * 没有「Memory usage for Compressing / Decompressing」两行：那两个数字是
//     GUI 在进程内问编解码器要的（SetMemoryUsage），命令行没有对应的查询开关。

import AppKit

// MARK: - 格式能力表

struct AddFormatSpec {
    /// 下拉里显示的名字，也是 g_Formats 里的名字
    let name: String
    /// 传给 -t 的类型名
    let arcType: String
    /// 允许的 -mx 值
    let levels: [Int]
    /// 方法列表，第 0 项同时是「自动」那一项
    let methods: [String]
    /// 默认扩展名
    let ext: String
    let solid: Bool
    let multiThread: Bool
    let encrypt: Bool
    let encryptFileNames: Bool

    /// 能创建的就这 8 种（zstd 在引擎里返回 E_NOTIMPL，也没进 g_Formats）。
    /// 格式下拉带 CBS_SORT，所以显示顺序按名字排。
    static let all: [AddFormatSpec] = [
        AddFormatSpec(name: "7z", arcType: "7z", levels: [0, 1, 3, 5, 7, 9],
                      methods: ["LZMA2", "LZMA", "PPMd", "BZip2"], ext: "7z",
                      solid: true, multiThread: true, encrypt: true, encryptFileNames: true),
        AddFormatSpec(name: "BZip2", arcType: "bzip2", levels: [1, 3, 5, 7, 9],
                      methods: ["BZip2"], ext: "bz2",
                      solid: false, multiThread: true, encrypt: false, encryptFileNames: false),
        AddFormatSpec(name: "GZip", arcType: "gzip", levels: [1, 5, 7, 9],
                      methods: ["Deflate"], ext: "gz",
                      solid: false, multiThread: false, encrypt: false, encryptFileNames: false),
        AddFormatSpec(name: "Hash", arcType: "hash", levels: [],
                      methods: ["SHA256", "SHA1"], ext: "sha256",
                      solid: false, multiThread: false, encrypt: false, encryptFileNames: false),
        AddFormatSpec(name: "Tar", arcType: "tar", levels: [0],
                      methods: ["GNU", "POSIX"], ext: "tar",
                      solid: false, multiThread: false, encrypt: false, encryptFileNames: false),
        AddFormatSpec(name: "wim", arcType: "wim", levels: [0],
                      methods: [], ext: "wim",
                      solid: false, multiThread: false, encrypt: false, encryptFileNames: false),
        AddFormatSpec(name: "xz", arcType: "xz", levels: [1, 3, 5, 7, 9],
                      methods: ["LZMA2"], ext: "xz",
                      solid: true, multiThread: true, encrypt: false, encryptFileNames: false),
        AddFormatSpec(name: "Zip", arcType: "zip", levels: [0, 1, 3, 5, 7, 9],
                      methods: ["Deflate", "Deflate64", "BZip2", "LZMA", "PPMd"], ext: "zip",
                      solid: false, multiThread: true, encrypt: true, encryptFileNames: false),
    ]

    static func named(_ n: String) -> AddFormatSpec {
        all.first { $0.name == n } ?? all[0]
    }

    var levelTitles: [CompressionLevel] {
        CompressionLevel.allCases.filter { levels.contains($0.rawValue) }
    }
}

// MARK: - 下拉项：显示文字 + 传给引擎的值

private struct Choice {
    let title: String
    /// nil = 自动，不加任何开关
    let value: String?

    static func auto(_ text: String) -> Choice { Choice(title: "*  " + text, value: nil) }
    static func one(_ text: String, _ value: String?) -> Choice { Choice(title: text, value: value) }
}

enum AddSpecs {

    /// 把字节数写成 Windows 版那个样子："1 GB" / "16 MB" / "64 KB"
    /// （Combo_AddDict2 / Add_Size 的进位顺序：先看 GB，再看 MB，再看 KB）
    static func sizeText(_ v: Int) -> String {
        if v % (1 << 30) == 0 { return "\(v >> 30) GB" }
        if v % (1 << 20) == 0 { return "\(v >> 20) MB" }
        if v % (1 << 10) == 0 { return "\(v >> 10) KB" }
        return "\(v) B"
    }

    /// 传给 -md / -ms 的写法：引擎只认带 k/m/g 后缀的量。
    /// 实测 `-md=33554432` 报 E_INVALIDARG，`-md=32m` 才行。
    static func byteArg(_ v: Int) -> String {
        if v % (1 << 30) == 0 { return "\(v >> 30)g" }
        if v % (1 << 20) == 0 { return "\(v >> 20)m" }
        return "\(v >> 10)k"
    }

    // MARK: 字典

    /// LZMA / LZMA2 的默认字典（CompressDialog.cpp:1941 的 _auto_Dict；
    /// 64 位下 sizeof(size_t)/2 == 4）
    static func autoDictionary(level: Int) -> Int {
        if level <= 4 { return 1 << (level * 2 + 16) }
        if level <= 8 { return 1 << (level + 20) }
        return 1 << 28
    }

    /// 字典下拉的候选值（CompressDialog.cpp 里生成 dict 列表的那段循环）
    static let dictionaries: [Int] = {
        var out: [Int] = []
        let maxDict = 15 << 28
        for i in (16 - 1) * 2 ... (32 - 1) * 2 {
            // 20 位以下只留 64 KB 和 128 KB 两档，1.5 MB 那档跳过
            if i < (20 - 1) * 2 && i != (16 - 1) * 2 && i != (18 - 1) * 2 { continue }
            if i == (20 - 1) * 2 + 1 { continue }
            let up = (2 + (i & 1)) << (i / 2)
            out.append(min(up, maxDict))
            if up >= (1 << 32) { break }
        }
        return out
    }()

    // MARK: 字长

    /// 字长的默认值（CompressDialog.cpp SetOrder2 里各方法的 _auto_Order）
    static func autoOrder(format: String, method: String, level: Int) -> Int? {
        switch method {
        case "LZMA", "LZMA2":
            return level < 7 ? 32 : 64
        case "Deflate", "Deflate64":
            if level >= 9 { return 128 }
            return level >= 7 ? 64 : 32
        case "PPMd":
            // zip 里的 PPMd 走的是另一套（kPPMdZip）
            if format == "Zip" { return level + 3 }
            if level >= 9 { return 32 }
            if level >= 7 { return 16 }
            if level >= 5 { return 6 }
            return 4
        default:
            return nil
        }
    }

    /// 字长下拉的候选值
    static func orders(format: String, method: String) -> [Int] {
        switch method {
        case "LZMA", "LZMA2":
            return [8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 273]
        case "Deflate":
            return [8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 258]
        case "Deflate64":
            return [8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 257]
        case "PPMd":
            return format == "Zip"
                ? Array(2...16)
                : [2, 3, 4, 5, 6, 7, 8, 10, 12, 14, 16, 20, 24, 28, 32]
        default:
            return []
        }
    }

    // MARK: 固实块

    /// LZMA2 的块大小（CompressDialog.cpp 的 Get_Lzma2_ChunkSize）
    private static func lzma2Chunk(_ dict: Int) -> Int {
        var cs = min(max(dict << 2, 1 << 20), 1 << 28)
        if cs < dict { cs = dict }
        return (cs + (1 << 20) - 1) & ~((1 << 20) - 1)
    }

    /// 固实块的默认值（SetSolidBlockSize2 里算出来的 blockSize）
    static func autoSolid(format: String, method: String, dict: Int) -> Int {
        let cs = lzma2Chunk(dict)
        guard format == "7z" else { return cs }
        var block: Int
        if method == "LZMA2" {
            block = cs << 6
        } else {
            var d2 = dict
            if method == "BZip2" { d2 = (d2 / 100_000) * 100_000 }
            block = d2 << 7
        }
        let cap = method == "LZMA2" ? (1 << 34) : (1 << 32)
        return min(max(block, 1 << 24), cap)
    }

    /// 固实块下拉的候选值：1 MB 到 64 GB
    static let solidSizes: [Int] = (20...36).map { 1 << $0 }

    // MARK: 线程

    /// 该方法最多能用几个线程（SetNumThreads2 里的 numAlgoThreadsMax）
    static func maxThreads(format: String, method: String, hardware: Int) -> Int {
        if format == "Zip" { return 128 }   // 8 << sizeof(size_t)/2，64 位下是 128
        if format == "xz" { return 512 }
        switch method {
        case "LZMA2": return 512
        case "LZMA": return 2
        case "BZip2": return 64
        case "Copy", "PPMd", "Deflate", "Deflate64", "GNU", "POSIX": return 1
        default: return hardware * 2
        }
    }

    // MARK: 其它

    /// 分卷下拉（AddVolumeItems 的 k_Sizes）。显示里 " - CD" 那半截只是说明，
    /// 传给 -v 的只有前半截（ParseVolumeSizes 遇到 '-' 就停）。
    static let volumes: [(title: String, value: String)] = [
        ("10M", "10M"), ("100M", "100M"), ("1000M", "1000M"),
        (S.volCD650, "650M"), (S.volCD700, "700M"),
        (S.volFat4092, "4092M"), (S.volDvd4480, "4480M"),
        (S.volDvdDl8128, "8128M"), (S.volBd23040, "23040M"),
    ]

    /// 加密方法（SetEncryptionMethod）
    static func encryptionMethods(format: String) -> [String] {
        switch format {
        case "7z": return ["AES-256"]
        case "Zip": return ["ZipCrypto", "AES-256"]
        default: return []
        }
    }
}

// MARK: - 对话框

final class AddDialog {

    /// 默认归档名（不含扩展名）。
    ///
    /// 单个目标沿用「它自己的名字」—— 和访达、和 Windows 版都一致。
    /// 多个目标不能用所在目录的名字：在 `Download` 里压两个 NDS 文件会得到
    /// `Download.7z`，既看不出装的是什么，又和同级那个 `Download` 目录混在一起。
    /// 改成固定词加时间戳。
    static func defaultName(targets: [String]) -> String {
        if targets.count == 1 {
            return ((targets[0] as NSString).lastPathComponent as NSString).deletingPathExtension
        }
        let f = DateFormatter()
        // 固定用 en_US_POSIX：这个名字要跨语言一致，不能跟着区域设置变成 2026年10月8日
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH.mm"
        return "\(S.defaultArchiveWord) \(f.string(from: Date()))"
    }

    static func run(targets: [String], inWorkingDir: String, totalBytes: Int64,
                    parent: NSWindow?) -> (String, AddOptions)? {
        _ = totalBytes
        let ctrl = AddDialogController(workingDirectory: inWorkingDir,
                                       baseName: defaultName(targets: targets))
        return ctrl.runModal(parent: parent)
    }
}

private final class AddDialogController {

    private var folder: String
    private var name: String

    private var spec = AddFormatSpec.named("7z")
    private var level = CompressionLevel.normal
    private var advanced = AdvancedOptions()

    // 左列
    private let folderLabel = DialogKit.label("")
    private let nameCombo = NSComboBox()
    private let browseButton = NSButton(title: "...", target: nil, action: nil)
    private lazy var formatCombo = DialogKit.combo(AddFormatSpec.all.map(\.name), width: 170)
    private lazy var levelCombo = DialogKit.combo([], width: 170)
    private lazy var methodCombo = DialogKit.combo([], width: 170)
    private lazy var dictCombo = DialogKit.combo([], width: 170)
    private lazy var orderCombo = DialogKit.combo([], width: 170)
    private lazy var solidCombo = DialogKit.combo([], width: 170)
    private lazy var threadCombo = DialogKit.combo([], width: 110)
    private let threadInfo = DialogKit.label("")
    private lazy var volumeCombo = DialogKit.editCombo(AddSpecs.volumes.map(\.title), width: 260)
    private let paramsField = NSTextField(string: "")
    private let optionsButton = NSButton(title: S.addOptionsButton, target: nil, action: nil)
    private let optionsInfo = DialogKit.label("")

    // 右列
    private lazy var updateCombo = DialogKit.combo(UpdateMode.allCases.map(\.title), width: 170)
    private lazy var pathCombo = DialogKit.combo(
        [S.pathModeRelative, S.pathModeFull, S.pathModeAbs], width: 170)
    private let sharedCheck = DialogKit.check(S.addShared, false)
    private let deleteCheck = DialogKit.check(S.addDeleteAfter, false)
    private let pw1 = NSSecureTextField(string: "")
    private let pw2 = NSSecureTextField(string: "")
    private let plainPw = NSTextField(string: "")
    private let showPwCheck = DialogKit.check(S.addShowPassword, false)
    private lazy var encCombo = DialogKit.combo([], width: 150)
    private let encNamesCheck = DialogKit.check(S.addEncryptFileNames, false)

    // 每个下拉当前的内容，取选中项的值时要对着它读
    private var levelChoices: [Choice] = []
    private var methodChoices: [Choice] = []
    private var dictChoices: [Choice] = []
    private var orderChoices: [Choice] = []
    private var solidChoices: [Choice] = []
    private var threadChoices: [Choice] = []
    private var encChoices: [Choice] = []

    init(workingDirectory: String, baseName: String) {
        self.folder = workingDirectory
        self.name = "\(baseName).7z"
    }

    // MARK: 跑起来

    func runModal(parent: NSWindow?) -> (String, AddOptions)? {
        fill()
        var form = buildForm()
        // 下面几个闭包要拿窗口，先把窗口取出来，别在闭包里再碰 form
        let sheet = form.window

        DialogKit.Action.attach(formatCombo, form: &form) { [weak self] _ in
            self?.formatChanged()
        }
        DialogKit.Action.attach(levelCombo, form: &form) { [weak self] _ in
            self?.levelChanged()
        }
        DialogKit.Action.attach(methodCombo, form: &form) { [weak self] _ in
            self?.methodChanged()
        }
        DialogKit.Action.attach(browseButton, form: &form) { [weak self] _ in
            self?.browse()
        }
        DialogKit.Action.attach(optionsButton, form: &form) { [weak self] _ in
            guard let self else { return }
            if let a = AdvancedDialog.run(flags: self.advanced, parent: sheet) {
                self.advanced = a
                self.showOptionsInfo()
            }
        }
        DialogKit.Action.attach(showPwCheck, form: &form) { [weak self] _ in
            self?.toggleShowPassword()
        }

        guard DialogKit.runModal(form, parent: parent) else { return nil }

        if pw1.stringValue != pw2.stringValue {
            DialogKit.alert(S.addPasswordsDoNotMatch, "", style: .warning, parent: parent)
            return nil
        }

        // 目标已经存在时问一次。默认的 update 模式是「把新文件并进旧包」，
        // 这是一件在很多情况下都不是用户本意、而且事后完全看不出来的事，
        // 所以不能闷头做。
        var archive = resolveArchivePath()
        while FileManager.default.fileExists(atPath: archive) {
            guard let i = DialogKit.choose(archive, S.archiveExistsMessage,
                                           buttons: [S.mergeIntoArchive, S.chooseAnotherName],
                                           parent: parent) else { return nil }
            if i == 0 { break }                     // 并入
            guard let renamed = DialogKit.prompt(S.addTitle, caption: S.addArchive,
                                                 initial: nameCombo.stringValue,
                                                 parent: parent) else { return nil }
            nameCombo.stringValue = renamed
            archive = resolveArchivePath()
        }

        var o = AddOptions()
        o.format = spec.arcType
        o.level = level
        o.method = value(of: methodCombo, in: methodChoices) ?? ""
        o.dictionary = value(of: dictCombo, in: dictChoices) ?? ""
        o.wordSize = value(of: orderCombo, in: orderChoices) ?? ""
        o.solidBlock = value(of: solidCombo, in: solidChoices) ?? ""
        o.threads = value(of: threadCombo, in: threadChoices) ?? ""
        let vol = volumeCombo.stringValue.trimmingCharacters(in: .whitespaces)
        // 下拉里的是 "650M - CD" 这种，真正要传的只有前半截
        o.volumeSize = vol.range(of: " - ").map { String(vol[vol.startIndex..<$0.lowerBound]) } ?? vol
        o.parameters = paramsField.stringValue.trimmingCharacters(in: .whitespaces)
        o.updateMode = UpdateMode(rawValue: updateCombo.indexOfSelectedItem) ?? .update
        o.deleteAfter = deleteCheck.state == .on
        o.sharedFiles = sharedCheck.state == .on
        o.password = showPwCheck.state == .on ? plainPw.stringValue : pw1.stringValue
        o.encryptFileNames = encNamesCheck.state == .on
        o.advanced = advanced
        return (archive, o)
    }

    // MARK: 组装界面

    private func buildForm() -> DialogKit.Form {
        let left = FormBuilder()
        // 归档名上面那行只显示所在目录（对应 IDT_COMPRESS_ARCHIVE_FOLDER）
        left.add("", folderLabel)
        let arcRow = NSStackView(views: [nameCombo, browseButton])
        arcRow.orientation = .horizontal
        arcRow.spacing = 6
        left.add(S.addArchive, arcRow)
        left.add(S.addArchiveFormat, formatCombo)
        left.add(S.addCompressionLevel, levelCombo)
        left.add(S.addCompressionMethod, methodCombo)
        left.add(S.addDictionarySize, dictCombo)
        left.add(S.addWordSize, orderCombo)
        left.add(S.addSolidBlockSize, solidCombo)
        let threadRow = NSStackView(views: [threadCombo, threadInfo])
        threadRow.orientation = .horizontal
        threadRow.spacing = 8
        left.add(S.addThreads, threadRow)
        let optionRow = NSStackView(views: [optionsButton, optionsInfo])
        optionRow.orientation = .horizontal
        optionRow.spacing = 10

        // Windows 里「Split to volumes」和「Parameters」不是标签在左的那种行：
        // 标签在上，输入框从最左边起、占满左列（CompressDialog.rc 里它们的 x 就是 m）
        let volumeBlock = labelAbove(S.addSplitVolumes, volumeCombo)
        let paramsBlock = labelAbove(S.addParameters, paramsField)

        let leftColumn = NSStackView(views: [
            left.makeView(labelWidth: 165), volumeBlock, paramsBlock, optionRow,
        ])
        leftColumn.orientation = .vertical
        leftColumn.alignment = .leading
        leftColumn.spacing = 8

        let right = FormBuilder()
        right.add(S.addUpdateMode, updateCombo)
        right.add(S.addPathMode, pathCombo)

        let optionBox = DialogKit.groupBox(S.addGroupOptions,
                                           [sharedCheck, deleteCheck].verticalStack())
        optionBox.widthAnchor.constraint(equalToConstant: Self.rightWidth).isActive = true
        plainPw.isHidden = true
        plainPw.font = NSFont.systemFont(ofSize: 12)
        plainPw.widthAnchor.constraint(equalToConstant: 170).isActive = true
        let pw1Row = NSStackView(views: [pw1, plainPw])
        pw1Row.orientation = .horizontal
        pw1Row.alignment = .centerY
        pw1Row.spacing = 0
        let encStack = NSStackView(views: [
            pwWithLabel(S.addEnterPassword, pw1Row), pwWithLabel(S.addReenterPassword, pw2),
            showPwCheck, encMethodRow(), encNamesCheck,
        ])
        encStack.orientation = .vertical
        encStack.alignment = .leading
        encStack.spacing = 6
        let encBox = DialogKit.groupBox(S.addGroupEncryption, encStack)
        encBox.widthAnchor.constraint(equalToConstant: Self.rightWidth).isActive = true

        let rightColumn = NSStackView(views: [
            right.makeView(labelWidth: 100), optionBox, encBox,
        ])
        rightColumn.orientation = .vertical
        rightColumn.alignment = .leading
        rightColumn.spacing = 12

        // 两栏各按自己的自然高度。宽度写死在里面：让容器自己撑开的话，
        // 窗口会按 fittingSize 缩到算错的值。
        let columns = DialogKit.columns([leftColumn, rightColumn],
                                         widths: [Self.leftWidth, Self.rightWidth], spacing: 30)

        return DialogKit.makeSheet(title: S.addTitle, content: columns,
                                   width: Self.leftWidth + 30 + Self.rightWidth + 36)
    }

    private static let leftWidth: CGFloat = 430
    private static let rightWidth: CGFloat = 330

    private func pwWithLabel(_ text: String, _ field: NSView) -> NSView {
        let label = DialogKit.label(text)
        let stack = NSStackView(views: [label, field])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        return stack
    }

    /// 标签在上、控件在下的一小块
    private func labelAbove(_ text: String, _ field: NSView) -> NSView {
        DialogKit.labelAbove(text, field)
    }

    private func encMethodRow() -> NSView {
        let label = DialogKit.label(S.addEncryptionMethod)
        let row = NSStackView(views: [label, encCombo])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }

    // MARK: 初值

    private func fill() {
        folderLabel.font = NSFont.systemFont(ofSize: 11)
        folderLabel.textColor = .secondaryLabelColor
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.stringValue = folder
        folderLabel.toolTip = folder

        nameCombo.font = NSFont.systemFont(ofSize: 12)
        nameCombo.addItem(withObjectValue: name)
        nameCombo.stringValue = name
        nameCombo.widthAnchor.constraint(equalToConstant: 200).isActive = true

        browseButton.bezelStyle = .rounded
        browseButton.widthAnchor.constraint(equalToConstant: 32).isActive = true

        for c in [formatCombo, levelCombo, methodCombo, dictCombo, orderCombo,
                  solidCombo, threadCombo, updateCombo, pathCombo, encCombo] {
            c.font = NSFont.systemFont(ofSize: 12)
        }
        volumeCombo.stringValue = ""
        paramsField.font = NSFont.systemFont(ofSize: 12)
        paramsField.widthAnchor.constraint(equalToConstant: 260).isActive = true
        optionsButton.bezelStyle = .rounded
        optionsInfo.font = NSFont.systemFont(ofSize: 11)
        optionsInfo.textColor = .secondaryLabelColor
        threadInfo.font = NSFont.systemFont(ofSize: 11)
        threadInfo.textColor = .secondaryLabelColor

        formatCombo.selectItem(withTitle: spec.name)
        levelCombo.selectItem(withTitle: level.title)
        updateCombo.selectItem(at: UpdateMode.update.rawValue)
        pathCombo.selectItem(at: 0)
        pw1.font = NSFont.systemFont(ofSize: 12)
        pw2.font = NSFont.systemFont(ofSize: 12)
        pw1.widthAnchor.constraint(equalToConstant: 170).isActive = true
        pw2.widthAnchor.constraint(equalToConstant: 170).isActive = true

        refreshAll()
        showOptionsInfo()

        // 开发用：--add-format / --add-level 直接切过去，方便截图核对各格式的界面
        if let f = LaunchArgs.addFormat, let idx = formatCombo.itemTitles.firstIndex(of: f) {
            formatCombo.selectItem(at: idx)
            formatChanged()
        }
        if let l = LaunchArgs.addLevel, let idx = levelCombo.itemTitles.firstIndex(of: l) {
            levelCombo.selectItem(at: idx)
            levelChanged()
        }
    }

    /// 格式一改，级别 / 方法 / 字典 / 字长 / 固实块 / 线程 / 加密方法全要重算，
    /// 与 FormatChanged() 做的事对应
    private func refreshAll() {
        refreshLevels()
        refreshMethods()
        refreshDictionary()
        refreshOrder()
        refreshSolid()
        refreshThreads()
        refreshEncryption()
    }

    private func formatChanged() {
        guard let newName = formatCombo.titleOfSelectedItem else { return }
        let old = spec
        spec = AddFormatSpec.named(newName)
        // 归档名跟着换扩展名，但只在用户没改过扩展名的时候
        let current = nameCombo.stringValue
        let stem = (current as NSString).deletingPathExtension
        let ext = (current as NSString).pathExtension
        if ext.isEmpty || ext.caseInsensitiveCompare(old.ext) == .orderedSame {
            nameCombo.stringValue = "\(stem).\(spec.ext)"
        }
        refreshAll()
    }

    private func levelChanged() {
        guard let v = value(of: levelCombo, in: levelChoices),
              let mx = Int(v), let lv = CompressionLevel(rawValue: mx) else { return }
        level = lv
        // SetLevel 之后要重排方法 / 字典 / 字长 / 固实块 / 线程
        refreshMethods()
        refreshDictionary()
        refreshOrder()
        refreshSolid()
        refreshThreads()
    }

    private func methodChanged() {
        refreshDictionary()
        refreshOrder()
        refreshSolid()
        refreshThreads()
    }

    // MARK: 各下拉的内容

    /// 当前选择的方法名；级别为 Store 时 7z 这类格式的方法框是空的
    private var chosenMethod: String {
        if let v = value(of: methodCombo, in: methodChoices) { return v }
        return spec.methods.first ?? ""
    }

    private func refreshLevels() {
        levelChoices = spec.levelTitles.map { .one($0.title, "\($0.rawValue)") }
        set(levelCombo, levelChoices)
        // 换格式后原级别可能不存在，退到 Normal
        if !spec.levels.contains(level.rawValue) {
            level = spec.levelTitles.contains(.normal) ? .normal : (spec.levelTitles.first ?? .store)
        }
        if let idx = levelChoices.firstIndex(where: { $0.value == "\(level.rawValue)" }) {
            levelCombo.selectItem(at: idx)
        }
        levelCombo.isEnabled = levelChoices.count > 1
    }

    private func refreshMethods() {
        // 级别为 Store 且不是 tar / Hash 时，方法框留空（SetMethod2 提前返回）
        let empty = level == .store && spec.name != "Tar" && spec.name != "Hash"
        if empty || spec.methods.isEmpty {
            methodChoices = []
        } else {
            methodChoices = [.auto(spec.methods[0])]
                + spec.methods.dropFirst().map { .one($0, $0) }
        }
        set(methodCombo, methodChoices)
    }

    private func refreshDictionary() {
        guard ["LZMA", "LZMA2"].contains(chosenMethod) else {
            dictChoices = []
            set(dictCombo, dictChoices)
            return
        }
        let auto = AddSpecs.autoDictionary(level: level.rawValue)
        dictChoices = [.auto(AddSpecs.sizeText(auto))]
            + AddSpecs.dictionaries.map { .one(AddSpecs.sizeText($0), AddSpecs.byteArg($0)) }
        set(dictCombo, dictChoices)
    }

    private func refreshOrder() {
        let m = chosenMethod
        guard let auto = AddSpecs.autoOrder(format: spec.name, method: m, level: level.rawValue) else {
            orderChoices = []
            set(orderCombo, orderChoices)
            return
        }
        orderChoices = [.auto("\(auto)")]
            + AddSpecs.orders(format: spec.name, method: m).map { .one("\($0)", "\($0)") }
        set(orderCombo, orderChoices)
    }

    private func refreshSolid() {
        guard spec.solid, level != .store else {
            solidChoices = []
            set(solidCombo, solidChoices)
            return
        }
        let auto = AddSpecs.autoSolid(format: spec.name, method: chosenMethod, dict: dictBytes())
        var list: [Choice] = [.auto(AddSpecs.sizeText(auto))]
        if spec.name == "7z" { list.append(.one(S.solidNonSolid, "off")) }
        list.append(contentsOf: AddSpecs.solidSizes.map {
            .one(AddSpecs.sizeText($0), AddSpecs.byteArg($0))
        })
        list.append(.one(S.solidFull, "on"))
        solidChoices = list
        set(solidCombo, solidChoices)
    }

    private func refreshThreads() {
        let hw = ProcessInfo.processInfo.activeProcessorCount
        guard spec.multiThread else {
            threadChoices = []
            set(threadCombo, threadChoices)
            threadInfo.stringValue = ""
            return
        }
        let auto = min(hw, AddSpecs.maxThreads(format: spec.name, method: chosenMethod, hardware: hw))
        threadChoices = [.auto("\(auto)")] + (1...max(hw, 1)).map { .one("\($0)", "\($0)") }
        set(threadCombo, threadChoices)
        threadInfo.stringValue = "/ \(hw)"
    }

    private func refreshEncryption() {
        let methods = AddSpecs.encryptionMethods(format: spec.name)
        encChoices = methods.map { .one($0, $0) }
        set(encCombo, encChoices)
        let on = spec.encrypt
        pw1.isEnabled = on
        pw2.isEnabled = on
        showPwCheck.isEnabled = on
        encCombo.isEnabled = on
        encNamesCheck.isEnabled = spec.encryptFileNames
        encNamesCheck.isHidden = !spec.encryptFileNames
        // 密码框的可编辑状态单独由 showPw 决定
        toggleShowPassword()
    }

    private func autoDictBytes() -> Int {
        AddSpecs.autoDictionary(level: level.rawValue)
    }

    /// 字典下拉当前选中的字节数；选了「自动」就用公式算出来的那个
    private func dictBytes() -> Int {
        guard let v = value(of: dictCombo, in: dictChoices), !v.isEmpty else {
            return autoDictBytes()
        }
        if v.hasSuffix("g") { return (Int(v.dropLast()) ?? 0) << 30 }
        if v.hasSuffix("m") { return (Int(v.dropLast()) ?? 0) << 20 }
        if v.hasSuffix("k") { return (Int(v.dropLast()) ?? 0) << 10 }
        return Int(v) ?? autoDictBytes()
    }

    // MARK: 小工具

    private func set(_ popup: NSPopUpButton, _ choices: [Choice]) {
        popup.removeAllItems()
        popup.addItems(withTitles: choices.map(\.title))
        popup.isEnabled = !choices.isEmpty
        if !choices.isEmpty { popup.selectItem(at: 0) }
    }

    private func value(of popup: NSPopUpButton, in choices: [Choice]) -> String? {
        let i = popup.indexOfSelectedItem
        guard i >= 0, i < choices.count else { return nil }
        return choices[i].value
    }

    private func toggleShowPassword() {
        let show = showPwCheck.state == .on
        plainPw.stringValue = pw1.stringValue
        plainPw.isHidden = !show
        pw1.isHidden = show
        pw2.isEnabled = !show
    }

    private func showOptionsInfo() {
        var parts: [String] = []
        if advanced.symLinks { parts.append(S.optSymLinks) }
        if advanced.hardLinks { parts.append(S.optHardLinks) }
        if advanced.storeCTime { parts.append(S.optCTime) }
        if advanced.storeATime { parts.append(S.optATime) }
        if !advanced.storeMTime { parts.append(S.optNoMTime) }
        if advanced.archiveTimeLatest { parts.append(S.optArchiveTimeLatest) }
        if advanced.preserveATime { parts.append(S.optKeepATime) }
        optionsInfo.stringValue = parts.joined(separator: ", ")
    }

    private func browse() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = nameCombo.stringValue
        panel.directoryURL = URL(fileURLWithPath: folder)
        if panel.runModal() == .OK, let u = panel.url {
            folder = u.deletingLastPathComponent().path
            nameCombo.stringValue = u.lastPathComponent
            folderLabel.stringValue = folder
            folderLabel.toolTip = folder
        }
    }

    /// 输入框里只放文件名时用上面显示的目录补全；用户直接粘了绝对路径也认
    private func resolveArchivePath() -> String {
        let typed = nameCombo.stringValue.trimmingCharacters(in: .whitespaces)
        if typed.hasPrefix("/") { return typed }
        return (folder as NSString).appendingPathComponent(typed)
    }
}

// MARK: - Options 那一层（CompressOptionsDialog.rc）

enum AdvancedDialog {

    static func run(flags: AdvancedOptions, parent: NSWindow?) -> AdvancedOptions? {
        var f = flags
        let sym = DialogKit.check(S.addStoreSymLinks, f.symLinks)
        let hard = DialogKit.check(S.addStoreHardLinks, f.hardLinks)
        let mt = DialogKit.check(S.addStoreMTime, f.storeMTime)
        let ct = DialogKit.check(S.addStoreCTime, f.storeCTime)
        let at = DialogKit.check(S.addStoreATime, f.storeATime)
        let latest = DialogKit.check(S.addArchiveTimeLatest, f.archiveTimeLatest)
        let keepAt = DialogKit.check(S.addPreserveATime, f.preserveATime)

        let links = DialogKit.groupBox(S.addGroupLinks, [sym, hard].verticalStack())
        let time = DialogKit.groupBox(S.addGroupTime,
                                      [mt, ct, at, latest, keepAt].verticalStack())
        let columns = DialogKit.columns([links, time], widths: [340, 340], spacing: 20)

        let form = DialogKit.makeSheet(title: S.addOptionsButton, content: columns, width: 736)
        guard DialogKit.runModal(form, parent: parent) else { return nil }

        f.symLinks = sym.state == .on
        f.hardLinks = hard.state == .on
        f.storeMTime = mt.state == .on
        f.storeCTime = ct.state == .on
        f.storeATime = at.state == .on
        f.archiveTimeLatest = latest.state == .on
        f.preserveATime = keepAt.state == .on
        return f
    }
}
