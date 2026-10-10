// 把「某类文件默认用本 App 打开」直接写进 LaunchServices 的用户偏好。
//
// 为什么不调 NSWorkspace.setDefaultApplication：macOS 26.4 起，凡是通过公开 API
// （NSWorkspace.setDefaultApplication，或者它底下的 LSSetDefaultRoleHandlerForContentType）
// 改默认打开方式，系统都会为每一个 UTI 弹一次确认框，用户得逐个点「使用」。首启
// 对话框默认勾了 24 个扩展名，去重后是 13 个 UTI —— 也就是 13 个弹窗，而且实测
// completion 会一直挂到用户点完为止。
//
// 那两个 API 底下就是往 com.apple.launchservices.secure.plist 的 LSHandlers 里写一条
//   { LSHandlerContentType = <UTI>, LSHandlerRoleAll = <bundle id> }
// 这里直接写同一份数据：用户已经在本 App 的对话框里点过「确定」，那 13 次系统确认
// 只是把同一件事重复问 13 遍。
//
// 生效链（实测自 macOS 27.0 / Build 26A428）：
//   只写文件                  -> 不生效
//   写文件 + 重启 cfprefsd     -> 不生效
//   写文件 + 重启 lsd          -> 立即生效，且不会被写回旧值
// lsd 是当前用户的进程，不需要额外权限。

import Foundation

enum DefaultHandlerWriter {

    struct Result {
        var written = 0
        var error: String?
    }

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist")
    }

    private static var backupURL: URL {
        plistURL.deletingLastPathComponent()
            .appendingPathComponent("com.apple.launchservices.secure.plist.7zip-backup")
    }

    /// 把 contentTypes 里每个类型的默认打开程序设成 bundleID。
    /// 表里已有该类型就就地改，没有就追加一条，其余条目原样保留。
    static func set(contentTypes: [String], to bundleID: String) -> Result {
        var result = Result()
        do {
            var root = try readRoot()
            var handlers = root["LSHandlers"] as? [[String: Any]] ?? []
            var written = 0

            for ct in contentTypes {
                if let i = handlers.firstIndex(where: { $0["LSHandlerContentType"] as? String == ct }) {
                    guard handlers[i]["LSHandlerRoleAll"] as? String != bundleID else { continue }
                    handlers[i]["LSHandlerRoleAll"] = bundleID
                    handlers[i].removeValue(forKey: "LSHandlerRoleViewer")
                    written += 1
                } else {
                    handlers.append(["LSHandlerContentType": ct, "LSHandlerRoleAll": bundleID])
                    written += 1
                }
            }

            guard written > 0 else { return result }
            root["LSHandlers"] = handlers

            // 落盘后让 lsd 重新读一遍 —— 少了这一步，文件改了也不生效。
            // 实测：只写文件 3 秒后仍是旧值；写文件 + 重启 cfprefsd 也不生效；
            // 写文件 + 重启 lsd 立即生效，且此后保持。所以这里只动 lsd。
            try write(root)
            signal("lsd")

            result.written = written
        } catch {
            result.error = error.localizedDescription
        }
        return result
    }

    private static func readRoot() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: plistURL), !data.isEmpty else { return [:] }
        let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return obj as? [String: Any] ?? [:]
    }

    private static func write(_ root: [String: Any]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: root,
                                                      format: .binary, options: 0)
        // 留一份原件。这个文件是系统级的，写坏会影响本机所有 App 的打开方式；
        // 只在还没有备份时留，不覆盖更早那份。
        if !FileManager.default.fileExists(atPath: backupURL.path),
           let current = try? Data(contentsOf: plistURL) {
            try? current.write(to: backupURL)
        }
        try data.write(to: plistURL, options: .atomic)
    }

    private static func signal(_ name: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = [name]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }
}
