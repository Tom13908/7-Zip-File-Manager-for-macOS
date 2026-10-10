// 数据模型：文件/归档条目、路径解析、显示格式化。

import Foundation

// MARK: - 随包资源的查找根
//
// 打包运行（Contents/MacOS 里的可执行文件）时用 Contents/Resources；
// 直接跑一个散装可执行文件时（调试用）用可执行文件所在目录。

enum Res {
    static var root: URL {
        let b = Bundle.main
        if b.bundleIdentifier == nil { return b.bundleURL }
        return b.resourceURL ?? b.bundleURL
    }

    static func url(_ name: String, ext: String, subdir: String? = nil) -> URL? {
        let file = ext.isEmpty ? name : "\(name).\(ext)"
        let dir = subdir.map { root.appendingPathComponent($0) } ?? root
        let u = dir.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }
}

// MARK: - 归档类型表（由 7zz 自己的格式表生成，见 tools/mkarchive_types.py）
//
// 表改成首次用到时再读（static let 由 Swift 运行时保证只初始化一次，且线程安全）。
// 这不是顺手优化，是修一个真实故障：
//
//   从 Finder 双击归档时，AppKit 的顺序是
//       willFinishLaunching -> open(文件) -> didFinishLaunching
//   「打开文件」比 didFinishLaunching 早，而 Location.isArchive 要查这张表。
//   以前把 load() 放在 didFinishLaunching 里，双击进来的那一次表还是空的，
//   归档被当成普通文件、面板按目录去读 —— 现象是窗口开了、列表一片空白。
//   只有双击这条路会中招：右键服务那条不查这张表，所以看起来是「解压能用、
//   双击打开不能用」。
//
// 惰性加载之后，谁先用到谁触发，启动顺序不再影响结果。

enum ArchiveTypes {

    private struct Table {
        var extensions: Set<String> = []
        var iconByExt: [String: String] = [:]
    }

    private static let table: Table = readTable()

    /// 显式预热。现在只是把惰性表读出来；留着是为了让「表读不出来」这件事
    /// 在启动时就能在日志里留下痕迹，而不是等用户点开某个目录才发现。
    static func load() { _ = table }

    private static func readTable() -> Table {
        var t = Table()
        guard let url = Res.url("archive_types", ext: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            // 这张表读不出来，等于所有归档都认不出来（列表不上归档图标、
            // 服务那边也会把归档当成普通文件）。必须留下痕迹，不能静默降级。
            NSLog("7zip: archive_types.json 读取失败，归档类型表为空")
            return t
        }
        if let list = obj["extensions"] as? [String] {
            t.extensions = Set(list.map { $0.lowercased() })
        }
        if let map = obj["byExt"] as? [String: String] {
            t.iconByExt = map.mapValues { $0.lowercased() }
        }
        return t
    }

    static func isArchiveExtension(_ ext: String) -> Bool {
        table.extensions.contains(ext.lowercased())
    }

    /// 该扩展名对应的图标名（resources/icons/archive/<name>.png）
    static func iconName(forExtension ext: String) -> String? {
        table.iconByExt[ext.lowercased()]
    }
}

// MARK: - 列表里的一行

struct FileEntry {
    var name: String
    /// 归档内部路径（"/" 分隔）或文件系统绝对路径
    var fullPath: String
    var isDir: Bool
    var isArchive: Bool
    /// 「..」那一行（Windows 版 PanelItems.cpp 的 kParentIndex）：
    /// 它只是个导航入口，不算本目录的条目，所有针对条目的操作都跳过它。
    var isParent: Bool = false
    var archiveIcon: String?
    var size: Int64 = 0
    var packedSize: Int64 = -1
    var mtime: Date?
    var ctime: Date?
    var atime: Date?
    var attributes: String = ""
    var crc: String = ""
    var method: String = ""
    var encrypted: String = ""
    var comment: String = ""
    var solid: String = ""
    var block: String = ""
    var hostOS: String = ""
    var version: String = ""
    var offset: String = ""

