// 图标加载。
//
// 归档格式图标与工具栏按钮用的都是 7-Zip 官方源码里的原始素材
// （Archive/Icons/*.ico、UI/FileManager/*.bmp），由 tools/mkicons.py 转成 PNG。
// @2x 变体是把原始位图整数倍放大出来的，保持像素质感，不做插值模糊。

import AppKit

enum Icons {

    private static var cache: [String: NSImage] = [:]
    private static let lock = NSLock()

    /// 加载一对 1x/@2x PNG，装进同一个 NSImage
    private static func pair(_ name: String, group: String) -> NSImage? {
        let key = "\(group)/\(name)"
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()

        guard let u1 = Res.url(name, ext: "png", subdir: "icons/\(group)"),
              let d1 = try? Data(contentsOf: u1),
              let rep1 = NSBitmapImageRep(data: d1)
        else { return nil }

        let img = NSImage(size: NSSize(width: rep1.pixelsWide, height: rep1.pixelsHigh))
        rep1.size = img.size
        img.addRepresentation(rep1)

        if let u2 = Res.url(name + "@2x", ext: "png", subdir: "icons/\(group)"),
           let d2 = try? Data(contentsOf: u2),
           let rep2 = NSBitmapImageRep(data: d2) {
            rep2.size = img.size
            img.addRepresentation(rep2)
        }

        lock.lock(); cache[key] = img; lock.unlock()
        return img
    }

    // MARK: 归档格式图标

    static let genericArchive: NSImage? = pair("7z", group: "archive")

    static func archive(_ name: String?) -> NSImage? {
        guard let name, !name.isEmpty else { return genericArchive }
        return pair(name, group: "archive") ?? genericArchive
    }

    // MARK: 工具栏按钮

    static func toolbarButton(_ name: String, large: Bool) -> NSImage? {
        pair(large ? "\(name)_large" : "\(name)_small", group: "toolbar")
    }

    // MARK: 程序图标 / 关于对话框 logo

    static var appIcon: NSImage? { pair("fm_48", group: "app") }
    static var logo: NSImage? { pair("logo", group: "app") }

    // MARK: 文件系统图标（走系统，和 Windows 版取系统图标是同一个道理）

    private static var fileIconCache: [String: NSImage] = [:]

    static func systemIcon(forPath path: String, isDir: Bool, size: CGFloat = 16) -> NSImage {
        let key = "\(isDir ? "d" : "f")|\((path as NSString).pathExtension)"
        if let hit = fileIconCache[key] { return hit }

        let img: NSImage
        if isDir {
            img = NSWorkspace.shared.icon(forFileType: "public.folder")
        } else {
            let ext = (path as NSString).pathExtension
            img = NSWorkspace.shared.icon(forFileType: ext.isEmpty ? "public.data" : ext)
        }
        img.size = NSSize(width: size, height: size)
        if fileIconCache.count < 8000 { fileIconCache[key] = img }
        return img
    }

    /// 列表里某一行的图标：归档用 7-Zip 自己的格式图标（和 Windows 版一致），其余走系统
    static func icon(for entry: FileEntry, size: CGFloat = 16) -> NSImage? {
        if entry.isArchive, let a = archive(entry.archiveIcon) { return a }
        return systemIcon(forPath: entry.fullPath, isDir: entry.isDir, size: size)
    }
}

enum SysIcon {
    static func symbol(_ name: String, size: CGFloat = 14, weight: NSFont.Weight = .regular) -> NSImage? {
        let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
    }
}
