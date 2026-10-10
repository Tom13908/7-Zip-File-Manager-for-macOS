// 各类对话框。字段、标签、默认值都对着 Windows 版的资源脚本摆。

import AppKit

// MARK: - 表单小工具

extension Array where Element == NSView {
    /// 竖着摞起来，左对齐
    func verticalStack(spacing: CGFloat = 6) -> NSStackView {
        let s = NSStackView(views: self)
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = spacing
        return s
    }
}

final class FormBuilder {
    private(set) var rows: [(String, NSView)] = []

    @discardableResult
    func add(_ caption: String, _ view: NSView) -> NSView {
        rows.append((caption, view))
        return view
    }

    /// 生成一个两列（标签 + 控件）的表单视图。
    /// 标签左对齐 —— Windows 版的 LTEXT 就是这个对齐方式。
    func makeView(labelWidth: CGFloat = 150, rowSpacing: CGFloat = 6) -> NSView {
        let container = NSView()
        var constraints: [NSLayoutConstraint] = []
        var previous: NSView?
        for (caption, view) in rows {
            let label = NSTextField(labelWithString: caption)
            label.font = NSFont.systemFont(ofSize: 12)
            label.alignment = .left
            label.translatesAutoresizingMaskIntoConstraints = false
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)
            container.addSubview(view)
            // 控件自带宽度的（下拉框、输入框）就不该被拉满：把靠右的约束降一档，
            // 这样定宽优先，能撑开的（列表、行栈）才撑开
            let trailing = view.trailingAnchor.constraint(equalTo: container.trailingAnchor)
            trailing.priority = .defaultHigh
            constraints.append(contentsOf: [
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                label.widthAnchor.constraint(equalToConstant: labelWidth),
                label.firstBaselineAnchor.constraint(equalTo: view.firstBaselineAnchor),
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: labelWidth + 8),
                trailing,
            ])
            if let p = previous {
                constraints.append(view.topAnchor.constraint(equalTo: p.bottomAnchor, constant: rowSpacing))
            } else {
                constraints.append(view.topAnchor.constraint(equalTo: container.topAnchor))
            }
            previous = view
        }
        if let p = previous {
            constraints.append(p.bottomAnchor.constraint(equalTo: container.bottomAnchor))
        }
        NSLayoutConstraint.activate(constraints)
        return container
    }
}

enum DialogKit {

    static func combo(_ items: [String], width: CGFloat = 220) -> NSPopUpButton {
        let b = NSPopUpButton(frame: .zero, pullsDown: false)
        b.addItems(withTitles: items)
        b.widthAnchor.constraint(equalToConstant: width).isActive = true
        return b
    }

    /// 可编辑下拉框（Windows 版里"分卷大小""字典大小"这类是 CBS_DROPDOWN）
    static func editCombo(_ items: [String], width: CGFloat = 220) -> NSComboBox {
        let c = NSComboBox()
        c.font = NSFont.systemFont(ofSize: 12)
        c.addItems(withObjectValues: items)
        c.numberOfVisibleItems = 12
        c.widthAnchor.constraint(equalToConstant: width).isActive = true
        return c
    }

    static func field(_ value: String = "", width: CGFloat = 220) -> NSTextField {
        let f = NSTextField(string: value)
        f.font = NSFont.systemFont(ofSize: 12)
        f.widthAnchor.constraint(equalToConstant: width).isActive = true
        return f
    }