    /// 排序用的扩展名（对应 7-Zip 的 kpidExtension，"按类型排序"用它）
    var fileExtension: String {
        let n = name
        guard let dot = n.lastIndex(of: "."), dot != n.startIndex else { return "" }
        return String(n[n.index(after: dot)...])
    }

    static func == (a: FileEntry, b: FileEntry) -> Bool { a.fullPath == b.fullPath && a.name == b.name }
}

// MARK: - 当前浏览位置
//
// 用一条字符串路径表示，和 Windows 版一样：文件系统是 /Users/x/y，
// 归档里就是 /Users/x/y.7z/inner/dir。root 是被打开的那个东西（目录或归档文件）。

struct Location: Equatable {
    /// 文件系统上的路径：目录，或归档文件本身
    var root: String
    /// 若 root 是归档，这里是归档内部的路径（"" 表示归档根）
    var inner: String = ""
    /// 临时解出来的归档（归档套归档时用），退出时要清理
    var temporary: Bool = false

    var isArchive: Bool { !inner.isEmpty || Location.isArchiveFile(root) }

    var display: String {
        var s = root
        // 根目录的斜杠不能削（"/" 会变成空串，地址栏就什么都不显示了）
        if s.count > 1 && s.hasSuffix("/") { s.removeLast() }
        if !inner.isEmpty {
            s += "/" + inner
        }
        return s
    }

    static func isArchiveFile(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension
        return ArchiveTypes.isArchiveExtension(ext)
    }

    var parent: Location? {
        if !inner.isEmpty {
            var comps = inner.split(separator: "/").map(String.init)
            comps.removeLast()
            var p = self
            p.inner = comps.joined(separator: "/")
            return p
        }
        let parent = (root as NSString).deletingLastPathComponent
        guard !parent.isEmpty, parent != root, root != "/" else { return nil }
        var p = self
        p.root = parent
        p.temporary = false
        return p
    }
}

// MARK: - 路径解析

enum Resolver {

    /// 把一条显示路径切成 (root, inner)。逐段判断该段是目录还是归档文件。
    static func parse(_ path: String) -> Location? {
        var p = path
        if p.isEmpty { p = "/" }
        if !p.hasPrefix("/") { p = "/" + p }

        var current = Location(root: "/")
        var pending: [String] = []

        for comp in p.split(separator: "/").map(String.init) {
            if !pending.isEmpty {
                pending.append(comp)
                continue
            }
            let candidate = current.root == "/" ? "/" + comp : current.root + "/" + comp
            let fm = FileManager.default
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: candidate, isDirectory: &isDir) else {
                return nil
            }
            if isDir.boolValue {
                current.root = candidate
            } else {
                // 归档文件：剩下的都算归档内部路径
                current.root = candidate
                current.inner = ""
                pending.append("")
            }
        }

        if !pending.isEmpty {
            current.inner = pending.filter { !$0.isEmpty }.joined(separator: "/")
        }
        return current
    }

    /// 用户地址栏里手打一个路径时用：宽松一点，末尾斜杠、~ 都接受
    static func parseLoose(_ input: String) -> Location? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if s.hasPrefix("~") { s = (s as NSString).expandingTildeInPath }
        return parse(s)
    }
}

// MARK: - 显示格式化（对齐 Windows 版 7-Zip File Manager 的样式）

enum Fmt {

