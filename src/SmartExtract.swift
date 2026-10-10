// 智能解压：先看压缩包的顶层结构，再决定解到哪。
//
// 规则取自 Bandizip 的「智能解压至此」（https://cn.bandisoft.com/bandizip/help/auto_dest）：
//
//   包里只有一个文件             -> 解压到压缩包所在目录
//   所有条目都在同一个顶层目录里 -> 解压到压缩包所在目录（那个目录整体出现）
//   其余                         -> 在压缩包所在目录下新建同名文件夹，全部装进去
//
// 第三条是它和「解压到当前文件夹」唯一的分歧点：包里有多个顶层项时，
// 「解压到当前文件夹」会把它们摊得到处都是，智能解压则先包一层。
//
// 这里只用 `7zz l -slt` 的目录结构，不做任何解压，所以判定是纯读操作。

import Foundation

enum SmartExtract {

    /// 压缩包的顶层直接子项。
    ///
    /// 走 `FolderLoader.children(of:inner:)`：目录条目缺失的包（很多 Unix 下打的包
    /// 只有文件路径）它也能按路径补出顶层目录，所以 `a/b/c.txt` 这种会算出一个 `a`。
    static func topLevel(_ listing: ArchiveListing) -> [FileEntry] {
        FolderLoader.children(of: listing, inner: "")
    }

    /// 落点目录。
    ///
    /// 读不出目录结构时（加密包没给密码、根本不是归档）也走「新建同名文件夹」那条 ——
    /// 多一层包装比把文件散进用户的目录里好收拾。
    static func destination(archive: String, password: String?) -> String {
        let parent = (archive as NSString).deletingLastPathComponent
        let stem = ((archive as NSString).lastPathComponent as NSString).deletingPathExtension
        guard let listing = try? FolderLoader.loadArchive(archive, password: password) else {
            return uniqueFolder(parent: parent, name: stem)
        }
        let top = topLevel(listing)
        // 一个顶层项：单文件、单文件夹，这两种都直接摊在压缩包所在目录。
        // 一个都没有：空包或只有目录记录，交给引擎去报错。
        if top.count <= 1 { return parent }
        return uniqueFolder(parent: parent, name: stem)
    }

    /// 「名字」已被占用时顺延成「名字 (2)」「名字 (3)」……
    static func uniqueFolder(parent: String, name: String) -> String {
        let fm = FileManager.default
        var candidate = (parent as NSString).appendingPathComponent(name)
        var n = 2
        while fm.fileExists(atPath: candidate), n < 1000 {
            candidate = (parent as NSString).appendingPathComponent("\(name) (\(n))")
            n += 1
        }
        return candidate
    }

    /// 在这个落点下已经存在的顶层名字。解压前拿它去问用户。
    ///
    /// 只看顶层：真正让人察觉不到的就是顶层被覆盖或者跟旧文件混在一起。
    /// 包里更深层的路径要不要覆盖，交给覆盖模式统一处理。
    static func existingTopLevel(archive: String, destination: String, password: String?) -> [String] {
        guard let listing = try? FolderLoader.loadArchive(archive, password: password) else { return [] }
        let fm = FileManager.default
        var hits: [String] = []
        for e in topLevel(listing) {
            let name = (e.fullPath as NSString).lastPathComponent
            guard !name.isEmpty, !hits.contains(name) else { continue }
            if fm.fileExists(atPath: (destination as NSString).appendingPathComponent(name)) {
                hits.append(name)
            }
        }
        return hits
    }
}