    static func check(_ title: String, _ on: Bool) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        b.state = on ? .on : .off
        b.font = NSFont.systemFont(ofSize: 12)
        return b
    }

    static func label(_ s: String, bold: Bool = false) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = bold ? NSFont.boldSystemFont(ofSize: 12) : NSFont.systemFont(ofSize: 12)
        return l
    }

    /// 把几个控件叠在同一格（都钉在容器的四边），同一时刻只显示其中一个。
    /// 用 NSStackView 摞的话，藏起来的那一个会让高度算不出来。
    static func overlay(_ views: [NSView]) -> NSView {
        let holder = NSView()
        var constraints: [NSLayoutConstraint] = []
        for (i, v) in views.enumerated() {
            v.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(v)
            constraints.append(contentsOf: [
                v.topAnchor.constraint(equalTo: holder.topAnchor),
                v.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            ])
            if i == 0 {
                constraints.append(v.leadingAnchor.constraint(equalTo: holder.leadingAnchor))
                constraints.append(v.trailingAnchor.constraint(equalTo: holder.trailingAnchor))
            } else {
                constraints.append(v.leadingAnchor.constraint(equalTo: holder.leadingAnchor))
                constraints.append(v.trailingAnchor.constraint(lessThanOrEqualTo: holder.trailingAnchor))
            }
        }
        NSLayoutConstraint.activate(constraints)
        return holder
    }

    /// 标签在上、控件在下的一小块（Windows 的通栏字段就是这种排法）
    static func labelAbove(_ text: String, _ field: NSView, spacing: CGFloat = 4) -> NSStackView {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12)
        let stack = NSStackView(views: [label, field])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

    /// 带标题的分组框（对应 Windows 的 GROUPBOX）。
    /// 用 NSBox 的话它的尺寸不由子视图约束决定，塞进 NSStackView 会塌成一条线，
    /// 所以这里自己画一个：浅底 + 1px 描边 + 左上角标题。
    static func groupBox(_ title: String, _ body: NSView) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.7).cgColor
        box.layer?.borderColor = NSColor.separatorColor.cgColor
        box.layer?.borderWidth = 1
        box.layer?.cornerRadius = 6

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 11)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        body.translatesAutoresizingMaskIntoConstraints = false
        // 里面这两块要是能被拉伸，分组框就会跟着被拉高（横排里尤其明显）
        titleLabel.setContentHuggingPriority(.required, for: .vertical)
        body.setContentHuggingPriority(.required, for: .vertical)
        box.addSubview(titleLabel)
        box.addSubview(body)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10),
            body.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            body.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10),
            body.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -10),
            body.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -10),
        ])
        return box
    }

    /// 并排的几栏：顶端对齐、各按自己的自然高度。
    ///
    /// 两个坑都踩过：
    ///   1. 横向 NSStackView 会把矮的那栏垂直拉到另一栏的高度，而且这个拉伸
    ///      不受 setContentHuggingPriority 控制；
    ///   2. 换成显式约束后，只要留下任何一条「容器底 = 各栏底」（哪怕低优先级）
    ///      的约束，Auto Layout 仍会把矮栏拉齐 —— 因为让两栏等高，两条约束就都满足了。
    /// 所以容器高度直接定死成最高那栏的自然高度，各栏内部就没人被撑开。
    static func columns(_ views: [NSView], widths: [CGFloat],
                        spacing: CGFloat = 20) -> NSView {
        precondition(views.count == widths.count)
        // 各自单独解一遍约束，问出「没被拉伸时该多高」。必须在塞进容器之前问，
        // 否则拿到的会是容器分给它的尺寸。
        let height = views.map { $0.fittingSize.height }.max() ?? 0

        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        var constraints: [NSLayoutConstraint] = []
        var previous: NSView?
        var total: CGFloat = 0
        for (view, width) in zip(views, widths) {
            view.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(view)
            constraints.append(view.topAnchor.constraint(equalTo: holder.topAnchor))
            constraints.append(view.widthAnchor.constraint(equalToConstant: width))
            constraints.append(holder.bottomAnchor.constraint(greaterThanOrEqualTo: view.bottomAnchor))
            if let p = previous {
                constraints.append(view.leadingAnchor.constraint(equalTo: p.trailingAnchor,
                                                                 constant: spacing))
            } else {
                constraints.append(view.leadingAnchor.constraint(equalTo: holder.leadingAnchor))
            }
            previous = view
            total += width
        }
        total += spacing * CGFloat(views.count - 1)
        constraints.append(holder.widthAnchor.constraint(equalToConstant: total))
        constraints.append(holder.heightAnchor.constraint(equalToConstant: height))
        NSLayoutConstraint.activate(constraints)
        return holder
    }

    /// 模态表单窗口
    struct Form {
        let window: NSWindow
        let ok: NSButton
        let cancel: NSButton
        /// 表单里那些需要活过函数返回的辅助对象（target/action 的持有者）
        var retained: [AnyObject] = []
    }

    static func makeSheet(title: String, content: NSView, okTitle: String = S.ok,
                          width: CGFloat, extraButtons: [NSButton] = []) -> Form {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 400),
                         styleMask: [.titled], backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false

        let root = w.contentView!
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(content)

        let ok = NSButton(title: okTitle, target: nil, action: nil)
        ok.bezelStyle = .rounded
        ok.keyEquivalent = "\r"
        let cancel = NSButton(title: S.cancel, target: nil, action: nil)
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"

        var buttonViews: [NSView] = [NSView()]
        buttonViews.append(contentsOf: extraButtons)
        buttonViews.append(contentsOf: [cancel, ok])
        let buttons = NSStackView(views: buttonViews)
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(buttons)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),

            buttons.topAnchor.constraint(equalTo: content.bottomAnchor, constant: 18),
            buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
        ])
        return Form(window: w, ok: ok, cancel: cancel)
    }

    /// 一个 target/action 收集器：把闭包挂到 NSControl 上，同时负责持有它
    final class Action: NSObject {
        private let body: (Any) -> Void
        init(_ body: @escaping (Any) -> Void) { self.body = body }
        @objc func fire(_ sender: Any) { body(sender) }

        /// 挂到控件并把持有关系交给 form（避免 target 被提前释放）
        static func attach(_ control: NSControl, form: inout Form, _ body: @escaping (Any) -> Void) {
            let a = Action(body)
            control.target = a
            control.action = #selector(Action.fire(_:))
            form.retained.append(a)
        }
    }

    /// 以模态方式跑一个表单，返回是否点了 OK
    static func runModal(_ form: Form, parent: NSWindow?) -> Bool {
        var f = form
        f.window.layoutIfNeeded()
        f.window.setContentSize(f.window.contentView!.fittingSize)
        retainedForms.append(f)

        final class Handler: NSObject {
            var done: ((Bool) -> Void)?
            @objc func ok(_ s: Any) { done?(true) }
            @objc func cancel(_ s: Any) { done?(false) }
        }
        let h = Handler()
        f.ok.target = h
        f.ok.action = #selector(Handler.ok(_:))
        f.cancel.target = h
        f.cancel.action = #selector(Handler.cancel(_:))

        var result = false
        h.done = { r in result = r; NSApp.stopModal() }

        f.window.center()
        NSApp.activate(ignoringOtherApps: true)
        f.window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: f.window)
        f.window.orderOut(nil)
        _ = parent
        return result
    }

    private static var retainedForms: [Form] = []

    static func alert(_ message: String, _ informative: String = "", style: NSAlert.Style = .warning,
                      parent: NSWindow?) {
        let a = NSAlert()
        a.messageText = message
        if !informative.isEmpty { a.informativeText = informative }
        a.alertStyle = style
        a.addButton(withTitle: S.ok)
        a.runModal()
        _ = parent
    }

    /// 是否确认（true = 用户点了第一个按钮）
    static func confirm(_ message: String, _ informative: String = "",
                        parent: NSWindow?, yes: String = S.yes, no: String = S.no) -> Bool {
        let a = NSAlert()
        a.messageText = message
        if !informative.isEmpty { a.informativeText = informative }
        a.alertStyle = .warning
        a.addButton(withTitle: yes)
        a.addButton(withTitle: no)
        return a.runModal() == .alertFirstButtonReturn
    }

    /// 多选一。返回按下的是第几个（0 起）；取消或者关了窗口返回 nil。
    /// 最后一个按钮固定是「取消」，调用方只需要给正面的那几个。
    static func choose(_ message: String, _ informative: String = "",
                       buttons: [String], parent: NSWindow?) -> Int? {
        guard !buttons.isEmpty else { return nil }
        let a = NSAlert()
        a.messageText = message
        if !informative.isEmpty { a.informativeText = informative }
        a.alertStyle = .warning
        for b in buttons { a.addButton(withTitle: b) }
        a.addButton(withTitle: S.cancel)
        let r = a.runModal()
        let i = r.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        return (i >= 0 && i < buttons.count) ? i : nil
    }

    /// 单行文本输入（对应 Windows 版的 ComboDialog / 新建文件夹）
    static func prompt(_ title: String, caption: String, initial: String,
                       parent: NSWindow?) -> String? {
        let f = DialogKit.field(initial, width: 260)
        let fb = FormBuilder()
        fb.add(caption, f)
        let form = makeSheet(title: title, content: fb.makeView(labelWidth: 90), width: 400)
        guard runModal(form, parent: parent) else { return nil }
        let v = f.stringValue
        return v.isEmpty ? nil : v
    }
}

