// 主窗口：顶部工具条 + 一个或两个并排的文件面板。
// 布局和 Windows 版 7-Zip File Manager 一致：工具条在上，面板里是地址栏 + 列表 + 状态栏。

import AppKit

// MARK: - 工具条按钮（平面、悬停高亮，像 Windows 工具条）

final class ToolbarButton: NSButton {
    var hovered = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageAbove
        alignment = .center
        font = NSFont.systemFont(ofSize: 11)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func draw(_ dirtyRect: NSRect) {
        let pressed = isHighlighted
        if pressed || hovered {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
            (pressed ? NSColor.selectedControlColor.withAlphaComponent(0.45)
                     : NSColor.controlHighlightColor.withAlphaComponent(0.55)).setFill()
            path.fill()
        }
        super.draw(dirtyRect)
    }
}

// MARK: - 工具条

final class ToolbarStripView: NSView {

    struct Item {
        let icon: String
        let title: String
        let action: MainWindowController.Action
    }

    private let archiveItems: [Item] = [
        Item(icon: "add", title: S.btnAdd, action: .add),
        Item(icon: "extract", title: S.btnExtract, action: .extract),
        Item(icon: "extractsmart", title: S.extractSmart, action: .smartExtract),
        Item(icon: "test", title: S.btnTest, action: .test),
    ]

    private let standardItems: [Item] = [
        Item(icon: "copy", title: S.btnCopy, action: .copyTo),
        Item(icon: "move", title: S.btnMove, action: .moveTo),
        Item(icon: "delete", title: S.btnDelete, action: .delete),
        Item(icon: "info", title: S.btnInfo, action: .properties),
    ]

    private var buttons: [ToolbarButton] = []
    weak var target: MainWindowController?

    /// 工具条里最高那个按钮需要的总高度（含上下留白）。
    ///
    /// 要读这个，不要去读 frame：frame 的高度由 `buildUI` 那条 height 约束决定，
    /// 而 `rebuild()` 里直接给 frame 赋的新高度在下次布局就会被约束盖回去 ——
    /// 于是启动时按硬编码的 50 定死，大图标（按钮 74pt 高 + 留白 = 82pt）整个顶出
    /// contentView，画进标题栏里，上半部分正好被红绿灯和窗口标题（标题显示的是当前路径）
    /// 压住。切一下图标大小能好，是因为那条路径会重新取高度；重启又坏，因为启动时没人取。
    private(set) var preferredHeight: CGFloat = 50

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError() }

    func rebuild() {
        for b in buttons { b.removeFromSuperview() }
        buttons.removeAll()

        let s = Settings.shared
        var items: [Item] = []
        if s.showArchiveToolbar { items += archiveItems }
        if s.showStandardToolbar { items += standardItems }

        let large = s.largeButtons
        let iconSize: CGFloat = large ? 48 : 24
        var x: CGFloat = 6
        var maxH: CGFloat = 0

        for it in items {
            let btn = ToolbarButton()
            btn.image = Icons.toolbarButton(it.icon, large: large)
            btn.title = s.showButtonsText ? it.title : ""
            btn.imageScaling = .scaleProportionallyUpOrDown
            btn.tag = it.action.rawValue
            btn.target = self
            btn.action = #selector(clicked(_:))
            btn.toolTip = it.title

            let textH: CGFloat = s.showButtonsText ? 14 : 0
            let w = max(iconSize + 18, textWidth(it.title) + 12)
            let h = iconSize + textH + (large ? 12 : 8)
            btn.frame = NSRect(x: x, y: 4, width: w, height: h)
            addSubview(btn)
            buttons.append(btn)
            x += w + 2
            maxH = max(maxH, h)
        }
        frame.size.height = maxH + 8
        // 没有按钮时不留高度，免得空出一条
        preferredHeight = maxH > 0 ? maxH + 8 : 0
    }

    private func textWidth(_ s: String) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width
    }

    @objc private func clicked(_ sender: ToolbarButton) {
        guard let a = MainWindowController.Action(rawValue: sender.tag) else { return }
        target?.performAction(a)
    }

    /// 自检用：每个按钮的标题与可用状态
    var stateDump: String {
        buttons.map { "\($0.title.isEmpty ? "(notext)" : $0.title)=\($0.isEnabled ? "on" : "off")" }
            .joined(separator: " ")
    }
}

// MARK: - 主窗口

final class MainWindowController: NSWindowController, NSWindowDelegate {

    enum Action: Int {
        case add = 1, extract, smartExtract, test, copyTo, moveTo, delete, properties
        case open, openInside, openOutside, view, edit, rename
        case createFolder, createFile, split, combine, diff, comment
        case selectAll, deselectAll, invertSelection, selectMask, deselectMask
        case selectByType, deselectByType
        case viewLargeIcons, viewSmallIcons, viewList, viewDetails
        case sortName, sortType, sortDate, sortSize, sortNone
        case flatView, twoPanels, openRoot, upOneLevel, foldersHistory, refresh, autoRefresh
        case toggleArchiveToolbar, toggleStandardToolbar, largeButtons, showButtonsText
        case addFavorite, options, benchmark, tempDir
        case helpContents, about, exit
    }

    private(set) var panels: [FilePanelView] = []
    private let splitView = NSSplitView()
    private let toolbarStrip = ToolbarStripView()
    let operations = Operations()

    private var activeIndex = 0
    var activePanel: FilePanelView { panels[max(0, min(activeIndex, panels.count - 1))] }

    private var toolbarHeight: NSLayoutConstraint!
    private var configObserver: NSObjectProtocol?

    // MARK: 初始化

    init(initialLocation: Location) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = S.fileManager
        window.minSize = NSSize(width: 620, height: 320)
        window.setFrameAutosaveName("SevenZipMainWindow")
        super.init(window: window)
        window.delegate = self

