// 程序入口与应用生命周期。

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var mainWindow: MainWindowController?
    private let services = ServicesProvider()

    /// 主窗口是「启动宽限期过完、没等到服务消息」才弹的。
    /// 记下弹出来的时刻：服务要是比宽限期还慢，这个窗口就不该存在，得收掉。
    private var mainWindowShownAt: Date?
    private var startupTimer: Timer?
    private static let startupGrace: TimeInterval = 0.35
    /// 超过这么久才到的服务，说明用户早就在正常用这个 App 了，窗口不该收
    private static let strayWindowGrace: TimeInterval = 5

    /// 服务请求在启动收尾（finishLaunching）期间就会被派发，
    /// 判定时机就在这里插进去。
    func applicationWillFinishLaunching(_ notification: Notification) {
        // 必须在启动收尾之前注册。晚一步（比如放到 applicationDidFinishLaunching 里），
        // 这次服务请求就已经派发完了，会被整个丢掉 —— 现象是 App 起来了、
        // 主窗口弹出来，然后什么都不发生，连个错误都没有。
        NSApp.servicesProvider = services
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ArchiveTypes.load()
        Engine.probeVersion()

        LaunchContext.onServingFinder = { [weak self] in
            guard let self, let shown = self.mainWindowShownAt else { return }
            guard Date().timeIntervalSince(shown) < Self.strayWindowGrace else { return }
            self.cancelStartupTimer()
            // 只 orderOut、不 close：close 会让它算作「最后一个窗口已关闭」，
            // 而服务那边此刻还没建出进度窗口，App 会当场退出。
            self.mainWindow?.window?.orderOut(nil)
            self.mainWindowShownAt = nil
        }

        let timer = Timer.scheduledTimer(withTimeInterval: Self.startupGrace, repeats: false) {
            [weak self] _ in
            self?.startupTimer = nil
            guard !LaunchContext.servingFinder else { return }
            let wc = self?.showMainWindow()
            self?.mainWindowShownAt = Date()
            Capture.schedule()
            if LaunchArgs.automation { Automation.start() }
            if let name = LaunchArgs.dialog {
                DispatchQueue.main.async { wc?.openInspectionDialog(name) }
            }
        }
        startupTimer = timer

        // 首次启动问一次「要不要把 7-Zip 设为归档的默认打开方式」。
        // 自检（--automation）、离屏截图（--capture）、指定对话框（--dialog）、
        // 以及 Finder 服务那条路径都不问 —— 它们要的是确定的行为，弹窗会卡住流程。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard LaunchArgs.capturePath == nil, !LaunchArgs.automation,
                  LaunchArgs.dialog == nil, !LaunchContext.servingFinder else { return }
            DefaultAppOffer.presentIfNeeded()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// 服务调用会把多弹出来的主窗口藏起来（见 LaunchContext.onServingFinder），
    /// 之后点 Dock 图标要能把窗口叫回来。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    /// 从 Finder 双击归档、拖到 Dock 图标上
    func application(_ application: NSApplication, open urls: [URL]) {
        // --open / --capture / --automation 已经明确说了起点，这时系统再送
        // 「打开某目录」的事件（状态恢复、LaunchServices 的残留请求）会把窗口带跑偏。
        if LaunchArgs.initialPath != nil {
            if LaunchArgs.automation {
                FileHandle.standardError.write("ignored open event: \(urls.map(\.path))\n"
                    .data(using: .utf8)!)
            }
            return
        }
        cancelStartupTimer()
        guard let first = urls.first else { return }
        if mainWindow == nil {
            showMainWindow(initial: Location(root: first.path))
        } else {
            mainWindow?.openPath(first.path)
        }
        Capture.schedule()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: 主窗口

    private func cancelStartupTimer() {
        startupTimer?.invalidate()
        startupTimer = nil
    }

    @discardableResult
    private func showMainWindow(initial: Location? = nil) -> MainWindowController? {
        guard mainWindow == nil else {
            NSApp.activate(ignoringOtherApps: true)
            mainWindow?.window?.makeKeyAndOrderFront(nil)
            return mainWindow
        }
        // --open 优先；否则按选项里选的那种启动位置（上次打开的目录 / 主路径）
        let start = LaunchArgs.initialPath ?? Settings.shared.startupLocation
        let loc = initial
            ?? Resolver.parseLoose(start)
            ?? Location(root: Settings.shared.effectiveHomePath)
        let wc = MainWindowController(initialLocation: loc)
        mainWindow = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        return wc
    }
}

// MARK: 入口

// 早期版本在「选项」里有一个界面语言开关，选择写在 App 自己的 AppleLanguages 里。
// 那个开关已经删掉（它改不了 Finder 右键菜单的语言，留着只会让两边不一致）。
// 这里做一次性清理 —— 不清的话界面会一直停在当时选的语言上，看着像「跟随系统」失灵。
if UserDefaults.standard.object(forKey: "SevenZipMac.appLanguage") != nil {
    UserDefaults.standard.removeObject(forKey: "AppleLanguages")
    UserDefaults.standard.removeObject(forKey: "SevenZipMac.appLanguage")
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