// MARK: - 解压前的同名冲突

/// 解压前问一次覆盖策略。
///
/// 原来「解压到当前文件夹」「智能解压」这类操作是闷头用 `-aoa` 覆盖的，用户不会知道
/// 有东西被替掉了。现在先列一遍包里顶层要落地的名字，撞上已有的就弹窗问一次。
enum OverwritePrompt {

    /// 有冲突就问；没冲突直接返回 `.overwrite`（引擎按老样子做，不会有提示）。
    /// 用户在弹窗里点了取消返回 nil，调用方应当中止这次操作。
    static func resolve(conflicts: [String], destination: String,
                        parent: NSWindow?) -> ExtractOverwriteMode? {
        guard !conflicts.isEmpty else { return .overwrite }
        let listed = conflicts.prefix(10).joined(separator: "\n")
        let more = conflicts.count > 10 ? "\n…" : ""
        let info = destination + "\n\n" + listed + more
        guard let i = DialogKit.choose(S.conflictMessage, info,
                                       buttons: [S.overwrite, S.skip, S.rename],
                                       parent: parent) else { return nil }
        return [ExtractOverwriteMode.overwrite, .skip, .rename][i]
    }
}

// MARK: - 解压对话框（GUI/ExtractDialog.rc）

final class ExtractDialog {