        buildUI(initialLocation: initialLocation)
        // 菜单的勾选状态和可用性要看当前面板，所以必须等面板建出来之后再建菜单
        setPanelsCount(LaunchArgs.panels ?? Settings.shared.numPanels, initial: initialLocation)
        buildMenu()
        Engine.probeVersion()
        window.makeKeyAndOrderFront(nil)

        configObserver = NotificationCenter.default.addObserver(
            forName: .sevenZipSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.applySettings()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let o = configObserver { NotificationCenter.default.removeObserver(o) }
    }

    private func buildUI(initialLocation: Location) {
        guard let content = window?.contentView else { return }

        toolbarStrip.target = self
        toolbarStrip.translatesAutoresizingMaskIntoConstraints = false

        let toolbarSeparator = NSBox()
        toolbarSeparator.boxType = .separator
        toolbarSeparator.translatesAutoresizingMaskIntoConstraints = false

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(toolbarStrip)
        content.addSubview(toolbarSeparator)
        content.addSubview(splitView)

        toolbarHeight = toolbarStrip.heightAnchor.constraint(
            equalToConstant: toolbarStrip.preferredHeight)

        NSLayoutConstraint.activate([
            toolbarStrip.topAnchor.constraint(equalTo: content.topAnchor),
            toolbarStrip.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolbarStrip.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            toolbarHeight,

            toolbarSeparator.topAnchor.constraint(equalTo: toolbarStrip.bottomAnchor),
            toolbarSeparator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolbarSeparator.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            splitView.topAnchor.constraint(equalTo: toolbarSeparator.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        _ = initialLocation
    }

    // MARK: 面板管理

    private func makePanel(_ loc: Location) -> FilePanelView {
        let p = FilePanelView(location: loc)
        p.onFocus = { [weak self] panel in self?.focus(panel) }
        p.onOpenEntry = { [weak self] panel, entry in self?.open(entry, in: panel) }
        p.onAction = { [weak self] panel, action in self?.runPanelAction(panel, action) }
        p.onToggleTwoPanels = { [weak self] in self?.toggleTwoPanels() }
        p.onCyclePanels = { [weak self] in self?.cyclePanels() }
        p.onSetViewMode = { [weak self] mode in self?.setViewMode(mode) }
        p.onShowHistory = { [weak self] in self?.showFoldersHistory() }
        p.onHashRequest = { [weak self] panel, kind in self?.calculateHash(panel, kind) }
        p.onPathChange = { [weak self] panel in self?.pathChanged(panel) }
        p.onFilesDropped = { [weak self] panel, urls in self?.handleDrop(panel, urls: urls) }
        p.onError = { [weak self] title, message in
            DialogKit.alert(title, message, style: .critical, parent: self?.window)
        }
        return p
    }

    private func setPanelsCount(_ count: Int, initial: Location? = nil) {
        let n = max(1, min(2, count))
        // 已经在用的目录不要丢：切换单/双面板时原地保留
        let kept = panels.map { $0.location }
        for v in splitView.arrangedSubviews { v.removeFromSuperview() }
        panels.removeAll()

        let firstLoc = initial ?? kept.first ?? Location(root: NSHomeDirectory())
        let first = makePanel(firstLoc)
        splitView.addArrangedSubview(first)
        panels.append(first)

        if n == 2 {
            let secondLoc = initial ?? (kept.count > 1 ? kept[1] : firstLoc)
            let second = makePanel(secondLoc)
            splitView.addArrangedSubview(second)
            panels.append(second)
        }

        // 命令行指定面板数时（截图检查用）不要写回设置
        if LaunchArgs.panels == nil { Settings.shared.numPanels = n }
        if n == 2 {
            // 分割位置要等布局完成后再设，否则 splitView.bounds 还是 0，
            // 左侧面板会被挤成一条缝
            window?.layoutIfNeeded()
            splitView.setPosition(max(splitView.bounds.width / 2, 320), ofDividerAt: 0)
        }

        for p in panels { p.refresh(preserveSelection: false) }
        focus(panels.first!)
        // 焦点默认落在文件列表上（Windows 版打开就是选中列表），不要停在地址栏
        panels.first?.focusTable()
    }

    private func focus(_ panel: FilePanelView) {
        guard let idx = panels.firstIndex(where: { $0 === panel }) else { return }
        activeIndex = idx
        for (i, p) in panels.enumerated() {
            p.layer?.borderWidth = (i == idx) ? 1 : 0
            p.layer?.borderColor = (i == idx)
                ? NSColor.controlAccentColor.withAlphaComponent(0.45).cgColor
                : NSColor.clear.cgColor
        }
        updateWindowTitle()
    }

    private func pathChanged(_ panel: FilePanelView) {
        if panel === activePanel { updateWindowTitle() }
    }

    /// Windows 版的窗口标题就是当前面板的路径（App.cpp RefreshTitlePanel）
    private func updateWindowTitle() {
        window?.title = activePanel.location.display
    }

    private func cyclePanels() {
        guard panels.count > 1 else { return }
        let next = panels[(activeIndex + 1) % panels.count]
        next.focusTable()
    }

    private func toggleTwoPanels() {
        setPanelsCount(panels.count == 2 ? 1 : 2,
                       initial: nil)
    }

    private func applySettings() {
        toolbarStrip.rebuild()
        toolbarHeight.constant = toolbarStrip.preferredHeight
        if Settings.shared.numPanels != panels.count {
            setPanelsCount(Settings.shared.numPanels)
        }
        let vm = Settings.shared.viewMode
        for p in panels { p.setViewMode(vm) }
        // 「显示隐藏项」「显示 ..」这类改动只影响列表内容，不重读一次目录看不出来
        for p in panels { p.refresh() }
    }

    // MARK: 工具条状态

    /// 自检用：工具条按钮的可用状态。
    /// 主工具栏的按钮始终可用 —— 整个 7-Zip 源码里只有地址栏那个「上一级」按钮
    /// 会被 EnableButton（PanelItems.cpp:523），这 7 个没有对应的启用/禁用逻辑。
    var toolbarStateDump: String { toolbarStrip.stateDump }

    /// 开发用：把 --dialog 指定的那个对话框直接调起来，配合 --capture 做离屏截图检查
    func openInspectionDialog(_ name: String) {
        // Add 对话框里「Options」那一层，单独调起来截图核对
        if name == "addoptions" {
            _ = AdvancedDialog.run(flags: AdvancedOptions(), parent: nil)
            return
        }
        let map: [String: Action] = [
            "extract": .extract, "add": .add, "options": .options, "about": .about,
            "benchmark": .benchmark, "properties": .properties, "split": .split,
            "combine": .combine, "diff": .diff, "help": .helpContents,
            "foldersHistory": .foldersHistory, "createFolder": .createFolder,
            "createFile": .createFile, "selectMask": .selectMask,
            "selectByType": .selectByType, "rename": .rename, "copyTo": .copyTo,
        ]
        guard let a = map[name] else { return }
        performAction(a)
    }

    func performAction(_ a: Action) {        switch a {
        case .add: doAdd()
        case .extract: doExtract()
        case .smartExtract: doSmartExtract()
        case .test: doTest()
        case .copyTo: doCopyMove(move: false)
        case .moveTo: doCopyMove(move: true)
        case .delete: doDelete()
        case .properties: doProperties()
        case .open: if let e = activePanel.selectedEntry { open(e, in: activePanel) }
        case .openInside: doOpenInside()
        case .openOutside: doOpenOutside()
        case .view: doView()
        case .edit: doEdit()
        case .rename: doRename()
        case .createFolder: doCreateFolder()
        case .createFile: doCreateFile()
        case .split: doSplit()
        case .combine: doCombine()
        case .diff: doDiff()
        case .selectAll: activePanel.tableView.selectAll(nil); activePanel.updateStatus()
        case .deselectAll: activePanel.tableView.deselectAll(nil); activePanel.updateStatus()
        case .invertSelection: invertSelection()
        case .selectMask: doMaskSelect(select: true)
        case .deselectMask: doMaskSelect(select: false)
        case .selectByType: doSelectByType(select: true)
        case .deselectByType: doSelectByType(select: false)
        case .viewLargeIcons: setViewMode(0)
        case .viewSmallIcons: setViewMode(1)
        case .viewList: setViewMode(2)
        case .viewDetails: setViewMode(3)
        case .sortName: setSort(Columns.name)
        case .sortType: setSort("type")
        case .sortDate: setSort(Columns.mtime)
        case .sortSize: setSort(Columns.size)
        case .sortNone: setSort("")
        case .twoPanels: toggleTwoPanels()
        case .openRoot: activePanel.navigate(to: Location(root: "/"))
        case .upOneLevel: activePanel.goUp()
        case .foldersHistory: showFoldersHistory()
        case .refresh: for p in panels { p.refresh() }
        case .autoRefresh: Settings.shared.autoRefresh.toggle(); buildMenu()
        case .toggleArchiveToolbar:
            Settings.shared.showArchiveToolbar.toggle(); applySettings(); buildMenu()
        case .toggleStandardToolbar:
            Settings.shared.showStandardToolbar.toggle(); applySettings(); buildMenu()
        case .largeButtons:
            Settings.shared.largeButtons.toggle(); applySettings(); buildMenu()
        case .showButtonsText:
            Settings.shared.showButtonsText.toggle(); applySettings(); buildMenu()
        case .addFavorite: addFavorite()
        case .options: OptionsDialog.run(parent: window)
        case .benchmark: runBenchmark()
        case .tempDir: deleteTempFiles()
        case .helpContents: showHelp()
        case .about: AboutDialog.show(parent: window)
        case .exit: NSApp.terminate(nil)
        default: break
        }
    }

    private func runPanelAction(_ panel: FilePanelView, _ action: FilePanelView.PanelAction) {
        focus(panel)
        switch action {
        case .open: if let e = panel.selectedEntry { open(e, in: panel) }
        case .openInside: doOpenInside()
        case .openOutside: doOpenOutside()
        case .view: doView()
        case .edit: doEdit()
        case .rename: doRename()
        case .copyTo: doCopyMove(move: false)
        case .moveTo: doCopyMove(move: true)
        case .delete: doDelete()
        case .properties: doProperties()
        case .diff: doDiff()
        case .createFolder: doCreateFolder()
        case .createFile: doCreateFile()
        case .split: doSplit()
        case .combine: doCombine()
        case .extract: doExtract()
        case .smartExtract: doSmartExtract()
        case .add: doAdd()
        case .test: doTest()
        case .comment: break
        }
    }

    // MARK: 打开 / 浏览

    private func open(_ entry: FileEntry, in panel: FilePanelView) {
        if entry.isDir {
            if panel.location.isArchive {
                var loc = panel.location
                loc.inner = entry.fullPath
                panel.navigate(to: loc)
            } else {
                panel.navigate(to: Location(root: entry.fullPath))
            }
            return
        }
        if entry.isArchive {
            openArchive(entry, in: panel)
            return
        }
        doOpenOutside()
    }

    /// 进入归档。双击走的是「点中的那一条」，菜单 / Ctrl+PgDn 走的是当前选中项。
    private func doOpenInside() {
        guard let e = activePanel.selectedEntry else { return }
        if activePanel.location.isArchive, e.isDir {
            var loc = activePanel.location
            loc.inner = e.fullPath
            activePanel.navigate(to: loc)
            return
        }
        guard e.isArchive else { return }
        openArchive(e, in: activePanel)
    }

    private func openArchive(_ entry: FileEntry, in panel: FilePanelView) {
        if !panel.location.isArchive {
            panel.setPassword(nil)
            panel.navigate(to: Location(root: entry.fullPath))
            return
        }
        // 归档里的归档：先把这个条目解到临时目录，再打开
        extractToTempAndOpen(entry, in: panel)
    }

    private func extractToTempAndOpen(_ entry: FileEntry, in panel: FilePanelView) {
        let archive = panel.location.root
        let dir = NSTemporaryDirectory() + "7zip-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var args = ["e", "-o" + dir, "-y"]
        if let pw = panel.password, !pw.isEmpty { args.append("-p" + pw) }
        args.append(archive)
        args.append(entry.fullPath)

        DispatchQueue.global(qos: .userInitiated).async {
            _ = try? Engine.runSync(args)
            let target = (dir as NSString).appendingPathComponent(entry.name)
            DispatchQueue.main.async {
                guard FileManager.default.fileExists(atPath: target) else {
                    panel.onError?("7-Zip", S.cantOpenArchive
                        .replacingOccurrences(of: "{0}", with: entry.name))
                    return
                }
                var loc = Location(root: target)
                loc.temporary = true
                panel.navigate(to: loc)
            }
        }
    }

    private func doOpenOutside() {
        let entries = activePanel.selectedEntries()
        guard !entries.isEmpty else { return }
        if activePanel.location.isArchive {
            // 归档里的文件：先解压到临时目录再交给系统打开
            let dir = NSTemporaryDirectory() + "7zip-" + UUID().uuidString
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            var args = ["x", "-o" + dir, "-y"]
            if let pw = activePanel.password, !pw.isEmpty { args.append("-p" + pw) }
            args.append(activePanel.location.root)
            args.append(contentsOf: entries.map { $0.fullPath })
            DispatchQueue.global(qos: .userInitiated).async {
                _ = try? Engine.runSync(args)
                DispatchQueue.main.async {
                    for e in entries {
                        let f = (dir as NSString).appendingPathComponent(e.fullPath)
                        if FileManager.default.fileExists(atPath: f) {
                            NSWorkspace.shared.open(URL(fileURLWithPath: f))
                        }
                    }
                }
            }
            return
        }
        for e in entries {
            NSWorkspace.shared.open(URL(fileURLWithPath: e.fullPath))
        }
    }

    // MARK: 查看 / 编辑

    private func doView() {
        guard let e = activePanel.selectedEntry, !e.isDir else {
            DialogKit.alert(S.selectOneFile, "", parent: window); return
        }
        if activePanel.location.isArchive {
            let dir = NSTemporaryDirectory() + "7zip-" + UUID().uuidString
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            var args = ["e", "-o" + dir, "-y"]
            if let pw = activePanel.password, !pw.isEmpty { args.append("-p" + pw) }
            args.append(activePanel.location.root)
            args.append(e.fullPath)
            DispatchQueue.global(qos: .userInitiated).async {
                _ = try? Engine.runSync(args)
                let f = (dir as NSString).appendingPathComponent(e.name)
                DispatchQueue.main.async { Viewer.show(path: f, title: e.name) }
            }
        } else {
            Viewer.show(path: e.fullPath, title: e.name)
        }
    }

    private func doEdit() {
        guard let e = activePanel.selectedEntry, !e.isDir else {
            DialogKit.alert(S.selectOneFile, "", parent: window); return
        }
        if !activePanel.location.isArchive {
            NSWorkspace.shared.open(URL(fileURLWithPath: e.fullPath))
        } else {
            doOpenOutside()
        }
    }

    // MARK: 改名

    private func doRename() {
        let sel = activePanel.selectedEntries()
        guard sel.count == 1, let e = sel.first else {
            DialogKit.alert(S.selectOneFile, "", parent: window); return
        }
        guard let newName = DialogKit.prompt(S.menuRename, caption: S.propName + ":", initial: e.name,
                                            parent: window)
        else { return }

        if activePanel.location.isArchive {
            operations.renameInArchive(archive: activePanel.location.root,
                                       pairs: [(e.fullPath, replacingLast(e.fullPath, with: newName))],
                                       password: activePanel.password, parent: window)
            activePanel.refresh(preserveSelection: false)
        } else {
            let dst = ((e.fullPath as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent(newName)
            do {
                try FileManager.default.moveItem(atPath: e.fullPath, toPath: dst)
            } catch {
                DialogKit.alert(S.errorRenaming, error.localizedDescription,
                                style: .critical, parent: window)
            }
            activePanel.refresh(preserveSelection: false)
        }
    }

    private func replacingLast(_ path: String, with name: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? name : parent + "/" + name
    }

    // MARK: 复制 / 移动 / 删除

    private func doCopyMove(move: Bool) {
        let entries = activePanel.selectedEntries()
        guard !entries.isEmpty else { return }

        if activePanel.location.isArchive {
            // 从归档里复制出来 = 解压
            var o = ExtractOptions()
            o.destination = pickFolder(title: move ? S.menuMoveTo : S.menuCopyTo) ?? ""
            guard !o.destination.isEmpty else { return }
            o.pathMode = .full
            o.overwrite = .ask
            o.password = activePanel.password ?? ""
            let total = entries.reduce(Int64(0)) { $0 + $1.size }
            operations.extract(archive: activePanel.location.root,
                               names: entries.map { $0.fullPath },
                               options: o, totalBytes: total, parent: window)
            return
        }

        guard let destination = pickFolder(title: move ? S.menuMoveTo : S.menuCopyTo) else { return }
        let urls = entries.map { URL(fileURLWithPath: $0.fullPath) }
        operations.copyOrMove(urls, to: destination, move: move, parent: window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.activePanel.refresh()
        }
    }

    private func pickFolder(title: String) -> String? {
        let panel = NSOpenPanel()
        panel.message = title
        panel.prompt = S.ok
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK else { return nil }
        return panel.url?.path
    }

    /// File > Properties。Windows 版对文件系统条目直接弹系统属性页；
    /// 这里按 7-Zip 自己那套字段画（PropertiesDialog.cpp）。
    private func doProperties() {
        let panel = activePanel
        let sel = panel.selectedEntries()
        guard let first = sel.first else { return }

        if sel.count > 1 {
            // 多选：路径 + 条目数 + 文件夹/文件计数 + 合计大小
            let files = sel.filter { !$0.isDir }.count
            let folders = sel.count - files
            let total = sel.reduce(Int64(0)) { $0 + max($1.size, 0) }

            func ro(_ s: String) -> NSTextField {
                let f = DialogKit.label(s)
                f.isSelectable = true
                f.lineBreakMode = .byTruncatingMiddle
                f.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                return f
            }
            let fb = FormBuilder()
            fb.add(S.propPath, ro(panel.location.display))
            fb.add(S.propType, ro("\(sel.count) \(S.propItems)"))
            if folders > 0 { fb.add(S.propFolders, ro(String(folders))) }
            if files > 0 { fb.add(S.propFiles, ro(String(files))) }
            fb.add(S.propSize, ro(Fmt.size(total)))

            let form = DialogKit.makeSheet(title: S.propertiesTitle,
                                           content: fb.makeView(labelWidth: 130),
                                           okTitle: S.ok, width: 600)
            DialogKit.runModal(form, parent: window)
            return
        }

        PropertiesDialog.run(entry: first, location: panel.location, parent: window)
    }

    private func doDelete() {
        let entries = activePanel.selectedEntries()
        guard !entries.isEmpty else { return }

        let message: String
        if entries.count == 1 {
            message = entries[0].isDir
                ? S.wantToDeleteFolder.replacingOccurrences(of: "{0}", with: entries[0].name)
                : S.wantToDeleteFile.replacingOccurrences(of: "{0}", with: entries[0].name)
        } else {
            message = S.wantToDeleteItems.replacingOccurrences(of: "{0}", with: String(entries.count))
        }
        let title = entries.count > 1 ? S.confirmItemsDelete
            : (entries[0].isDir ? S.confirmFolderDelete : S.confirmFileDelete)
        guard DialogKit.confirm(title, message, parent: window) else { return }

        if activePanel.location.isArchive {
            operations.deleteInArchive(archive: activePanel.location.root,
                                       names: entries.map { $0.fullPath },
                                       password: activePanel.password, parent: window)
            activePanel.refresh(preserveSelection: false)
            return
        }

        operations.trash(entries.map { URL(fileURLWithPath: $0.fullPath) }) { [weak self] errors in
            if !errors.isEmpty {
                DialogKit.alert(S.errorDeleting, errors.joined(separator: "\n"),
                                style: .critical, parent: self?.window)
            }
            self?.activePanel.refresh(preserveSelection: false)
        }
    }

    // MARK: 解压 / 压缩 / 测试

    private func doExtract() {
        let panel = activePanel
        if panel.location.isArchive {
            let sel = panel.selectedEntries()
            let current = panel.location
            let baseDir = (current.root as NSString).deletingLastPathComponent
            guard var o = ExtractDialog.run(archive: current.root, baseDir: baseDir, parent: window)
            else { return }
            o.password = o.password.isEmpty ? (panel.password ?? "") : o.password
            let total = sel.isEmpty
                ? (panel.listing?.entries.reduce(Int64(0)) { $0 + $1.size } ?? 0)
                : sel.reduce(Int64(0)) { $0 + $1.size }
            operations.extract(archive: current.root,
                               names: sel.map { $0.fullPath },
                               options: o, totalBytes: total, parent: window)
            return
        }

        // 文件系统里：对着选中的归档文件做解压
        var archives = panel.selectedEntries().filter { $0.isArchive }.map { $0.fullPath }
        if archives.isEmpty {
            // 没有选归档，就看当前目录里有没有归档
            let all = panel.entries.filter { $0.isArchive }.map { $0.fullPath }
            guard !all.isEmpty else {
                DialogKit.alert("7-Zip", S.cantOpenArchive.replacingOccurrences(of: "{0}", with: ""),
                                parent: window)
                return
            }
            archives = all
        }
        let first = archives[0]
        let dir = (first as NSString).deletingLastPathComponent
        guard let o = ExtractDialog.run(archive: first, baseDir: dir, parent: window) else { return }
        if archives.count > 1 {
            // 多个归档：只弹一次对话框，各自解到同名的子目录
            for a in archives {
                let dst = (o.destination as NSString).deletingLastPathComponent
                var sub = o
                sub.destination = Operations.defaultExtractFolder(archive: a, fallbackDir: dst)
                let total = ArchiveSizer.totalSize(archive: a, password: nil)
                operations.extract(archive: a, names: [], options: sub,
                                   totalBytes: total, parent: window)
            }
            return
        }
        let total = ArchiveSizer.totalSize(archive: first, password: o.password.isEmpty ? nil : o.password)
        operations.extract(archive: first, names: [], options: o, totalBytes: total, parent: window)
        _ = dir
        Settings.shared.lastExtractPath = o.destination
    }

    /// 解压（智能）。落点由压缩包的顶层结构决定，规则见 SmartExtract。
    ///
    /// 已经在归档面板里时（`location.isArchive`）直接转给普通解压 —— 智能解压要判断的是
    /// 「这个包摊开长什么样」，而此刻用户看的就是摊开后的内容，再问一次没有意义，
    /// 缺的只是「解到哪个目录」这个选择，那正是 ExtractDialog 的活儿。
    private func doSmartExtract() {
        let panel = activePanel
        guard !panel.location.isArchive else {
            doExtract()
            return
        }

        var archives = panel.selectedEntries().filter { $0.isArchive }.map { $0.fullPath }
        if archives.isEmpty {
            archives = panel.entries.filter { $0.isArchive }.map { $0.fullPath }
        }
        guard !archives.isEmpty else {
            DialogKit.alert("7-Zip", S.mustSelectArchives, parent: window)
            return
        }
        smartExtract(archives)
    }

    /// 对一批归档逐个做智能解压。列表里点「解压（智能）」走这里，
    /// 自检通道（--automation 的 unzip）也走这里，保证测的就是用户点的那条路。
    func smartExtract(_ archives: [String]) {
        // 一个面板里的归档都在同一个目录，所以冲突问题只问一次
        var answered: ExtractOverwriteMode?
        for a in archives {
            let here = (a as NSString).deletingLastPathComponent
            let dest = SmartExtract.destination(archive: a, password: nil)
            var mode: ExtractOverwriteMode = .overwrite
            // 只有「摊在压缩包所在目录」这一种落点会撞上已有文件，
            // 新建文件夹那条的落点本来就是空的
            if dest == here {
                let hits = SmartExtract.existingTopLevel(archive: a, destination: dest, password: nil)
                if !hits.isEmpty {
                    if let a = answered {
                        mode = a
                    } else {
                        guard let m = OverwritePrompt.resolve(conflicts: hits, destination: dest,
                                                              parent: window) else { return }
                        mode = m
                        answered = m
                    }
                }
            }
            var o = ExtractOptions()
            o.destination = dest
            o.pathMode = .full
            o.overwrite = mode
            try? FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)
            operations.extract(archive: a, names: [], options: o,
                               totalBytes: ArchiveSizer.totalSize(archive: a, password: nil),
                               parent: window)
        }
    }

    private func doAdd() {
        let panel = activePanel
        guard !panel.location.isArchive else {
            DialogKit.alert(S.addTitle, S.updateNotSupported, parent: window)
            return
        }
        let sel = panel.selectedEntries()
        let files = sel.isEmpty ? panel.entries.map { $0.name } : sel.map { $0.name }
        guard !files.isEmpty else { return }
        let total = sel.isEmpty
            ? panel.entries.reduce(Int64(0)) { $0 + $1.size }
            : sel.reduce(Int64(0)) { $0 + $1.size }

        guard let (archive, options) = AddDialog.run(targets: sel.map { $0.fullPath },
                                                     inWorkingDir: panel.location.display,
                                                     totalBytes: total, parent: window)
        else { return }

        operations.add(archive: archive, files: files,
                       workingDirectory: panel.location.display,
                       options: options, totalBytes: total, parent: window)
    }

    private func doTest() {
        let panel = activePanel
        if panel.location.isArchive {
            let total = panel.listing?.entries.reduce(Int64(0)) { $0 + $1.size } ?? 0
            operations.test(archives: [panel.location.root], password: panel.password,
                            totalBytes: total, parent: window)
            return
        }
        let archives = panel.selectedEntries().filter { $0.isArchive }.map { $0.fullPath }
        let list = archives.isEmpty ? panel.entries.filter { $0.isArchive }.map { $0.fullPath } : archives
        guard !list.isEmpty else {
            DialogKit.alert("7-Zip", S.mustSelectArchives, parent: window)
            return
        }
        operations.test(archives: list, password: nil, totalBytes: 0, parent: window)
    }

    private func calculateHash(_ panel: FilePanelView, _ kind: HashKind) {
        let entries = panel.selectedEntries()
        guard !entries.isEmpty else { return }
        if panel.location.isArchive {
            let dir = NSTemporaryDirectory() + "7zip-" + UUID().uuidString
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            var args = ["x", "-o" + dir, "-y"]
            if let pw = panel.password, !pw.isEmpty { args.append("-p" + pw) }
            args.append(panel.location.root)
            args.append(contentsOf: entries.map { $0.fullPath })
            DispatchQueue.global(qos: .userInitiated).async {
                _ = try? Engine.runSync(args)
                DispatchQueue.main.async {
                    let files = entries.map { (dir as NSString).appendingPathComponent($0.fullPath) }
                    self.operations.hash(files: files, kind: kind, workingDirectory: dir,
                                         parent: self.window)
                }
            }
            return
        }
        operations.hash(files: entries.map { $0.name }, kind: kind,
                        workingDirectory: panel.location.display, parent: window)
    }

    // MARK: 新建

    private func doCreateFolder() {
        guard let name = DialogKit.prompt(S.menuCreateFolder, caption: S.createFolderName,
                                          initial: S.createFolderDefault, parent: window) else { return }
        if activePanel.location.isArchive {
            DialogKit.alert(S.createFolderError, S.createFolderInArchive,
                            parent: window)
            return
        }
        let path = (activePanel.location.display as NSString).appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
        } catch {
            DialogKit.alert(S.createFolderError, error.localizedDescription,
                            style: .critical, parent: window)
        }
        activePanel.refresh(preserveSelection: false)
    }

    private func doCreateFile() {
        guard let name = DialogKit.prompt(S.menuCreateFile, caption: S.createFilePrompt,
                                          initial: S.createFileDefault, parent: window) else { return }
        guard !activePanel.location.isArchive else { return }
        let path = (activePanel.location.display as NSString).appendingPathComponent(name)
        if !FileManager.default.createFile(atPath: path, contents: Data()) {
            DialogKit.alert(S.createFileError, path, style: .critical, parent: window)
        }
        activePanel.refresh(preserveSelection: false)
    }

    // MARK: 拆分 / 合并 / 比较

    private func doSplit() {
        guard let e = activePanel.selectedEntry, !e.isDir, !activePanel.location.isArchive else {
            DialogKit.alert(S.selectOneFile, "", parent: window); return
        }
        let size = max(e.size / 10, 1024 * 1024)
        guard let vol = SplitDialog.run(file: e.fullPath, size: size, parent: window), vol > 0 else { return }
        operations.split(file: e.fullPath, volumeBytes: vol, parent: window)
    }

    private func doCombine() {
        let sel = activePanel.selectedEntries().filter { !$0.isDir }
        guard sel.count >= 2 else {
            DialogKit.alert(S.selectOneFile, "", parent: window); return
        }
        let sorted = sel.sorted { Sorter.naturalCompare($0.name, $1.name) == .orderedAscending }
        let out = "\((activePanel.location.display as NSString).appendingPathComponent(sorted[0].name)).combined"
        guard DialogKit.prompt(S.menuCombine, caption: S.combineTo,
                               initial: (out as NSString).lastPathComponent,
                               parent: window) != nil else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            var error: String?
            FileManager.default.createFile(atPath: out, contents: nil)
            guard let handle = FileHandle(forWritingAtPath: out) else {
                DialogKit.alert(S.progressCombining, S.cannotCreateOutput, parent: nil)
                return
            }
            for e in sorted {
                if let d = try? Data(contentsOf: URL(fileURLWithPath: e.fullPath)) {
                    handle.write(d)
                } else {
                    error = e.name
                    break
                }
            }
            try? handle.close()
            DispatchQueue.main.async {
                if let error {
                    DialogKit.alert(S.progressCombining,
                                     S.cannotReadNamed.replacingOccurrences(of: "{0}", with: error),
                                     parent: self.window)
                } else {
                    self.activePanel.refresh(preserveSelection: false)
                }
            }
        }
    }

    private func doDiff() {
        let sel = activePanel.selectedEntries()
        guard sel.count == 2, !activePanel.location.isArchive else {
            DialogKit.alert(S.menuDiff, S.selectTwoFiles, parent: window); return
        }
        let a = sel[0].fullPath, b = sel[1].fullPath
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/diff")
            p.arguments = ["-u", a, b]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            try? p.run()
            let d = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let text = String(decoding: d, as: UTF8.self)
            DispatchQueue.main.async {
                TextWindow.show(title: "\(S.menuDiff): \(sel[0].name) / \(sel[1].name)",
                                text: text.isEmpty ? S.noDifferences : text)
            }
        }
    }

    // MARK: 选择

    private func invertSelection() {
        let tv = activePanel.tableView
        var idx = IndexSet()
        for i in 0..<activePanel.entries.count where !tv.selectedRowIndexes.contains(i) {
            idx.insert(i)
        }
        tv.selectRowIndexes(idx, byExtendingSelection: false)
        activePanel.updateStatus()
    }

    private func doMaskSelect(select: Bool) {
        let title = select ? S.menuSelect : S.menuDeselect
        guard let mask = MaskDialog.run(title: title, parent: window) else { return }
        let tv = activePanel.tableView
        var idx = tv.selectedRowIndexes
        let re = wildcardRegex(mask)
        for (i, e) in activePanel.entries.enumerated() {
            let full = NSRange(e.name.startIndex..<e.name.endIndex, in: e.name)
            let match = re.map { $0.firstMatch(in: e.name, options: [], range: full) != nil } ?? false
            if match {
                if select { idx.insert(i) } else { idx.remove(i) }
            }
        }
        tv.selectRowIndexes(idx, byExtendingSelection: false)
        activePanel.updateStatus()
    }

    private func doSelectByType(select: Bool) {
        let sel = activePanel.selectedEntries()
        guard let first = sel.first else {
            DialogKit.alert(S.selectOneFile, "", parent: window); return
        }
        let ext = first.fileExtension
        let tv = activePanel.tableView
        var idx = tv.selectedRowIndexes
        for (i, e) in activePanel.entries.enumerated() where e.fileExtension == ext {
            if select { idx.insert(i) } else { idx.remove(i) }
        }
        tv.selectRowIndexes(idx, byExtendingSelection: false)
        activePanel.updateStatus()
    }

    /// 把 * ? 通配符转成正则（和 7-Zip 的掩码语义一致）
    private func wildcardRegex(_ mask: String) -> NSRegularExpression? {
        var pattern = "^"
        for ch in mask {
            switch ch {
            case "*": pattern += ".*"
            case "?": pattern += "."
            default: pattern += NSRegularExpression.escapedPattern(for: String(ch))
            }
        }
        pattern += "$"
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    // MARK: 视图 / 排序

    private func setViewMode(_ mode: Int) {
        Settings.shared.viewMode = mode
        for p in panels { p.setViewMode(mode) }
        buildMenu()
    }

    private func setSort(_ key: String) {
        for p in panels {
            p.sortKey = key
            p.sortAscending = Sorter.defaultAscending(for: key)
        }
        activePanel.refresh(preserveSelection: true)
        buildMenu()
    }

    // MARK: 收藏夹 / 历史

    private func addFavorite() {
        guard let name = DialogKit.prompt(S.menuAddToFavorites, caption: S.propName + ":",
                                          initial: (activePanel.location.display as NSString).lastPathComponent,
                                          parent: window) else { return }
        var f = Settings.shared.favorites
        f.append(["name": name, "path": activePanel.location.display])
        Settings.shared.favorites = f
        buildMenu()
    }

    private func showFoldersHistory() {
        FoldersHistoryDialog.run(parent: window) { [weak self] path in
            self?.activePanel.navigate(toPath: path)
        }
    }

    // MARK: 拖放

    private func handleDrop(_ panel: FilePanelView, urls: [URL]) {
        focus(panel)
        if panel.location.isArchive {
            // 往归档里追加
            let names = urls.map { $0.lastPathComponent }
            let dir = urls.first?.deletingLastPathComponent().path ?? NSHomeDirectory()
            var o = AddOptions()
            o.format = archiveFormatForName(panel.location.root)
            o.updateMode = .update
            o.password = panel.password ?? ""
            let total = urls.reduce(Int64(0)) { $0 + Operations.sizeOfItem(at: $1.path) }
            operations.add(archive: panel.location.root, files: names, workingDirectory: dir,
                           options: o, totalBytes: total, parent: window)
            return
        }
        // 拖进窗口 = 「我要压这些」。原来这里是 copyOrMove，等于从 Windows 版把
        // 「往面板里拖 = 复制到该目录」照抄了过来，但 macOS 上这么拖的用户意图
        // 基本只有一个：把这几样东西打成一个包。
        //
        // 按住 ⌘ 仍按老规矩复制，留一条退路（面板之间搬文件用得上）。
        // 用 ⌘ 不用 ⌥：⌥ 在文件管理器里通常是「复制」的备用键，语义正好反过来。
        if NSEvent.modifierFlags.contains(.command) {
            operations.copyOrMove(urls, to: panel.location.display, move: false, parent: window)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { panel.refresh() }
            return
        }
        guard let first = urls.first else { return }
        let dir = first.deletingLastPathComponent().path
        let total = urls.reduce(Int64(0)) { $0 + Operations.sizeOfItem(at: $1.path) }
        // 和右键「使用 7-Zip 压缩…」走的是同一个对话框、同一套默认参数
        guard let (archive, options) = AddDialog.run(targets: urls.map { $0.path },
                                                     inWorkingDir: dir,
                                                     totalBytes: total, parent: window) else { return }
        // 传绝对路径：拖进来的东西可能跨目录，只传文件名会让引擎在 dir 里找错文件。
        // 实测 7zz 对绝对路径只取末一段，所以包内存的仍是原来的名字。
        operations.add(archive: archive, files: urls.map { $0.path },
                       workingDirectory: dir, options: options,
                       totalBytes: total, parent: window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { panel.refresh() }
    }

    private func archiveFormatForName(_ path: String) -> String {
        let base = (path as NSString).lastPathComponent.lowercased()
        if base.hasSuffix(".zip") { return "zip" }
        if base.hasSuffix(".tar") { return "tar" }
        if base.hasSuffix(".gz") { return "gzip" }
        if base.hasSuffix(".bz2") { return "bzip2" }
        if base.hasSuffix(".xz") { return "xz" }
        return "7z"
    }

    // MARK: 基准测试 / 临时文件

    private var benchmarkWindow: ProgressWindowController?

    private func runBenchmark() {
        let model = ProgressModel(kind: .benchmark, subject: "")
        let wc = ProgressWindowController(model: model)
        benchmarkWindow = wc
        let task = EngineTask(arguments: ["b", "-bsp1"])
        wc.attach(task)
        var out: [String] = []
        task.onMessage = { out.append($0) }
        task.onProgress = { p in model.update(percent: p.percent, file: "") }
        task.onFinish = { _ in
            wc.finish()
            TextWindow.show(title: S.menuBenchmark, text: out.joined(separator: "\n"),
                            width: 700, height: 480)
        }
        wc.show()
        task.run()
    }

    private func deleteTempFiles() {
        let tmp = NSTemporaryDirectory()
        let fm = FileManager.default
        var removed = 0
        if let items = try? fm.contentsOfDirectory(atPath: tmp) {
            for i in items where i.hasPrefix("7zip-") {
                if (try? fm.removeItem(atPath: (tmp as NSString).appendingPathComponent(i))) != nil {
                    removed += 1
                }
            }
        }
        DialogKit.alert("7-Zip",
                        "\(S.menuTempDir) — "
                        + S.itemsDeleted.replacingOccurrences(of: "{0}", with: "\(removed)"),
                        parent: window)
    }

    private func showHelp() {
        TextWindow.show(title: S.menuHelpContents, text: S.helpText, width: 660, height: 520)
    }

    // MARK: 其它

    func openPath(_ path: String) {
        activePanel.navigate(toPath: path)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}

// MARK: - 归档体积（用于进度百分比的分母）

enum ArchiveSizer {
    static func totalSize(archive: String, password: String?) -> Int64 {
        var args = ["l", "-slt"]
        if let p = password, !p.isEmpty { args.append("-p" + p) }
        args.append(archive)
        guard let r = try? Engine.runSync(args) else { return 0 }
        let listing = FolderLoader.parseListing(r.stdout)
        return listing.entries.reduce(Int64(0)) { $0 + $1.size }
    }
}

// MARK: - 查看器（File -> View）

enum Viewer {
    static func show(path: String, title: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            TextWindow.show(title: title, text: S.cannotReadFile)
            return
        }
        let head = data.prefix(4096)
        let nonPrintable = head.filter { $0 < 9 || ($0 > 13 && $0 < 32) }.count
        let isBinary = !head.isEmpty && Double(nonPrintable) / Double(head.count) > 0.1

        if isBinary {
            let limit = min(data.count, 64 * 1024)
            var lines: [String] = []
            var offset = 0
            let bytes = [UInt8](data.prefix(limit))
            while offset < bytes.count {
                let chunk = bytes[offset..<min(offset + 16, bytes.count)]
                let hex = chunk.map { String(format: "%02X", $0) }.joined(separator: " ")
                let ascii = chunk.map { $0 >= 32 && $0 < 127 ? String(UnicodeScalar($0)) : "." }.joined()
                lines.append(String(format: "%08X  %-47@  %@",
                                    offset, hex as NSString, ascii as NSString))
                offset += 16
            }
            TextWindow.show(title: S.hexTitle.replacingOccurrences(of: "{0}", with: title),
                            text: lines.joined(separator: "\n"))
        } else {
            let text = String(decoding: data.prefix(4 * 1024 * 1024), as: UTF8.self)
            TextWindow.show(title: title, text: text)
        }
    }
}
