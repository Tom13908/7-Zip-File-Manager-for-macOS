// 文件面板：一个地址栏 + 一个多列文件列表 + 一条状态栏。
// Windows 版 7-Zip File Manager 里这类面板最多两个，左右并排（F9 切换）。

import AppKit

// MARK: - 单元格

final class FileCellView: NSTableCellView {
    /// 列表正文用的字号。Windows 版是 Segoe UI 9pt，对应的 macOS 系统字号是 12。
    static let fontSize: CGFloat = 12

    let icon = NSImageView()
    let label = NSTextField(labelWithString: "")
    private var iconW: NSLayoutConstraint?
    private var iconH: NSLayoutConstraint?

    /// 视图模式切换时改图标大小（大图标/小图标/列表/详细资料）
    func setIconSize(_ side: CGFloat) {
        iconW?.constant = side
        iconH?.constant = side
    }

    init(showIcon: Bool, rightAligned: Bool) {
        super.init(frame: .zero)
        label.font = NSFont.systemFont(ofSize: FileCellView.fontSize)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = rightAligned ? .right : .left
        label.cell?.usesSingleLineMode = true
        addSubview(label)

        if showIcon {
            icon.imageScaling = .scaleProportionallyDown
            icon.translatesAutoresizingMaskIntoConstraints = false
            addSubview(icon)
            iconW = icon.widthAnchor.constraint(equalToConstant: 16)
            iconH = icon.heightAnchor.constraint(equalToConstant: 16)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconW!, iconH!,
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
            ])
        } else {
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            ])
        }
        NSLayoutConstraint.activate([
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        textField = label
        imageView = showIcon ? icon : nil
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - 表格视图（接管键盘与拖放）

protocol FileTableDelegate: AnyObject {
    func tableDidBecomeFirstResponder(_ table: FileTableView)
    func table(_ table: FileTableView, handleKey key: String, modifiers: NSEvent.ModifierFlags) -> Bool
    func table(_ table: FileTableView, didDoubleClickRow row: Int)
    func table(_ table: FileTableView, acceptDrop urls: [URL]) -> Bool
    func tableNeedsContextMenu(_ table: FileTableView) -> NSMenu?
    func tableClickedEmptyArea(_ table: FileTableView)
}

final class FileTableView: NSTableView {
    weak var fileDelegate: FileTableDelegate?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { fileDelegate?.tableDidBecomeFirstResponder(self) }
        return ok
    }

    override func mouseDown(with event: NSEvent) {
        fileDelegate?.tableDidBecomeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        if row < 0 { fileDelegate?.tableClickedEmptyArea(self) }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if let d = fileDelegate, d.table(self, handleKey: event.charactersIgnoringModifiers ?? "",
                                        modifiers: event.modifierFlags) {
            return
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        if row >= 0 && !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        fileDelegate?.tableDidBecomeFirstResponder(self)
        return fileDelegate?.tableNeedsContextMenu(self)
    }

    // 按住左键拖动行的动作由 NSTableView 自己完成 —— 它会扩选（框选多选），
    // 前提是数据源没有实现 pasteboardWriterForRow（见 FilePanelView 那边的说明）。
    //
    // 注意这里没有 mouseDragged / mouseUp 可写：拖动整段发生在 NSTableView 自己的
    // 跟踪循环里，这两个 override 都不会被调用。所以那个半透明的选择框也画不出来
    // （要画只能另起一套计时器轮询鼠标位置），当前就只有行的选中高亮。
    //
    // 双击由 tableView 的 doubleAction 上报（见 FilePanelView.build），同理不能写在 mouseUp 里。

    // 拖出去（只会在按住 ⌥ 时真正发生）
    override func draggingSession(_ session: NSDraggingSession,
                                  sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

// MARK: - 面板

final class FilePanelView: NSView, NSTableViewDataSource, NSTableViewDelegate,
                           FileTableDelegate, NSMenuDelegate {

    // 数据
    private(set) var location: Location
    private(set) var allEntries: [FileEntry] = []
    private(set) var entries: [FileEntry] = []
    private(set) var listing: ArchiveListing?

    var sortKey: String = Columns.name
    var sortAscending = true
    private var searchFilter = ""

    // 组件
    let tableView = FileTableView()
    private let scrollView = NSScrollView()
    private let pathField = NSTextField()
    private let dropdownButton = NSButton()
    private let upButton = NSButton()
    /// 状态栏的 4 个分区（Panel.cpp 里 SetParts(4, {220, 320, 420, -1})）：
    /// 选中计数 / 选中总大小 / 光标项大小 / 光标项修改时间
    private let statusParts = (0..<4).map { _ in NSTextField(labelWithString: "") }
    private var headerMenu = NSMenu()

    // 外部回调
    var onFocus: ((FilePanelView) -> Void)?
    var onPathChange: ((FilePanelView) -> Void)?
    var onOpenEntry: ((FilePanelView, FileEntry) -> Void)?
    var onError: ((String, String) -> Void)?

    private var visibleColumnIDs: [String] = []

    // MARK: 初始化

    init(location: Location) {
        self.location = location
        super.init(frame: .zero)
        build()
        updateColumnSet()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        wantsLayer = true

        // --- 地址栏
        upButton.bezelStyle = .texturedRounded
        upButton.isBordered = false
        upButton.image = SysIcon.symbol("arrow.up", size: 13, weight: .medium)
        upButton.imagePosition = .imageOnly
        upButton.target = self
        upButton.action = #selector(goUpAction)
        upButton.toolTip = "\(S.menuUpOneLevel)\tBackspace"
        upButton.translatesAutoresizingMaskIntoConstraints = false

        dropdownButton.bezelStyle = .texturedRounded
        dropdownButton.isBordered = false
        dropdownButton.image = SysIcon.symbol("chevron.down", size: 10, weight: .medium)
        dropdownButton.imagePosition = .imageOnly
        dropdownButton.target = self
        dropdownButton.action = #selector(showHistoryMenu)
        dropdownButton.toolTip = S.menuFoldersHistory
        dropdownButton.translatesAutoresizingMaskIntoConstraints = false

        pathField.font = NSFont.systemFont(ofSize: 12)
        pathField.isBordered = true
        pathField.bezelStyle = .squareBezel
        pathField.target = self
        pathField.action = #selector(pathFieldCommitted)
        pathField.translatesAutoresizingMaskIntoConstraints = false
        pathField.cell?.usesSingleLineMode = true
        pathField.lineBreakMode = .byTruncatingHead

        let addressBar = NSView()
        addressBar.translatesAutoresizingMaskIntoConstraints = false
        addressBar.addSubview(upButton)
        addressBar.addSubview(pathField)
        addressBar.addSubview(dropdownButton)

        // --- 列表
        tableView.fileDelegate = self
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 18
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.allowsEmptySelection = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        // 双击 = 进入目录 / 打开归档（Windows 版 MouseDblClick 的行为）。
        // 走 doubleAction 是 AppKit 给表格规定的通路；写在 mouseUp 上不会触发。
        tableView.target = self
        tableView.doubleAction = #selector(tableDoubleClicked)
        tableView.style = .plain
        tableView.gridStyleMask = []
        tableView.headerView = NSTableHeaderView()
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = true

        // --- 状态栏
        //
        // Windows 版的 4 个分区宽度是 {220, 320, 420, -1}，也就是前三个各占
        // 220/100/100 像素，最后一个吃掉剩下的。分区文字在 Windows 里是左对齐的
        // （SetText 传的 type 是 0），所以这里也全部左对齐。
        for label in statusParts {
            label.font = NSFont.systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            label.cell?.usesSingleLineMode = true
            label.translatesAutoresizingMaskIntoConstraints = false
        }
        let statusBar = NSView()
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        for label in statusParts { statusBar.addSubview(label) }
        let statusSeparator = NSBox()
        statusSeparator.boxType = .separator
        statusSeparator.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(statusSeparator)

        addSubview(addressBar)
        addSubview(scrollView)
        addSubview(statusBar)

        NSLayoutConstraint.activate([
            addressBar.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            addressBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            addressBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            addressBar.heightAnchor.constraint(equalToConstant: 20),

            // 顺序照 Windows 的 rebar：band 0 是「上一级」按钮，band 1 是地址框
            // （Panel.cpp 先 InsertBand 那个工具栏、再 InsertBand 组合框）。
            // 所以按钮在地址框左边，不是右边。
            upButton.leadingAnchor.constraint(equalTo: addressBar.leadingAnchor),
            upButton.centerYAnchor.constraint(equalTo: addressBar.centerYAnchor),
            upButton.widthAnchor.constraint(equalToConstant: 22),

            dropdownButton.trailingAnchor.constraint(equalTo: addressBar.trailingAnchor),
            dropdownButton.centerYAnchor.constraint(equalTo: addressBar.centerYAnchor),
            dropdownButton.widthAnchor.constraint(equalToConstant: 18),

            pathField.leadingAnchor.constraint(equalTo: upButton.trailingAnchor, constant: 2),
            pathField.trailingAnchor.constraint(equalTo: dropdownButton.leadingAnchor, constant: -2),
            pathField.centerYAnchor.constraint(equalTo: addressBar.centerYAnchor),
            pathField.heightAnchor.constraint(equalToConstant: 20),

            scrollView.topAnchor.constraint(equalTo: addressBar.bottomAnchor, constant: 3),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            scrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 18),

            statusSeparator.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor),
            statusSeparator.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor),
            statusSeparator.topAnchor.constraint(equalTo: statusBar.topAnchor),
        ])

        // 分区边界照 Windows 版的 {220, 320, 420, -1} 摆，文字各留 4px 内缩
        let edges: [CGFloat] = [0, 220, 320, 420]
        for (i, label) in statusParts.enumerated() {
            var constraints = [
                label.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
                label.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor,
                                               constant: edges[i] + 4),
            ]
            if i + 1 < edges.count {
                constraints.append(label.widthAnchor.constraint(
                    equalToConstant: edges[i + 1] - edges[i] - 8))
            } else {
                constraints.append(label.trailingAnchor.constraint(
                    lessThanOrEqualTo: statusBar.trailingAnchor, constant: -6))
            }
            NSLayoutConstraint.activate(constraints)
        }

        headerMenu.delegate = self
        tableView.headerView?.menu = headerMenu
    }

    // MARK: 列

    private var availableColumns: [ColumnSpec] {
        location.isArchive ? Columns.archive : Columns.fileSystem
    }

    func updateColumnSet() {
        let specs = availableColumns
        let ctx = columnsContext()
        let saved = Settings.shared.columns(for: ctx)
        var ids: [String] = []
        for s in specs {
            if let rec = saved[s.id], let vis = rec["visible"] as? Bool {
                if vis { ids.append(s.id) }
            } else {
                // 默认可见性：归档里默认多开 CRC / 方法 / 加密，和 Windows 版一致
                let hidden = location.isArchive
                    ? Columns.hiddenByDefaultInArchive
                    : Columns.hiddenByDefaultInFileSystem
                if !hidden.contains(s.id) { ids.append(s.id) }
            }
        }
        if !ids.contains(Columns.name) { ids.insert(Columns.name, at: 0) }

        // 去掉已经不存在的列，按 specs 顺序排列
        let order = specs.map { $0.id }
        ids = ids.filter { order.contains($0) }
        ids.sort { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
        visibleColumnIDs = ids

        for col in tableView.tableColumns.reversed() {
            tableView.removeTableColumn(col)
        }
        for id in ids {
            guard let spec = specs.first(where: { $0.id == id }) else { continue }
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = spec.title
            let rec = saved[id]
            let storedWidth = (rec?["width"] as? Int) ?? Int(defaultWidth(for: spec))
            col.width = CGFloat(storedWidth)
            col.minWidth = 30
            if id == Columns.name {
                col.resizingMask = [.userResizingMask, .autoresizingMask]
            }
            tableView.addTableColumn(col)
        }
        reloadTable()
    }

    /// 列的默认宽度：取 7-Zip 源码里的值，但不小于「放得下最宽取值」所需的宽度
    private func defaultWidth(for spec: ColumnSpec) -> CGFloat {
        let font = NSFont.systemFont(ofSize: FileCellView.fontSize)
        let sample = Columns.sampleValue(spec.id)
        guard !sample.isEmpty else { return spec.width }
        let text = (sample as NSString).size(withAttributes: [.font: font]).width
        return max(spec.width, ceil(text) + 12)
    }

    // MARK: 数据加载

    func refresh(preserveSelection: Bool = true) {
        let selectedPaths = preserveSelection ? Set(selectedEntries().map { $0.fullPath }) : []

        if location.isArchive {
            do {
                let listing = try FolderLoader.loadArchive(location.root, password: currentPassword)
                self.listing = listing
                allEntries = FolderLoader.children(of: listing, inner: location.inner)
            } catch {
                self.listing = nil
                allEntries = []
                onError?(S.cantOpenArchive.replacingOccurrences(of: "{0}", with: location.root),
                         (error as? LocalizedError)?.errorDescription ?? "\(error)")
            }
        } else {
            listing = nil
            allEntries = FolderLoader.loadFileSystem(location.root,
                                                     showHidden: Settings.shared.showHidden)
        }
        applySort()
        reloadTable()
        pathField.stringValue = location.display

        if preserveSelection, !selectedPaths.isEmpty {
            var idx = IndexSet()
            for (i, e) in entries.enumerated() where selectedPaths.contains(e.fullPath) {
                idx.insert(i)
            }
            tableView.selectRowIndexes(idx, byExtendingSelection: false)
        }
        updateStatus()
        updateUpButtonState()
        onPathChange?(self)
    }

    /// 「上一级」按钮在根目录下不可用（PanelItems.cpp:523
    /// `_headerToolBar.EnableButton(kParentFolderID, !IsRootFolder())`）。
    /// 主工具栏那 7 个按钮在 Windows 版里从来不置灰，那边没有对应的 EnableButton。
    private func updateUpButtonState() {
        upButton.isEnabled = (location.parent != nil)
    }

    private var currentPassword: String?

    func setPassword(_ pw: String?) { currentPassword = pw }
    var password: String? { currentPassword }

    private func applySort() {
        var items = allEntries
        if !searchFilter.isEmpty {
            let lower = searchFilter.lowercased()
            items = items.filter { $0.name.lowercased().contains(lower) }
        }
        if sortKey.isEmpty {
            entries = items
        } else {
            entries = Sorter.sort(items, by: sortKey, ascending: sortAscending, mode: .name)
        }

        // 「Show ".." item」打开时，列表第一行是上一级目录。
        // 只在有上一级时出现（PanelItems.cpp:578 的 !IsRootFolder），
        // 而且永远排在最前（PanelSort.cpp:183 让 kParentIndex 先比）。
        if Settings.shared.showDots, let parent = location.parent {
            var dot = FileEntry(name: "..", fullPath: parent.display,
                                isDir: true, isArchive: false)
            dot.isParent = true
            entries.insert(dot, at: 0)
        }
    }

    /// 第一行是不是那个「..」
    var hasParentRow: Bool { entries.first?.isParent ?? false }

    func reloadTable() {
        tableView.reloadData()
        updateSortIndicator()
    }

    private func updateSortIndicator() {
        for col in tableView.tableColumns {
            tableView.setIndicatorImage(nil, in: col)
        }
        guard let col = tableView.tableColumns.first(where: { $0.identifier.rawValue == sortKey }) else { return }
        let name = sortAscending ? "NSAscendingSortIndicator" : "NSDescendingSortIndicator"
        tableView.setIndicatorImage(NSImage(named: name), in: col)
        tableView.highlightedTableColumn = col
    }

    // MARK: 导航

    func navigate(to loc: Location, recordHistory: Bool = true) {
        if recordHistory {
            addToHistory(location.display)
        }
        var l = loc
        if l.root.hasPrefix("~/") { l.root = (l.root as NSString).expandingTildeInPath }
        location = l
        currentPassword = location.isArchive ? currentPassword : nil
        updateColumnSet()
        refresh(preserveSelection: false)
        tableView.scrollRowToVisible(0)
    }

    func navigate(toPath path: String) {
        guard let loc = Resolver.parseLoose(path) else {
            onError?("7-Zip", "\(S.errorPathNotFound)\n\(path)")
            pathField.stringValue = location.display
            return
        }
        navigate(to: loc)
    }

    @objc private func goUpAction() { goUp() }

    func goUp() {
        if let p = location.parent { navigate(to: p) }
    }

    @objc private func pathFieldCommitted() {
        navigate(toPath: pathField.stringValue)
    }

    // MARK: 自动化自检用（--automation）

    /// Cocoa 屏幕坐标（原点左下、y 向上）转成合成鼠标事件用的坐标（原点左上、y 向下）
    private func toEventCoords(_ r: NSRect) -> NSRect {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        let h = primary?.frame.height ?? 0
        return NSRect(x: r.origin.x, y: h - r.maxY, width: r.width, height: r.height)
    }

    func screenRect(forRow row: Int) -> NSRect {
        guard window != nil, row >= 0, row < entries.count else { return .zero }
        let r = tableView.rect(ofRow: row)
        let inWindow = tableView.convert(r, to: nil)
        return toEventCoords(window!.convertToScreen(inWindow))
    }

    func upButtonScreenRect() -> NSRect {
        guard window != nil else { return .zero }
        let r = upButton.convert(upButton.bounds, to: nil)
        return toEventCoords(window!.convertToScreen(r))
    }

    /// 触发工具栏「上一级」按钮（等价于用户点它）
    func pressUpButton() { upButton.performClick(nil) }

    // 自动化自检用：把地址栏三个控件暴露出去，好对它们做命中测试与真实点击
    var upButtonView: NSView { upButton }
    var dropdownView: NSView { dropdownButton }
    var pathFieldView: NSView { pathField }
    var upButtonEnabled: Bool { upButton.isEnabled }

    /// 在地址栏里敲一个路径并回车
    func commitPath(_ p: String) {
        pathField.stringValue = p
        pathFieldCommitted()
    }

    private func addToHistory(_ path: String) {
        var h = Settings.shared.foldersHistory
        h.removeAll { $0 == path }
        h.insert(path, at: 0)
        if h.count > 40 { h.removeLast(h.count - 40) }
        Settings.shared.foldersHistory = h
    }

    @objc private func showHistoryMenu() {
        let menu = NSMenu()
        // 当前面板自己的历史（前进/后退用不到，但保留本面板访问过的路径）
        let history = Settings.shared.foldersHistory
        for p in history {
            let item = NSMenuItem(title: p, action: #selector(goToHistoryItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = p
            if p == location.display { item.state = .on }
            menu.addItem(item)
        }
        if history.isEmpty {
            menu.addItem(withTitle: S.computer, action: nil, keyEquivalent: "")
        }
        let at = NSPoint(x: 0, y: dropdownButton.bounds.height + 2)
        menu.popUp(positioning: nil, at: at, in: dropdownButton)
    }

    @objc private func goToHistoryItem(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? String else { return }
        navigate(toPath: p)
    }

    // MARK: 选择

    /// 选中的条目。「..」那一行不算（PanelItems.cpp 里所有取选中项的地方都跳过它），
    /// 所以只选中「..」时，各项操作自然就是禁用的。
    func selectedEntries() -> [FileEntry] {
        tableView.selectedRowIndexes.compactMap { row in
            guard row < entries.count else { return nil }
            let e = entries[row]
            return e.isParent ? nil : e
        }
    }

    /// 光标停在哪一行（含「..」）
    var focusedEntry: FileEntry? {
        let row = tableView.selectedRow
        return row >= 0 && row < entries.count ? entries[row] : nil
    }

    var selectedEntry: FileEntry? { selectedEntries().first }

    /// 状态栏的 4 个分区，内容照 PanelListNotify.cpp 的 Refresh_StatusBar
    func updateStatus() {
        let selected = selectedEntries()

        // 1) "N / M object(s) selected"（N=选中数，M=本目录条目总数）
        //    M 不含「..」那一行 —— Windows 版的 _selectedStatusVector 里就没有它
        let total = entries.count - (hasParentRow ? 1 : 0)
        statusParts[0].stringValue = S.nSelectedItems
            .replacingOccurrences(of: "{0}", with: "\(selected.count) / \(total)")

        // 2) 选中项的合计大小
        if selected.isEmpty {
            statusParts[1].stringValue = ""
        } else {
            statusParts[1].stringValue = Fmt.size(selected.reduce(Int64(0)) { $0 + max($1.size, 0) })
        }

        // 3)(4) 光标所在那一条的大小与修改时间（「..」没有这些属性）
        let row = tableView.selectedRow
        if row >= 0, row < entries.count, !entries[row].isParent {
            statusParts[2].stringValue = Fmt.size(entries[row].size)
            statusParts[3].stringValue = Fmt.date(entries[row].mtime)
        } else {
            statusParts[2].stringValue = ""
            statusParts[3].stringValue = ""
        }
    }

    var statusText: String { statusParts[0].stringValue }

    // MARK: NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, row < entries.count else { return nil }
        let id = tableColumn.identifier.rawValue
        let spec = availableColumns.first { $0.id == id }
        let showIcon = (id == Columns.name)
        let reuseID = NSUserInterfaceItemIdentifier("cell." + id)

        let cell: FileCellView
        if let reused = tableView.makeView(withIdentifier: reuseID, owner: nil) as? FileCellView {
            cell = reused
        } else {
            cell = FileCellView(showIcon: showIcon, rightAligned: spec?.alignRight ?? false)
            cell.identifier = reuseID
        }

        let e = entries[row]
        if showIcon {
            cell.setIconSize(iconSide)
            cell.icon.image = Icons.icon(for: e, size: iconSide)
        }
        cell.label.stringValue = text(for: e, column: id)
        cell.label.textColor = e.isArchive ? NSColor.systemBlue : .labelColor
        return cell
    }

    private func text(for e: FileEntry, column: String) -> String {
        // 「..」那一行只有名字（Windows 版它只有图标和文字）
        if e.isParent { return column == Columns.name ? e.name : "" }
        switch column {
        case Columns.name: return e.name
        case Columns.size: return e.isDir ? "" : Fmt.size(e.size)
        case Columns.packedSize: return e.isDir ? "" : Fmt.size(e.packedSize)
        case Columns.mtime: return Fmt.date(e.mtime)
        case Columns.ctime: return Fmt.date(e.ctime)
        case Columns.atime: return Fmt.date(e.atime)
        case Columns.attributes: return e.attributes
        case Columns.crc: return e.crc
        case Columns.method: return e.method
        case Columns.encrypted: return e.encrypted
        case Columns.comment: return e.comment
        case Columns.solid: return e.solid
        case Columns.block: return e.block
        case Columns.hostOS: return e.hostOS
        case Columns.version: return e.version
        case Columns.offset: return e.offset
        default: return ""
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateStatus()
    }

    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        let id = tableColumn.identifier.rawValue
        if sortKey == id {
            sortAscending.toggle()
        } else {
            sortKey = id
            sortAscending = Sorter.defaultAscending(for: id)
        }
        applySort()
        reloadTable()
    }

    // 把文件拖到别处（Finder、另一个面板）：按住 ⌥ 拖动才会走到这里。
    // 不按 ⌥ 时拖动一律让给框选 —— 返回 nil 就是「这次不起拖放」，表格于是按
    // 普通拖动处理，也就是扩选。见 FileTableView 那段的说明。
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        // 用当前事件上的修饰键，而不是 NSEvent.modifierFlags —— 后者只反映硬件状态，
        // 自检里合成的 ⌥ 拖动就永远进不来。
        let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
        guard flags.contains(.option) else { return nil }
        guard !location.isArchive,                        // 归档里的条目不是磁盘上的文件
              row < entries.count, !entries[row].isParent else { return nil }
        let pb = NSPasteboardItem()
        pb.setString(URL(fileURLWithPath: entries[row].fullPath).absoluteString, forType: .fileURL)
        return pb
    }

    // 拖进来 -> 复制到当前目录（归档里则向归档追加）
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                   proposedRow row: Int, proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        guard info.draggingPasteboard.canReadObject(forClasses: [NSURL.self]) else { return [] }
        return .copy
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                   row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let items = info.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              !items.isEmpty else { return false }
        return table(self.tableView, acceptDrop: items)
    }

    func table(_ table: FileTableView, acceptDrop urls: [URL]) -> Bool {
        onFilesDropped?(self, urls)
        return true
    }

    var onFilesDropped: ((FilePanelView, [URL]) -> Void)?

    // MARK: 键盘

    func tableDidBecomeFirstResponder(_ table: FileTableView) {
        onFocus?(self)
    }

    func tableClickedEmptyArea(_ table: FileTableView) {
        table.deselectAll(nil)
        updateStatus()
    }

    func table(_ table: FileTableView, didDoubleClickRow row: Int) {
        guard row < entries.count else { return }
        // 双击「..」= 回到上一级（PanelItemOpen.cpp:840 对 kParentIndex 就是这么处理的）
        if entries[row].isParent { goUp(); return }
        onOpenEntry?(self, entries[row])
    }

    @objc private func tableDoubleClicked() {
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        table(tableView, didDoubleClickRow: row)
    }

    /// Windows 版的键盘习惯（F2..F9、Ctrl+PgUp/PgDn、Backspace、Alt+Enter……）
    func table(_ table: FileTableView, handleKey key: String, modifiers: NSEvent.ModifierFlags) -> Bool {
        let hasCtrl = modifiers.contains(.control)
        let hasAlt = modifiers.contains(.option)
        let hasCmd = modifiers.contains(.command)

        switch key {
        case "\u{08}", "\u{7F}":                     // Backspace
            if !hasCmd { goUp(); return true }
        case "\r", "\u{03}":                          // Enter
            if let e = focusedEntry {
                if e.isParent { goUp() } else { onOpenEntry?(self, e) }
                return true
            }
        case "\u{F705}":                              // F2：改名
            if hasAlt { perform(.properties) } else { perform(.rename) }
            return true
        case "\u{F706}": perform(.view); return true            // F3
        case "\u{F707}":                              // F4：编辑；Shift+F4：新建文件
            if modifiers.contains(.shift) { perform(.createFile) } else { perform(.edit) }
            return true
        case "\u{F708}": perform(.copyTo); return true          // F5
        case "\u{F709}": perform(.moveTo); return true          // F6
        case "\u{F70A}": perform(.createFolder); return true    // F7
        case "\u{F70C}": onToggleTwoPanels?(); return true      // F9
        case "\u{F70F}": onShowHistory?(); return true          // F12
        case "\t": onCyclePanels?(); return true
        case "\u{F72D}":                                          // Page Down
            if hasCtrl { openInside(); return true }
        case "\u{F72C}":                                          // Page Up
            if hasCtrl { goUp(); return true }
        case "\u{1B}":                                            // Esc
            table.deselectAll(nil); updateStatus(); return true
        default: break
        }

        if hasCmd {
            switch key.lowercased() {
            case "a": table.selectAll(nil); updateStatus(); return true
            case "r": refresh(); return true
            case "o": if let e = selectedEntry { onOpenEntry?(self, e); return true }
            // 菜单上的「Edit」挂的是 Windows 的 F4，Cmd+Shift+E 在面板里留着
            case "e": if modifiers.contains(.shift) { perform(.edit); return true }
            case "i": perform(.properties); return true
            case "n": perform(.createFolder); return true
            case "f": perform(.extract); return true
            default: break
            }
        }
        if hasCtrl {
            switch key {
            case "1": onSetViewMode?(0); return true
            case "2": onSetViewMode?(1); return true
            case "3": onSetViewMode?(2); return true
            case "4": onSetViewMode?(3); return true
            default: break
            }
        }
        return false
    }

    // MARK: 动作（由主窗口执行的转发出去）

    enum PanelAction {
        case open, openInside, openOutside, view, edit, rename
        case copyTo, moveTo, delete, properties, comment, diff
        case createFolder, createFile, split, combine, extract, add, test
        case smartExtract
    }

    var onAction: ((FilePanelView, PanelAction) -> Void)?
    var onToggleTwoPanels: (() -> Void)?
    var onCyclePanels: (() -> Void)?
    var onSetViewMode: ((Int) -> Void)?
    var onShowHistory: (() -> Void)?

    func perform(_ a: PanelAction) { onAction?(self, a) }

    func openInside() {
        guard let e = selectedEntry, e.isArchive else { return }
        onAction?(self, .openInside)
    }

    // MARK: 右键菜单

    func tableNeedsContextMenu(_ table: FileTableView) -> NSMenu? {
        buildContextMenu()
    }

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        let sel = selectedEntries()
        let hasSel = !sel.isEmpty
        let single = sel.count == 1
        let first = sel.first

        func add(_ title: String, _ action: PanelAction?, enabled: Bool = true, key: String = "") {
            let item = NSMenuItem(title: title, action: #selector(menuAction(_:)), keyEquivalent: key)
            item.target = self
            item.isEnabled = enabled && action != nil
            item.representedObject = action.map { NSNumber(value: actionCode($0)) }
            menu.addItem(item)
        }

        add(S.menuOpen, .open, enabled: hasSel)
        if let f = first, f.isArchive, !location.isArchive {
            add(S.menuOpenInside, .openInside, enabled: single)
        }
        add(S.menuOpenOutside, .openOutside, enabled: hasSel)
        // 和「文件」菜单同一条规则：View / Edit 只对单个文件可用。
        // 对文件夹亮着只会点了弹「请选择单个文件」，是个死点击。
        let viewable = single && !(first?.isDir ?? true)
        add(S.menuView, .view, enabled: viewable)
        add(S.menuEditItem, .edit, enabled: viewable)
        // 智能解压。列表里选中一个压缩包时才出现；已经在压缩包内部时不出现
        // （那时候「..」才是有意义的动作）。
        if !location.isArchive {
            add(S.extractSmart, .smartExtract, enabled: single && (first?.isArchive ?? false))
        }
        menu.addItem(.separator())
        add(S.menuRename, .rename, enabled: single)
        add(S.menuCopyTo, .copyTo, enabled: hasSel)
        add(S.menuMoveTo, .moveTo, enabled: hasSel)
        add(S.menuDelete, .delete, enabled: hasSel)
        menu.addItem(.separator())
        let crc = NSMenuItem(title: S.menuCRC, action: nil, keyEquivalent: "")
        let crcMenu = NSMenu()
        for (i, name) in HashKind.allCases.enumerated() {
            let it = NSMenuItem(title: name.title, action: #selector(menuCRC(_:)), keyEquivalent: "")
            it.target = self
            it.tag = i
            it.isEnabled = hasSel
            crcMenu.addItem(it)
        }
        crc.submenu = crcMenu
        menu.addItem(crc)
        add(S.menuDiff, .diff, enabled: sel.count == 2)
        menu.addItem(.separator())
        add(S.menuCreateFolder, .createFolder)
        add(S.menuCreateFile, .createFile)
        menu.addItem(.separator())
        add(S.menuProperties, .properties, enabled: hasSel)
        return menu
    }

    private func actionCode(_ a: PanelAction) -> Int {
        switch a {
        case .open: return 1
        case .openInside: return 2
        case .openOutside: return 3
        case .view: return 4
        case .edit: return 5
        case .rename: return 6
        case .copyTo: return 7
        case .moveTo: return 8
        case .delete: return 9
        case .properties: return 10
        case .comment: return 11
        case .diff: return 12
        case .createFolder: return 13
        case .createFile: return 14
        case .split: return 15
        case .combine: return 16
        case .extract: return 17
        case .add: return 18
        case .test: return 19
        case .smartExtract: return 20
        }
    }

    private func decodeAction(_ n: NSNumber?) -> PanelAction? {
        guard let n else { return nil }
        switch n.intValue {
        case 1: return .open
        case 2: return .openInside
        case 3: return .openOutside
        case 4: return .view
        case 5: return .edit
        case 6: return .rename
        case 7: return .copyTo
        case 8: return .moveTo
        case 9: return .delete
        case 10: return .properties
        case 11: return .comment
        case 12: return .diff
        case 13: return .createFolder
        case 14: return .createFile
        case 15: return .split
        case 16: return .combine
        case 17: return .extract
        case 18: return .add
        case 19: return .test
        case 20: return .smartExtract
        default: return nil
        }
    }

    @objc private func menuAction(_ sender: NSMenuItem) {
        if let a = decodeAction(sender.representedObject as? NSNumber) {
            perform(a)
        }
    }

    @objc private func menuCRC(_ sender: NSMenuItem) {
        let kinds = HashKind.allCases
        guard sender.tag >= 0, sender.tag < kinds.count else { return }
        onHashRequest?(self, kinds[sender.tag])
    }

    var onHashRequest: ((FilePanelView, HashKind) -> Void)?

    // MARK: 列右键菜单（对应 Windows 版在列头上右键选列）

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === headerMenu else { return }
        menu.removeAllItems()

        // 排序项
        let sortTitles: [(String, String)] = [
            (S.menuArrangeByName, Columns.name),
            (S.menuArrangeByType, "type"),
            (S.menuArrangeByDate, Columns.mtime),
            (S.menuArrangeBySize, Columns.size),
            (S.menuArrangeNoSort, ""),
        ]
        for (title, key) in sortTitles {
            let it = NSMenuItem(title: title, action: #selector(headerSort(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = key
            it.state = (key == sortKey || (key.isEmpty && sortKey.isEmpty)) ? .on : .off
            menu.addItem(it)
        }
        menu.addItem(.separator())

        // 列显示/隐藏
        for spec in availableColumns {
            let it = NSMenuItem(title: spec.title, action: #selector(toggleColumn(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = spec.id
            it.state = visibleColumnIDs.contains(spec.id) ? .on : .off
            if spec.id == Columns.name { it.isEnabled = false }
            menu.addItem(it)
        }
    }

    @objc private func headerSort(_ sender: NSMenuItem) {
        let key = sender.representedObject as? String ?? ""
        if key.isEmpty {
            sortKey = ""
        } else {
            if sortKey == key { sortAscending.toggle() } else {
                sortKey = key
                sortAscending = Sorter.defaultAscending(for: key)
            }
        }
        applySort()
        reloadTable()
    }

    @objc private func toggleColumn(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, id != Columns.name else { return }
        if let i = visibleColumnIDs.firstIndex(of: id) {
            visibleColumnIDs.remove(at: i)
        } else {
            let order = availableColumns.map { $0.id }
            visibleColumnIDs.append(id)
            visibleColumnIDs.sort { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
        }
        saveColumns()
        updateColumnSet()
    }

    private func columnsContext() -> String {
        location.isArchive ? "archive" : "filesystem"
    }

    func saveColumns() {
        var rec: [String: [String: Any]] = [:]
        for spec in availableColumns {
            var w = Int(spec.width)
            var visible = visibleColumnIDs.contains(spec.id)
            if let col = tableView.tableColumns.first(where: { $0.identifier.rawValue == spec.id }) {
                w = Int(col.width)
                visible = true
            }
            rec[spec.id] = ["visible": visible, "width": w]
        }
        Settings.shared.setColumns(rec, for: columnsContext())
    }

    /// 当前视图模式下的图标边长（0=大图标 1=小图标 2=列表 3=详细资料）
    private(set) var iconSide: CGFloat = 16

    /// 供 View 菜单的四种视图模式切换用
    func setViewMode(_ mode: Int) {
        settingsViewMode = mode
        tableView.headerView = (mode == 3) ? NSTableHeaderView() : nil
        tableView.rowHeight = [40, 24, 18, 18][max(0, min(3, mode))]
        iconSide = [32, 20, 16, 16][max(0, min(3, mode))]

        if mode == 3 {
            updateColumnSet()
            return
        }
        visibleColumnIDs = [Columns.name]
        for col in tableView.tableColumns.reversed() { tableView.removeTableColumn(col) }
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(Columns.name))
        col.title = (mode == 2) ? S.propName : ""
        col.width = max(tableView.bounds.width - 24, 200)
        tableView.addTableColumn(col)
        reloadTable()
    }

    private(set) var settingsViewMode = 3

    func focusTable() {
        window?.makeFirstResponder(tableView)
    }

    func setSearchFilter(_ s: String) {
        searchFilter = s
        applySort()
        reloadTable()
    }
}

// MARK: - 校验和类型（对应 File 菜单里的 CRC 子菜单）

enum HashKind: Int, CaseIterable {
    case crc32 = 0, crc64, xxh64, md5, sha1, sha256, sha384, sha512, sha3_256, blake2sp, all

    var title: String {
        switch self {
        case .crc32: return "CRC-32"
        case .crc64: return "CRC-64"
        case .xxh64: return "XXH64"
        case .md5: return "MD5"
        case .sha1: return "SHA-1"
        case .sha256: return "SHA-256"
        case .sha384: return "SHA-384"
        case .sha512: return "SHA-512"
        case .sha3_256: return "SHA3-256"
        case .blake2sp: return "BLAKE2sp"
        case .all: return "*"
        }
    }

    /// 7zz -scrc<name>
    var switchValue: String? {
        switch self {
        case .crc32: return "CRC32"
        case .crc64: return "CRC64"
        case .xxh64: return "XXH64"
        case .md5: return "MD5"
        case .sha1: return "SHA1"
        case .sha256: return "SHA256"
        case .sha384: return "SHA384"
        case .sha512: return "SHA512"
        case .sha3_256: return "SHA3-256"
        case .blake2sp: return "BLAKE2SP"
        case .all: return nil
        }
    }
}