    static func run(archive: String, baseDir: String, parent: NSWindow?) -> ExtractOptions? {
        let defaultDir = (baseDir as NSString).appendingPathComponent("")

        let pathCombo = NSComboBox()
        pathCombo.font = NSFont.systemFont(ofSize: 12)
        pathCombo.addItems(withObjectValues: [defaultDir, Settings.shared.lastExtractPath ?? ""].filter { !$0.isEmpty })
        pathCombo.stringValue = defaultDir
        pathCombo.widthAnchor.constraint(equalToConstant: 300).isActive = true

        let browse = NSButton(title: "...", target: nil, action: nil)
        browse.bezelStyle = .rounded
        browse.widthAnchor.constraint(equalToConstant: 32).isActive = true

        let pathRow = NSStackView(views: [pathCombo, browse])
        pathRow.orientation = .horizontal
        pathRow.spacing = 6

        let zipName = ((archive as NSString).lastPathComponent as NSString).deletingPathExtension
        let nameEnable = DialogKit.check("", true)
        nameEnable.toolTip = "解压到以这个名字新建的子文件夹"
        let nameField = DialogKit.field(zipName, width: 206)
        let nameRow = NSStackView(views: [nameEnable, nameField])
        nameRow.orientation = .horizontal
        nameRow.alignment = .centerY
        nameRow.spacing = 6

        let pathMode = DialogKit.combo(ExtractPathMode.allCases.map { $0.title }, width: 220)
        pathMode.selectItem(at: 0)

        let elimDup = DialogKit.check(S.extractElimDup, false)

        let overwrite = DialogKit.combo(ExtractOverwriteMode.allCases.map { $0.title }, width: 220)
        overwrite.selectItem(at: 0)

        let password = NSSecureTextField(string: "")
        password.font = NSFont.systemFont(ofSize: 12)
        password.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let showPw = DialogKit.check(S.extractShowPassword, false)
        let plainPw = DialogKit.field("", width: 220)
        plainPw.isHidden = true

        // 密码框和明文框叠在同一格，勾 Show Password 时互换
        let pwStack = DialogKit.overlay([password, plainPw])

        // Windows 版的 Extract 对话框分两栏：左边是路径与三个模式，
        // 右边是「Password」分组框（ExtractDialog.rc 的 g1xs / g2x）
        let left = NSStackView(views: [
            nameRow,
            DialogKit.labelAbove(S.extractPathMode, pathMode),
            elimDup,
            DialogKit.labelAbove(S.extractOverwriteMode, overwrite),
        ])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 10
        left.widthAnchor.constraint(equalToConstant: 240).isActive = true

        // ExtractDialog.rc：左栏 g1xs = 160、两栏间距 gSpace = 20，右栏是定高的
        // Password 分组框（GROUP_Y_SIZE = 56）。左栏最后一个组合框在框底之下，
        // 右栏保持自己的自然高度，不被左栏拉高。
        let pwBox = DialogKit.groupBox(S.extractPassword, [pwStack, showPw].verticalStack(spacing: 8))

        let columns = DialogKit.columns([left, pwBox], widths: [240, 260], spacing: 30)

        // 「Extract to」那一行通栏，在分栏之上
        let content = NSStackView(views: [DialogKit.labelAbove(S.extractExtractTo, pathRow), columns])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.widthAnchor.constraint(equalToConstant: 530).isActive = true

        var form = DialogKit.makeSheet(title: S.extractTitle, content: content, width: 566)

        DialogKit.Action.attach(browse, form: &form) { _ in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.directoryURL = URL(fileURLWithPath: pathCombo.stringValue)
            if panel.runModal() == .OK, let u = panel.url {
                pathCombo.stringValue = u.path
                nameEnable.state = .off
            }
        }

        DialogKit.Action.attach(showPw, form: &form) { sender in
            let on = (sender as? NSButton)?.state == .on
            if on {
                plainPw.stringValue = password.stringValue
                password.isHidden = true; plainPw.isHidden = false
            } else {
                password.stringValue = plainPw.stringValue
                password.isHidden = false; plainPw.isHidden = true
            }
        }

        guard DialogKit.runModal(form, parent: parent) else { return nil }

        var o = ExtractOptions()
        var dest = pathCombo.stringValue
        if nameEnable.state == .on, !nameField.stringValue.isEmpty {
            dest = (dest as NSString).appendingPathComponent(nameField.stringValue)
        }
        o.destination = dest
        o.pathMode = ExtractPathMode(rawValue: pathMode.indexOfSelectedItem) ?? .full
        o.overwrite = ExtractOverwriteMode(rawValue: overwrite.indexOfSelectedItem) ?? .ask
        o.eliminateDuplicate = elimDup.state == .on
        o.password = showPw.state == .on ? plainPw.stringValue : password.stringValue
        Settings.shared.lastExtractPath = pathCombo.stringValue
        return o
    }
}