    /// 文件大小按 macOS 的十进制进位显示（1 KB = 1000 B），跟 Finder 对得上。
    /// 不到 1 KB 就写字节数；再往上一律一位小数，正好是整数时不带小数点（"2 MB" 而非 "2.0 MB"）。
    /// 进位按四舍五入后的值判断，免得出现 "1000 KB" 这种本该再进一位的边界值。
    static func size(_ n: Int64) -> String {
        guard n >= 0 else { return "" }
        if n < 1000 { return "\(n) B" }
        let units = ["KB", "MB", "GB", "TB", "PB"]
        var value = Double(n)
        var idx = -1
        repeat {
            value /= 1000
            idx += 1
        } while value >= 999.95 && idx < units.count - 1
        let tenths = Int((value * 10).rounded())
        if tenths % 10 == 0 { return "\(tenths / 10) \(units[idx])" }
        return "\(tenths / 10).\(tenths % 10) \(units[idx])"
    }

    /// 时间列的精度默认是「到分」（Panel.h 里 _timestampLevel 的初值
    /// kTimestampPrintLevel_MIN），所以列表里显示 "yyyy-MM-dd HH:mm"。
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    static func date(_ d: Date?) -> String {
        guard let d else { return "" }
        return dateFormatter.string(from: d)
    }

    /// 相对时间，用于进度窗口的「已用/剩余」
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "" }
        let t = Int(seconds.rounded())
        if t < 3600 {
            return String(format: "%d:%02d", t / 60, t % 60)
        }
        return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }

    /// 与 7zz 一致的属性串：文件 "A -rw-r--r--"，目录 "D drwxr-xr-x"
    static func attributes(path: String, isDir: Bool) -> String {
        guard let st = statPath(path) else { return isDir ? "D" : "A" }
        let mode = st.st_mode
        var s = isDir ? "D " : "A "
        s += (mode & S_IRUSR) != 0 ? "r" : "-"
        s += (mode & S_IWUSR) != 0 ? "w" : "-"
        s += (mode & S_IXUSR) != 0 ? "x" : "-"
        s += (mode & S_IRGRP) != 0 ? "r" : "-"
        s += (mode & S_IWGRP) != 0 ? "w" : "-"
        s += (mode & S_IXGRP) != 0 ? "x" : "-"
        s += (mode & S_IROTH) != 0 ? "r" : "-"
        s += (mode & S_IWOTH) != 0 ? "w" : "-"
        s += (mode & S_IXOTH) != 0 ? "x" : "-"
        return s
    }

    struct Stat {
        var st_mode: mode_t
        var st_size: off_t
        var st_mtime: Date
        var st_ctime: Date
        var st_atime: Date
        var st_ino: UInt64
        var st_nlink: UInt64
        var st_uid: uid_t
        var st_gid: gid_t
    }

    static func statPath(_ path: String) -> Stat? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        func toDate(_ ts: timespec) -> Date {
            Date(timeIntervalSince1970: Double(ts.tv_sec) + Double(ts.tv_nsec) / 1e9)
        }
        return Stat(st_mode: st.st_mode,
                    st_size: st.st_size,
                    st_mtime: toDate(st.st_mtimespec),
                    st_ctime: toDate(st.st_ctimespec),
                    st_atime: toDate(st.st_atimespec),
                    st_ino: st.st_ino,
                    st_nlink: UInt64(st.st_nlink),
                    st_uid: st.st_uid,
                    st_gid: st.st_gid)
    }

    /// 系统用户名/组名
    static func userName(_ uid: uid_t) -> String {
        guard let pw = getpwuid(uid), let name = pw.pointee.pw_name else { return String(uid) }
        return String(cString: name)
    }

    static func groupName(_ gid: gid_t) -> String {
        guard let gr = getgrgid(gid), let name = gr.pointee.gr_name else { return String(gid) }
        return String(cString: name)
    }
}

// MARK: - 设置（对应 Windows 版的注册表项）

