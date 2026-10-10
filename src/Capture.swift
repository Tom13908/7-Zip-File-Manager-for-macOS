// 界面自检用的离屏截图。
//
// 走的是 AppKit 自己的绘制通路（view.cacheDisplay），不需要屏幕录制权限，
// 也不用把窗口摆到前台。正常启动完全不受影响。
//
// 模态对话框会在自己的 run loop 里跑，主队列上的延迟块不保证按时被排到，
// 所以这里用一个挂在多个 run loop mode 上的重复定时器反复抓，
// 以「抓到窗口数量最多」的那一次为准。

import AppKit

enum Capture {

    private static var timer: Timer?
    private static var best = 0
    private static var deadline = Date()

    /// 开始抓。没带 --capture 时什么都不做。
    static func schedule() {
        guard let path = LaunchArgs.capturePath else { return }
        deadline = Date().addingTimeInterval(LaunchArgs.captureDelay)
        let t = Timer(timeInterval: 0.4, repeats: true) { _ in tick(path) }
        for mode in [RunLoop.Mode.default, .modalPanel, .eventTracking] {
            RunLoop.main.add(t, forMode: mode)
        }
        timer = t
    }

    /// 立刻抓一次（自动化自检用，--automation 的 shot 命令）
    static func writeNow(_ path: String) {
        let windows = NSApp.windows
            .filter { $0.isVisible && $0.contentView != nil }
            .sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }
        for (idx, w) in windows.enumerated() {
            let name = windows.count == 1 ? path : suffixed(path, idx, w.title)
            write(window: w, to: name)
        }
    }

    private static func tick(_ path: String) {
        let windows = NSApp.windows
            .filter { $0.isVisible && $0.contentView != nil }
            .sorted { $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height }

        if !windows.isEmpty && windows.count >= best {
            best = windows.count
            for (idx, w) in windows.enumerated() {
                let name = windows.count == 1 ? path : suffixed(path, idx, w.title)
                write(window: w, to: name)
            }
        }

        if LaunchArgs.dumpLayout {
            for w in windows { dumpTree(w.contentView!, indent: 0) }
        }

        if LaunchArgs.dumpMenu, let main = NSApp.mainMenu { dumpMenuTree(main) }

        guard Date() >= deadline else { return }
        timer?.invalidate()
        exit(0)
    }

    /// 菜单栏 + 加速键（--dump-menu）。键里的 U+F7xx 是 AppKit 的功能键码，
    /// F1 = F704 起依次递增，Shift 单独算修饰键。
    private static func dumpMenuTree(_ menu: NSMenu, indent: Int = 0) {
        let pad = String(repeating: "  ", count: indent)
        for it in menu.items {
            var mods: [String] = []
            let m = it.keyEquivalentModifierMask
            if m.contains(.control) { mods.append("Control") }
            if m.contains(.option) { mods.append("Option") }
            if m.contains(.shift) { mods.append("Shift") }
            if m.contains(.command) { mods.append("Command") }
            var name = it.keyEquivalent
            if let scalar = name.unicodeScalars.first, name.count == 1 {
                switch scalar.value {
                case 0xF704...0xF726: name = "F\(scalar.value - 0xF704 + 1)"
                case 0xF727: name = "Insert"
                case 0xF728: name = "ForwardDelete"
                case 0xF729: name = "Home"
                case 0xF72B: name = "End"
                case 0xF72C: name = "PageUp"
                case 0xF72D: name = "PageDown"
                default:
                    // 控制字符（回车、退格…）直接打出来看不见，改成十六进制
                    if scalar.value < 0x20 || scalar.value == 0x7F {
                        name = String(format: "U+%04X", scalar.value)
                    }
                }
            }
            let line = "\(pad)\(it.title.isEmpty ? "(separator)" : it.title)"
                + "  key=\(name.isEmpty ? "-" : name)"
                + "  mods=\(mods.isEmpty ? "-" : mods.joined(separator: "+"))"
                + "  enabled=\(it.isEnabled)\n"
            FileHandle.standardError.write(line.data(using: .utf8)!)
            if let sub = it.submenu { dumpMenuTree(sub, indent: indent + 1) }
        }
    }

    /// 视图树 + 各自的实际尺寸（--dump-layout）
    private static func dumpTree(_ view: NSView, indent: Int) {
        let pad = String(repeating: "  ", count: indent)
        let f = view.frame
        let line = String(format: "%@%@  x=%.1f y=%.1f w=%.1f h=%.1f\n",
                          pad, String(describing: type(of: view)), f.origin.x, f.origin.y,
                          f.width, f.height)
        FileHandle.standardError.write(line.data(using: .utf8)!)
        for sub in view.subviews { dumpTree(sub, indent: indent + 1) }
    }

    private static func suffixed(_ path: String, _ idx: Int, _ title: String) -> String {        let ns = path as NSString
        let tag = title.isEmpty ? "window" : title.replacingOccurrences(of: "/", with: "_")
        return ns.deletingPathExtension + "-\(idx)-\(tag)." + ns.pathExtension
    }

    private static func write(window: NSWindow, to path: String) {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        FileHandle.standardError.write(
            "captured \(path) \(rep.pixelsWide)x\(rep.pixelsHigh)\n".data(using: .utf8)!)
    }
}