// Add to Archive 对话框在 AddDialog.swift

// MARK: - 属性窗口（File -> Properties）

final class PropertiesWindow {

    static func show(entries: [FileEntry], panelLocation: Location, listing: ArchiveListing?,
                     password: String?, parent: NSWindow?) {
        guard let first = entries.first else { return }

        var text = ""
        if entries.count == 1, !panelLocation.isArchive {
            let st = Fmt.statPath(first.fullPath)
            text += "\(S.propPath) = \(first.fullPath)\n"
            text += "\(S.propName) = \(first.name)\n"
            text += "\(S.propType) = \(first.isDir ? "Folder" : "File")\n"
            text += "\(S.propSize) = \(Fmt.size(first.size))\n"
            text += "\(S.propPackedSize) = \(Fmt.size(0))\n"
            text += "\(S.propAttributes) = \(first.attributes)\n"
            text += "\(S.propMTime) = \(Fmt.date(first.mtime))\n"
            text += "\(S.propCTime) = \(Fmt.date(first.ctime))\n"
            text += "\(S.propATime) = \(Fmt.date(first.atime))\n"
            if let st {
                text += "\(S.propINode) = \(st.st_ino)\n"
                text += "\(S.propLinks) = \(st.st_nlink)\n"
                text += "\(S.propMode) = \(String(st.st_mode & 0o7777, radix: 8))\n"
                text += "\(S.propUser) = \(Fmt.userName(st.st_uid))\n"
                text += "\(S.propGroup) = \(Fmt.groupName(st.st_gid))\n"
                text += "\(S.propDevice) = \(st.st_uid)/\(st.st_gid)\n"
            }
        } else if entries.count == 1 {
            text += "\(S.propPath) = \(first.fullPath)\n"
            text += "\(S.propName) = \(first.name)\n"
            text += "\(S.propFolder) = \(first.isDir ? "+" : "-")\n"
            text += "\(S.propSize) = \(Fmt.size(first.size))\n"
            text += "\(S.propPackedSize) = \(Fmt.size(first.packedSize))\n"
            text += "\(S.propAttributes) = \(first.attributes)\n"
            text += "\(S.propMTime) = \(Fmt.date(first.mtime))\n"
            text += "\(S.propCTime) = \(Fmt.date(first.ctime))\n"
            text += "\(S.propATime) = \(Fmt.date(first.atime))\n"
            text += "\(S.propCRC) = \(first.crc)\n"
            text += "\(S.propEncrypted) = \(first.encrypted)\n"
            text += "\(S.propMethod) = \(first.method)\n"
            text += "\(S.propBlock) = \(first.block)\n"
            text += "\(S.propComment) = \(first.comment)\n"
            text += "\(S.propHostOS) = \(first.hostOS)\n"
            text += "\(S.propVersion) = \(first.version)\n"
            text += "\(S.propOffset) = \(first.offset)\n"
        } else {
            var total: Int64 = 0
            var packed: Int64 = 0
            for e in entries { total += e.size; packed += max(e.packedSize, 0) }
            text += "\(S.propName) = \(entries.count) object(s)\n"
            text += "\(S.propSize) = \(Fmt.size(total))\n"
            text += "\(S.propPackedSize) = \(Fmt.size(packed))\n"
        }

        // 归档本身的信息
        if let listing, panelLocation.inner.isEmpty {
            text += "\n----------\n"
            for (k, v) in listing.info {
                text += "\(k) = \(v)\n"
            }
        }
        _ = password

        let title = entries.count == 1 ? "\(S.propertiesTitle): \(first.name)" : S.propertiesTitle
        TextWindow.show(title: title, text: text, width: 640, height: 460)
        _ = parent
    }
}

