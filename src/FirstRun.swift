// 首次启动时问一次：要不要把 7-Zip 设为归档的默认打开方式。
//
// 为什么要问：macOS 自带「归档实用工具」（Archive Utility），系统认得的归档类型默认
// 都归它 —— 双击 .7z 是它来解。想让双击直接进 7-Zip，用户得自己去
// 「显示简介 → 打开方式 → 全部更改」。这里把这件事一次问清楚，并按格式分组让用户勾。
//
// 勾选项按扩展名分组，真正落到 UTI 时才用 UTType(filenameExtension:) 现算：
// 系统给每个扩展名解析到哪个 UTI（.7z → org.7-zip.7-zip-archive、.zip →
// public.zip-archive …）才是设置默认程序要填的值，写死了会随系统版本漂移。
//
// 磁盘映像（iso、img）默认不勾：这类文件在 macOS 上双击是挂载，改了默认程序就挂载
// 不了了。dmg 干脆不在列表里 —— 它必须留给系统的挂载行为。

import AppKit
import UniformTypeIdentifiers

enum DefaultAppOffer {

    private static let offeredKey = "SevenZipMac.didOfferDefaultApp"

    private struct Group {
        let extensions: [String]
        let on: Bool
    }

    /// 勾选框上的文字就是扩展名本身，各语言通用，不进译文表。
    ///
    /// 只列能确实设成默认的格式。两类不列：
    ///   .ipa —— 归系统的「iOS App Installer」，认下它的 UTI 会把默认程序抢过来
    ///   .deb —— 系统里没有任何 App 声明过，落的是动态类型，设了也不会生效
    /// 留着勾选框却什么都不做，比不提供这个选项更糟。
    private static let groups: [Group] = [
        Group(extensions: ["7z"], on: true),
        Group(extensions: ["zip", "jar", "apk", "xpi"], on: true),
        Group(extensions: ["tar", "gz", "tgz", "bz2", "tbz2", "xz", "zst", "lzma"], on: true),
        Group(extensions: ["rar", "cab", "arj", "lzh", "chm", "cpio", "rpm", "wim"], on: true),
        Group(extensions: ["iso", "img"], on: false),
    ]

    /// 每次弹窗新建的勾选框，runModal 之后按顺序读回来。
    private static var boxes: [NSButton] = []

    /// 只在「用户自己打开 App」时调用。自检、截图、Finder 服务那几条启动路径都不问
    /// —— 它们要的是确定的行为，弹窗会把流程卡住。
    static func presentIfNeeded() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: offeredKey) else { return }
        // 先落标记：无论用户点确定还是取消，都不再问第二次。
        d.set(true, forKey: offeredKey)

        let alert = NSAlert()
        alert.messageText = S.defaultAppOfferTitle
        alert.informativeText = S.defaultAppOfferBody
        alert.addButton(withTitle: S.ok)
        alert.addButton(withTitle: S.cancel)
        alert.accessoryView = makeAccessory()

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        apply()
    }

    private static func makeAccessory() -> NSView {
        let rowHeight: CGFloat = 22
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 360,
                                       height: rowHeight * CGFloat(groups.count)))
        boxes = []
        for (i, g) in groups.enumerated() {
            let b = NSButton(checkboxWithTitle: g.extensions.joined(separator: ", "),
                             target: nil, action: nil)
            b.state = g.on ? .on : .off
            b.font = NSFont.systemFont(ofSize: 12)
            b.sizeToFit()
            // AppKit 的 y 轴朝上，第一组排在最上面
            let y = box.frame.height - rowHeight * CGFloat(i + 1)
            b.setFrameOrigin(NSPoint(x: 0, y: y + 3))
            box.addSubview(b)
            boxes.append(b)
        }
        return box
    }

    private static func apply() {
        var types: [UTType] = []
        var seen = Set<String>()
        for (i, g) in groups.enumerated() where i < boxes.count && boxes[i].state == .on {
            for e in g.extensions {
                // 解析不出类型、或系统只给了个动态类型（没人声明过这个扩展名）的，
                // 设不了默认程序，跳过。
                guard let t = UTType(filenameExtension: e), !t.isDynamic else { continue }
                if seen.insert(t.identifier).inserted { types.append(t) }
            }
        }
        guard !types.isEmpty else { return }

        let app = Bundle.main.bundleURL
        let ws = NSWorkspace.shared
        let group = DispatchGroup()
        let lock = NSLock()
        var failed: [String] = []

        for t in types {
            group.enter()
            ws.setDefaultApplication(at: app, toOpen: t) { error in
                if let error {
                    NSLog("7zip: 设置 \(t.identifier) 的默认打开程序失败：\(error)")
                    lock.lock()
                    failed.append("\(t.identifier): \(error.localizedDescription)")
                    lock.unlock()
                }
                group.leave()
            }
        }

        // 失败要说话：静默失败会让用户以为已经设好了。
        group.notify(queue: .main) {
            guard !failed.isEmpty else { return }
            DialogKit.alert("7-Zip",
                            failed.sorted().joined(separator: "\n"),
                            style: .warning, parent: nil)
        }
    }
}