final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    private func key(_ k: String) -> String { "SevenZipMac." + k }

    /// 和 Windows 版一致：默认单面板（FM.cpp 里的 kNumDefaultPanels = 1），F9 切双面板
    var numPanels: Int {
        get { d.object(forKey: key("numPanels")) as? Int ?? 1 }
        set { d.set(newValue, forKey: key("numPanels")) }
    }

    var showArchiveToolbar: Bool {
        get { d.object(forKey: key("showArchiveToolbar")) as? Bool ?? true }
        set { d.set(newValue, forKey: key("showArchiveToolbar")) }
    }

    var showStandardToolbar: Bool {
        get { d.object(forKey: key("showStandardToolbar")) as? Bool ?? true }
        set { d.set(newValue, forKey: key("showStandardToolbar")) }
    }

    var largeButtons: Bool {
        get { d.object(forKey: key("largeButtons")) as? Bool ?? false }
        set { d.set(newValue, forKey: key("largeButtons")) }
    }

    var showButtonsText: Bool {
        get { d.object(forKey: key("showButtonsText")) as? Bool ?? true }
        set { d.set(newValue, forKey: key("showButtonsText")) }
    }

    var viewMode: Int {
        get { d.object(forKey: key("viewMode")) as? Int ?? 3 }   // 3 = Details
        set { d.set(newValue, forKey: key("viewMode")) }
    }

    /// 「Show ".." item」：列表里是否显示上一级那一行（对应注册表的 ShowDots）。
    /// Windows 版 RegistryUtils.cpp:136 的初值是 false，所以默认不显示。
    var showDots: Bool {
        get { d.object(forKey: key("showDots")) as? Bool ?? false }
        set { d.set(newValue, forKey: key("showDots")) }
    }

    /// 文件列表里是否显示隐藏项。默认关，和 Finder 一样 —— 打开主目录时
    /// 不会先看到 Library。判定沿用 Finder 的口径，见 FolderLoader.isHidden。
    var showHidden: Bool {
        get { d.object(forKey: key("showHidden")) as? Bool ?? false }
        set { d.set(newValue, forKey: key("showHidden")) }
    }

    var autoRefresh: Bool {
        get { d.object(forKey: key("autoRefresh")) as? Bool ?? true }
        set { d.set(newValue, forKey: key("autoRefresh")) }
    }

    /// 每个目录类型各自的列宽与可见性，对应 Windows 版把视图设置存进注册表
    func columns(for context: String) -> [String: [String: Any]] {
        d.dictionary(forKey: key("columns." + context)) as? [String: [String: Any]] ?? [:]
    }

    func setColumns(_ v: [String: [String: Any]], for context: String) {
        d.set(v, forKey: key("columns." + context))
    }

    var favorites: [[String: String]] {
        get { d.array(forKey: key("favorites")) as? [[String: String]] ?? [] }
        set { d.set(newValue, forKey: key("favorites")) }
    }

    var foldersHistory: [String] {
        get { d.array(forKey: key("foldersHistory")) as? [String] ?? [] }
        set { d.set(newValue, forKey: key("foldersHistory")) }
    }

    var lastExtractPath: String? {
        get { d.string(forKey: key("lastExtractPath")) }
        set { d.set(newValue, forKey: key("lastExtractPath")) }
    }

    // MARK: 启动位置

    /// 启动时落在哪里：上次打开过的目录，还是固定的主路径
    enum StartupPath: String {
        case last
        case home
    }

    var startupPath: StartupPath {
        get { StartupPath(rawValue: d.string(forKey: key("startupPath")) ?? "") ?? .last }
        set { d.set(newValue.rawValue, forKey: key("startupPath")) }
    }

    /// 主路径。空串表示用用户主目录。
    var homePath: String {
        get { d.string(forKey: key("homePath")) ?? "" }
        set { d.set(newValue, forKey: key("homePath")) }
    }

    /// 主路径的实际取值：没自定义过就是用户主目录
    var effectiveHomePath: String {
        let p = homePath
        return p.isEmpty ? NSHomeDirectory() : p
    }

    /// 启动时要打开的路径。命令行 --open 的优先级比它高，见 main.swift。
    var startupLocation: String {
        switch startupPath {
        case .home: return effectiveHomePath
        case .last: return foldersHistory.first ?? effectiveHomePath
        }
    }

}