// MARK: - 关于对话框（FileManager/AboutDialog.rc）

final class AboutDialog {

    static func show(parent: NSWindow?) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = S.menuAbout

        let logo = NSImageView()
        logo.image = Icons.logo
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.widthAnchor.constraint(equalToConstant: 220).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 126).isActive = true

        let title = DialogKit.label(S.aboutTitle.replacingOccurrences(of: "{0}", with: Engine.version),
                                    bold: true)
        title.font = NSFont.boldSystemFont(ofSize: 14)

        let engine = DialogKit.label(S.aboutEngine.replacingOccurrences(of: "{0}", with: Engine.version))
        let copyright = DialogKit.label(S.aboutCopyright)
        let license = DialogKit.label(S.aboutWarranty)
        let gpl = DialogKit.label(S.aboutLicense)
        let home = NSButton(title: "www.7-zip.org", target: nil, action: nil)
        home.bezelStyle = .inline
        home.isBordered = false
        home.contentTintColor = .linkColor
        final class Open: NSObject {
            @objc func go(_ s: Any) { NSWorkspace.shared.open(URL(string: "https://www.7-zip.org/")!) }
        }
        let o = Open()
        home.target = o
        home.action = #selector(Open.go(_:))
        objc_setAssociatedObject(w, "openlink", o, .OBJC_ASSOCIATION_RETAIN)

        let stack = NSStackView(views: [logo, title, engine, copyright, license, gpl, home])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        w.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: w.contentView!.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: w.contentView!.centerYAnchor),
        ])

        let wc = NSWindowController(window: w)
        AboutDialog.retained = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        _ = parent
    }

    private static var retained: NSWindowController?
}

// MARK: - 选项对话框（Tools -> Options）

final class OptionsDialog {

