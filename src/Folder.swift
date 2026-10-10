// 目录/归档的读取与排序。

import Foundation

struct ArchiveListing {
    var info: [(String, String)] = []      // 归档自身的属性，保留引擎给的顺序
    var entries: [FileEntry] = []
    var typeName: String = ""

    func value(_ key: String) -> String? {
        info.first { $0.0 == key }?.1
    }
}

enum FolderLoader {

    // MARK: 文件系统目录

    /// 读一个文件系统目录。
    ///
    /// - Parameter showHidden: false 时跳过隐藏项。判定按 Finder 的口径走
    ///   （`.isHidden`：名字以「.」开头，或带 hidden 标志），只按名字前缀过滤是漏的 ——
    ///   `~/Library` 就没有点号前缀，靠的是 hidden 标志。
    static func loadFileSystem(_ path: String, showHidden: Bool) -> [FileEntry] {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: path, isDirectory: true)
        guard let urls = try? fm.contentsOfDirectory(at: dir,
                                                     includingPropertiesForKeys: [.isHiddenKey],
                                                     options: []) else { return [] }
        var out: [FileEntry] = []
        out.reserveCapacity(urls.count)
        for url in urls {
            if !showHidden, isHidden(url) { continue }
            let name = url.lastPathComponent
            // 路径按传进来的那个字符串拼，不用 url.path ——
            // contentsOfDirectory(at:) 返回的子项会把软链接解析掉，
            // `/tmp/x` 会变成 `/private/tmp/x`，地址栏跟着变，和 Windows 版那种
            // 「显示的就是你输入的那条路径」不一致。
            let full = path == "/" ? "/" + name : path + "/" + name
            guard let st = Fmt.statPath(full) else { continue }
            let isDir = (st.st_mode & S_IFMT) == S_IFDIR
            let ext = (name as NSString).pathExtension
            var e = FileEntry(name: name, fullPath: full, isDir: isDir, isArchive: false, archiveIcon: nil)
            e.size = isDir ? 0 : Int64(st.st_size)
            e.packedSize = -1
            e.mtime = st.st_mtime
            e.ctime = st.st_ctime
            e.atime = st.st_atime
            e.attributes = Fmt.attributes(path: full, isDir: isDir)
            e.method = isDir ? "" : ""
            if !isDir, ArchiveTypes.isArchiveExtension(ext) {
                e.isArchive = true
                e.archiveIcon = ArchiveTypes.iconName(forExtension: ext)
            }
            out.append(e)
        }
        return out
    }

    /// 这个条目在 Finder 眼里算不算隐藏。
    /// `isHiddenKey` 一次把两种情形都覆盖了（点号前缀、hidden 标志），
    /// 取不到资源值时退回到点号前缀判断。
    static func isHidden(_ url: URL) -> Bool {
        if let v = try? url.resourceValues(forKeys: [.isHiddenKey]), let h = v.isHidden { return h }
        return url.lastPathComponent.hasPrefix(".")
    }

    // MARK: 归档

    /// 列出整个归档（引擎一次吐出全部条目，之后在内存里上下钻）
    static func loadArchive(_ archivePath: String, password: String?) throws -> ArchiveListing {
        var args = ["l", "-slt"]
        if let pw = password, !pw.isEmpty { args.append("-p" + pw) }
        args.append(archivePath)

        let r = try Engine.runSync(args)

        let text = r.stdout
        if text.contains("Cannot open encrypted archive") || text.contains("Wrong password") {
            throw EngineError.passwordRequired
        }
        if r.exitCode >= 2 && !text.contains("Path = ") {
            throw EngineError.notAnArchive(archivePath)
        }
        var listing = parseListing(text)
        listing.typeName = listing.value("Type") ?? ""
        if listing.entries.isEmpty && listing.info.isEmpty {
            throw EngineError.notAnArchive(archivePath)
        }
        return listing
    }

    /// 解析 `7zz l -slt` 的输出
    static func parseListing(_ text: String) -> ArchiveListing {
        var listing = ArchiveListing()
        var current: [String: String] = [:]
        var inEntries = false
        var order: [String] = []

        func flushEntry() {
            guard !current.isEmpty else { return }
            if let e = makeEntry(current, order: order, previous: listing.entries.last) {
                listing.entries.append(e)
            }
            current = [:]
            order = []
        }

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushEntry()
                continue
            }
            if trimmed.allSatisfy({ $0 == "-" }) && trimmed.count >= 4 {
                flushEntry()
                inEntries = true
                continue
            }
            guard let sep = line.range(of: " = ") else { continue }
            let key = String(line[line.startIndex..<sep.lowerBound])
            let value = String(line[sep.upperBound...])
            if inEntries {
                if current[key] == nil { order.append(key) }
                current[key] = value
            } else {
                listing.info.append((key, value))
            }
        }
        flushEntry()
        return listing
    }

    private static func makeEntry(_ kv: [String: String], order: [String],
                                  previous: FileEntry?) -> FileEntry? {
        guard let path = kv["Path"], !path.isEmpty else { return nil }
        // "Path = ." 之类不是真条目
        _ = order

        let isDir = kv["Folder"] == "+" || (kv["Attributes"]?.hasPrefix("D ") ?? false)
        let name = (path as NSString).lastPathComponent
        var e = FileEntry(name: name, fullPath: path, isDir: isDir, isArchive: false, archiveIcon: nil)

        if let s = kv["Size"], let v = Int64(s) { e.size = v }
        if let s = kv["Packed Size"], let v = Int64(s) { e.packedSize = v }
        e.mtime = parseDate(kv["Modified"])
        e.ctime = parseDate(kv["Created"])
        e.atime = parseDate(kv["Accessed"])
        e.attributes = kv["Attributes"] ?? ""
        e.crc = kv["CRC"] ?? ""
        e.method = kv["Method"] ?? ""
        e.encrypted = kv["Encrypted"] ?? ""
        e.comment = kv["Comment"] ?? ""
        e.block = kv["Block"] ?? ""
        e.hostOS = kv["Host OS"] ?? ""
        e.version = kv["Version"] ?? ""
        e.offset = kv["Offset"] ?? ""

        // 同属一个 solid 块（Block 值与上一条相同）的条目，Windows 版在 Solid 列显示 "+"
        if !isDir, !e.block.isEmpty, let prev = previous,
           !prev.isDir, prev.block == e.block {
            e.solid = "+"
        }

        if !isDir {
            let ext = (name as NSString).pathExtension
            if ArchiveTypes.isArchiveExtension(ext) {
                e.isArchive = true
                e.archiveIcon = ArchiveTypes.iconName(forExtension: ext)
            }
        }
        return e
    }

    /// "2026-09-30 14:33:46.2759918" —— 小数位最多 7 位，DateFormatter 吃不下，手动截断
    static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let parts = s.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        var time = String(parts[1])
        if let dot = time.firstIndex(of: ".") {
            let frac = time[time.index(after: dot)...]
            time = String(time[time.startIndex..<dot]) + "." + String(frac.prefix(6))
        }
        let norm = "\(parts[0]) \(time)"
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
        if let d = f.date(from: norm) { return d }
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: "\(parts[0]) \(time)")
    }

    /// 取出归档里某个内部目录的直接子项；目录条目缺失时按文件路径补出来
    static func children(of listing: ArchiveListing, inner: String) -> [FileEntry] {
        let prefix = inner.isEmpty ? "" : inner + "/"
        var direct: [FileEntry] = []
        var synthesized: Set<String> = []
        var order: [String] = []

        for e in listing.entries {
            guard e.fullPath.hasPrefix(prefix) else { continue }
            let rest = String(e.fullPath.dropFirst(prefix.count))
            guard !rest.isEmpty else { continue }
            if let slash = rest.firstIndex(of: "/") {
                // 落在子目录里——记下这个子目录名
                let sub = String(rest[rest.startIndex..<slash])
                if !synthesized.contains(sub) {
                    synthesized.insert(sub)
                    order.append(sub)
                }
            } else {
                direct.append(e)
            }
        }

        let known = Set(direct.map { $0.name })
        for sub in order where !known.contains(sub) {
            let full = prefix + sub
            var e = FileEntry(name: sub, fullPath: full, isDir: true, isArchive: false, archiveIcon: nil)
            e.size = 0
            e.packedSize = -1
            // 该目录下所有文件的最新时间，近似目录时间
            var newest: Date?
            var total: Int64 = 0
            for x in listing.entries where x.fullPath.hasPrefix(full + "/") {
                if let d = x.mtime, newest == nil || d > newest! { newest = d }
                total += x.size
            }
            e.mtime = newest
            e.size = total
            e.attributes = "D"
            direct.append(e)
        }
        return direct
    }
}