    static func run(parent: NSWindow?) {
        let s = Settings.shared
        let twoPanels = DialogKit.check(S.menuTwoPanels, s.numPanels == 2)
        let archiveTb = DialogKit.check(S.menuArchiveToolbar, s.showArchiveToolbar)
        let standardTb = DialogKit.check(S.menuStandardToolbar, s.showStandardToolbar)
        let largeButtons = DialogKit.check(S.menuLargeButtons, s.largeButtons)
        let buttonsText = DialogKit.check(S.menuShowButtonsText, s.showButtonsText)
        let autoRefresh = DialogKit.check(S.menuAutoRefresh, s.autoRefresh)
        let showDots = DialogKit.check(S.optionsShowDots, s.showDots)
        let showHidden = DialogKit.check(S.optionsShowHidden, s.showHidden)

        // 窗口尺寸取内容的 fittingSize，而表单容器的宽度实际是被几个下拉框的定宽
        // 撑出来的（158 + 300），比这更宽的控件会被窗口右边缘切掉。所以这一组
        // 都按同一个宽度摆：下拉 300，主路径那一格 280。
        let viewCombo = DialogKit.combo([S.menuLargeIcons, S.menuSmallIcons, S.menuList, S.menuDetails], width: 260)
        viewCombo.selectItem(at: min(max(s.viewMode, 0), 3))

        // 启动位置：上次打开的目录 / 主路径
        let startupCombo = DialogKit.combo([S.optionsStartupLast, S.optionsStartupHome], width: 300)
        startupCombo.selectItem(at: s.startupPath == .home ? 1 : 0)

        // 主路径：框里直接填实际会用的值，用户看到的就是结果
        let homeField = DialogKit.field(s.effectiveHomePath, width: 200)
        let homeButton = NSButton(title: S.optionsChoose, target: nil, action: nil)
        homeButton.bezelStyle = .rounded
        let homeRow = NSStackView(views: [homeField, homeButton])
        homeRow.orientation = .horizontal
        homeRow.spacing = 6
        homeRow.widthAnchor.constraint(equalToConstant: 280).isActive = true

        let fb = FormBuilder()
        fb.add(S.menuTwoPanels, twoPanels)
        fb.add(S.menuArchiveToolbar, archiveTb)
        fb.add(S.menuStandardToolbar, standardTb)
        fb.add(S.menuLargeButtons, largeButtons)
        fb.add(S.menuShowButtonsText, buttonsText)
        fb.add(S.menuAutoRefresh, autoRefresh)
        fb.add(S.optionsShowDots, showDots)
        fb.add(S.optionsShowHidden, showHidden)
        fb.add(S.menuViewMenu, viewCombo)
        fb.add(S.optionsStartupLabel, startupCombo)
        fb.add(S.optionsHomeLabel, homeRow)

        // 表单宽度写死。窗口尺寸取的是内容的 fittingSize，而表单里几行控件的宽度
        // 互相牵制（靠右那条约束只是 defaultHigh），算出来的值会比最宽的一行还窄，
        // 于是右边缘的「选择…」被窗口切掉。定死最省事，也省得以后加一栏又要调。
        let formContent = fb.makeView(labelWidth: 150)
        formContent.widthAnchor.constraint(equalToConstant: 474).isActive = true
        var form = DialogKit.makeSheet(title: S.optionsTitle,
                                       content: formContent,
                                       width: 540)

        DialogKit.Action.attach(homeButton, form: &form) { _ in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.directoryURL = URL(fileURLWithPath: homeField.stringValue)
            if panel.runModal() == .OK, let u = panel.url {
                homeField.stringValue = u.path
            }
        }

        guard DialogKit.runModal(form, parent: parent) else { return }

        s.numPanels = twoPanels.state == .on ? 2 : 1
        s.showArchiveToolbar = archiveTb.state == .on
        s.showStandardToolbar = standardTb.state == .on
        s.largeButtons = largeButtons.state == .on
        s.showButtonsText = buttonsText.state == .on
        s.autoRefresh = autoRefresh.state == .on
        s.showDots = showDots.state == .on
        s.showHidden = showHidden.state == .on
        s.viewMode = viewCombo.indexOfSelectedItem
        s.startupPath = startupCombo.indexOfSelectedItem == 1 ? .home : .last

        // 主路径填成用户主目录就等于没填（存空串）—— 以后换了用户名也不会留下一条死路径
        var home = homeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if home.isEmpty { home = NSHomeDirectory() }
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: home, isDirectory: &isDir) || !isDir.boolValue {
            DialogKit.alert(S.optionsHomeMissing, home, style: .warning, parent: parent)
            home = NSHomeDirectory()
        }
        s.homePath = (home == NSHomeDirectory()) ? "" : home

        NotificationCenter.default.post(name: .sevenZipSettingsChanged, object: nil)
    }
}

// MARK: - 拆分文件对话框（FileManager/SplitDialog.rc）

final class SplitDialog {
    static func run(file: String, size: Int64, parent: NSWindow?) -> Int64? {
        let sizeField = DialogKit.field("\(size)", width: 200)
        let fb = FormBuilder()
        fb.add(S.splitVolumeSize, sizeField)
        let form = DialogKit.makeSheet(title: S.splitTitle, content: fb.makeView(labelWidth: 140),
                                       width: 420)
        guard DialogKit.runModal(form, parent: parent) else { return nil }
        let v = sizeField.stringValue.replacingOccurrences(of: " ", with: "")
        return Int64(v)
    }
}

// MARK: - 按掩码选择（Edit -> Select...）

final class MaskDialog {
    static func run(title: String, parent: NSWindow?) -> String? {
        let field = DialogKit.field("*", width: 220)
        let fb = FormBuilder()
        fb.add(S.selectMask, field)
        let form = DialogKit.makeSheet(title: title, content: fb.makeView(labelWidth: 60), width: 340)
        guard DialogKit.runModal(form, parent: parent) else { return nil }
        return field.stringValue
    }
}

// MARK: - 文件夹历史

final class FoldersHistoryDialog {

    private final class Source: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        let items: [String]
        init(items: [String]) { self.items = items }
        func numberOfRows(in tableView: NSTableView) -> Int { items.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let cell = NSTextField(labelWithString: items[row])
            cell.font = NSFont.systemFont(ofSize: 12)
            cell.lineBreakMode = .byTruncatingMiddle
            return cell
        }
    }

    static func run(parent: NSWindow?, onPick: @escaping (String) -> Void) {
        let items = Settings.shared.foldersHistory
        let list = NSTableView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        col.width = 430
        list.addTableColumn(col)
        list.headerView = nil
        list.rowHeight = 18

        let source = Source(items: items)
        list.dataSource = source
        list.delegate = source

        let scroll = NSScrollView()
        scroll.documentView = list
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 260).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 440).isActive = true

        var form = DialogKit.makeSheet(title: S.foldersHistory, content: scroll, width: 520)
        DialogKit.Action.attach(list, form: &form) { _ in }

        guard DialogKit.runModal(form, parent: parent) else { return }
        let row = list.selectedRow
        if row >= 0, row < items.count { onPick(items[row]) }
    }
}

extension Notification.Name {
    static let sevenZipSettingsChanged = Notification.Name("SevenZipSettingsChanged")
}

// MARK: - 属性

/// Windows 版对文件系统条目调的是系统属性页（SHObjectProperties），macOS 没有对等
/// 的公开 API，所以这里照 7-Zip 自己给归档条目画的那套字段做，两边都能用。
enum PropertiesDialog {

    static func run(entry: FileEntry, location: Location, parent: NSWindow?) {
        let fb = FormBuilder()

        func ro(_ s: String) -> NSTextField {
            let f = DialogKit.label(s)
            f.isSelectable = true
            f.lineBreakMode = .byTruncatingMiddle
            f.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            return f
        }

        // 归档里给的是内部路径，文件系统里给的是真实路径
        let shownPath: String
        if location.isArchive {
            shownPath = location.root + "/" + entry.fullPath
        } else {
            shownPath = entry.fullPath
        }

        fb.add(S.propPath, ro(shownPath))
        fb.add(S.propName, ro(entry.name))
        if !entry.isDir {
            fb.add(S.propExtension, ro(entry.fileExtension))
        }
        fb.add(S.propType, ro(typeName(entry)))

        let sizeField = ro(entry.isDir ? S.propFolder : Fmt.size(entry.size))
        fb.add(S.propSize, sizeField)

        if entry.packedSize >= 0 {
            fb.add(S.propPackedSize, ro(Fmt.size(entry.packedSize)))
        }
        if !entry.crc.isEmpty { fb.add(S.propCRC, ro(entry.crc)) }
        if !entry.method.isEmpty { fb.add(S.propMethod, ro(entry.method)) }
        if !entry.encrypted.isEmpty { fb.add(S.propEncrypted, ro(entry.encrypted)) }
        if !entry.solid.isEmpty { fb.add(S.propSolid, ro(entry.solid)) }
        if !entry.block.isEmpty { fb.add(S.propBlock, ro(entry.block)) }
        if !entry.hostOS.isEmpty { fb.add(S.propHostOS, ro(entry.hostOS)) }
        if !entry.version.isEmpty { fb.add(S.propVersion, ro(entry.version)) }
        if !entry.offset.isEmpty { fb.add(S.propOffset, ro(entry.offset)) }
        if !entry.comment.isEmpty { fb.add(S.propComment, ro(entry.comment)) }

        if !entry.attributes.isEmpty { fb.add(S.propAttributes, ro(entry.attributes)) }
        if entry.mtime != nil { fb.add(S.propMTime, ro(Fmt.date(entry.mtime))) }
        if entry.ctime != nil { fb.add(S.propCTime, ro(Fmt.date(entry.ctime))) }
        if entry.atime != nil { fb.add(S.propATime, ro(Fmt.date(entry.atime))) }

        let form = DialogKit.makeSheet(title: S.propertiesTitle,
                                       content: fb.makeView(labelWidth: 130),
                                       okTitle: S.ok, width: 600)
        DialogKit.runModal(form, parent: parent)

        // 目录的大小要递归算，别拿它卡住对话框
        if entry.isDir && !location.isArchive {
            let path = entry.fullPath
            DispatchQueue.global(qos: .utility).async {
                let total = Operations.sizeOfItem(at: path)
                DispatchQueue.main.async { sizeField.stringValue = Fmt.size(total) }
            }
        }
    }

    private static func typeName(_ e: FileEntry) -> String {
        if e.isDir { return S.propFolder }
        let ext = e.fileExtension.uppercased()
        if ArchiveTypes.isArchiveExtension(e.fileExtension) {
            return ext + " " + S.propWordArchive
        }
        return ext.isEmpty ? S.propWordFile : ext + " " + S.propWordFile
    }
}