// MARK: - 排序

enum SortKey: Int {
    case name = 0, type, date, size, unsorted
}

enum Sorter {

    /// 与 7-Zip 的 CompareFileNames 同构的自然序：数字段按数值比，字母不区分大小写
    static func naturalCompare(_ a: String, _ b: String) -> ComparisonResult {
        let x = Array(a.unicodeScalars), y = Array(b.unicodeScalars)
        var i = 0, j = 0
        while i < x.count && j < y.count {
            let ca = x[i], cb = y[j]
            if isDigit(ca) && isDigit(cb) {
                var vi = 0, vj = 0
                while i < x.count, isDigit(x[i]) { vi = vi * 10 + Int(x[i].value - 48); i += 1 }
                while j < y.count, isDigit(y[j]) { vj = vj * 10 + Int(y[j].value - 48); j += 1 }
                if vi != vj { return vi < vj ? .orderedAscending : .orderedDescending }
                continue
            }
            let la = lower(ca), lb = lower(cb)
            if la != lb { return la < lb ? .orderedAscending : .orderedDescending }
            i += 1
            j += 1
        }
        if i < x.count { return .orderedDescending }
        if j < y.count { return .orderedAscending }
        // 完全同名（大小写不同）时用原始大小写做最后区分
        if a != b { return a < b ? .orderedAscending : .orderedDescending }
        return .orderedSame
    }

    private static func isDigit(_ s: Unicode.Scalar) -> Bool { s.value >= 48 && s.value <= 57 }
    private static func lower(_ s: Unicode.Scalar) -> UInt32 {
        s.value >= 65 && s.value <= 90 ? s.value + 32 : s.value
    }

    /// 首次点某列时的排序方向：大小/日期类默认降序（PanelSort.cpp:230-242）
    static func defaultAscending(for key: String) -> Bool {
        switch key {
        case Columns.size, Columns.packedSize, Columns.mtime, Columns.ctime, Columns.atime:
            return false
        default:
            return true
        }
    }

    static func sort(_ items: [FileEntry], by key: String, ascending: Bool, mode: SortKey) -> [FileEntry] {
        if mode == .unsorted && key.isEmpty { return items }

        func less(_ a: FileEntry, _ b: FileEntry) -> Bool {
            // 目录永远排在前面（和 Windows 版一致）
            if a.isDir != b.isDir { return a.isDir }

            var r: ComparisonResult
            switch key {
            case Columns.name:
                r = naturalCompare(a.name, b.name)
            case Columns.size:
                r = a.size == b.size ? .orderedSame : (a.size < b.size ? .orderedAscending : .orderedDescending)
            case Columns.packedSize:
                let x = max(a.packedSize, 0), y = max(b.packedSize, 0)
                r = x == y ? .orderedSame : (x < y ? .orderedAscending : .orderedDescending)
            case Columns.mtime:
                r = compareDate(a.mtime, b.mtime)
            case Columns.ctime:
                r = compareDate(a.ctime, b.ctime)
            case Columns.atime:
                r = compareDate(a.atime, b.atime)
            case Columns.crc:
                r = naturalCompare(a.crc, b.crc)
            case Columns.method:
                r = naturalCompare(a.method, b.method)
            case Columns.attributes:
                r = naturalCompare(a.attributes, b.attributes)
            default:
                r = naturalCompare(a.name, b.name)
            }
            if r == .orderedSame {
                r = naturalCompare(a.name, b.name)
            }
            return ascending ? (r == .orderedAscending) : (r == .orderedDescending)
        }

        return items.sorted(by: less)
    }

    private static func compareDate(_ a: Date?, _ b: Date?) -> ComparisonResult {
        switch (a, b) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedAscending
        case (_, nil): return .orderedDescending
        case let (x?, y?):
            if x == y { return .orderedSame }
            return x < y ? .orderedAscending : .orderedDescending
        }
    }
}
