// 自动化自检：带 --automation 启动时，从 stdin 读一行命令，往 stdout 写一行结果。
//
// 只为开发期验证「鼠标点下去到底有没有反应」这类事服务 —— 单看代码看不出来，
// 得真的合成一次事件。正常启动完全不加载这段逻辑。
//
// 命令：
//   state            当前路径 / 行数 / 选中的行 / 前几行名字
//   names            所有行的名字
//   rowrect <i>      第 i 行中心点的屏幕坐标（转成合成事件用的坐标系）
//   click <目标>     在进程内合成点击：click row <行> [次数] / click up|dropdown|pathfield
//   drag <起点> <终> 在列表里合成一次按住拖动：drag row <行> <行> / drag empty <行>
//   drop <路径>…     按「这些文件被拖进窗口」处理一遍（调的就是拖放入口）
//   uprect           工具栏「上一级」按钮中心点的屏幕坐标
//   setdots <0|1>    改「Show ".." item」并刷新
//   sethidden <0|1>  改「显示隐藏项」并刷新
//   lang             当前界面语言，以及每一条文案实际查出来的结果
//   quit             退出
//
// 两种通信方式：
//   --automation          走 stdin/stdout（进程就是自己起的，随手可用）
//   --automation-io <dir> 走目录里的 cmd / out 文件（配合 `open --args` 启动，
//                         只有这样才能真正拿到前台会话，鼠标事件才会送到窗口上）

import AppKit

enum Automation {

    private static var buffer = ""
    private static var timer: Timer?
    private static var ioDir = ""
    private static var seq = 0

    static func start() {
        if let dir = LaunchArgs.automationIO {
            startFileMode(dir)
            return
        }
        FileHandle.standardInput.readabilityHandler = { h in
            let data = h.availableData
            if data.isEmpty { h.readabilityHandler = nil; return }
            guard let s = String(data: data, encoding: .utf8) else { return }
            buffer += s
            while let r = buffer.range(of: "\n") {
                let line = String(buffer[buffer.startIndex..<r.lowerBound])
                buffer = String(buffer[r.upperBound...])
                if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    DispatchQueue.main.async { handle(line) }
                }
            }
        }
        say("ready pid=\(getpid())")
    }

    /// 按空格切参数，但引号里的空格算数 —— 路径带空格是常态
    /// （Downloads 里随手一个文件就可能叫 "Urbz, The - Sims in the City (USA).nds"）。
    private static func splitArgs(_ line: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var quoted = false
        for ch in line {
            if ch == "\"" {
                quoted.toggle()
            } else if ch == " ", !quoted {
                if !cur.isEmpty { out.append(cur); cur = "" }
            } else {
                cur.append(ch)
            }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    private static func say(_ s: String) {
        if ioDir.isEmpty {
            FileHandle.standardOutput.write((s + "\n").data(using: .utf8)!)
            return
        }
        seq += 1
        let text = "\(seq) \(s)\n"
        let out = (ioDir as NSString).appendingPathComponent("out")
        let tmp = (ioDir as NSString).appendingPathComponent("out.tmp")
        try? text.data(using: .utf8)?.write(to: URL(fileURLWithPath: tmp))
        try? FileManager.default.removeItem(atPath: out)
        try? FileManager.default.moveItem(atPath: tmp, toPath: out)
    }

    // MARK: 文件模式

    private static func startFileMode(_ dir: String) {
        ioDir = dir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let cmd = (dir as NSString).appendingPathComponent("cmd")
        try? FileManager.default.removeItem(atPath: cmd)
        say("ready pid=\(getpid())")
        let t = Timer(timeInterval: 0.05, repeats: true) { _ in poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private static func poll() {
        let cmd = (ioDir as NSString).appendingPathComponent("cmd")
        guard let data = FileManager.default.contents(atPath: cmd),
              let s = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return }
        try? FileManager.default.removeItem(atPath: cmd)
        handle(s)
    }

    /// 主窗口控制器。从窗口的 delegate 上取，不用为此改动 MainWindow。
    private static var controller: MainWindowController? {
        for w in NSApp.windows {
            if let c = w.delegate as? MainWindowController { return c }
        }
        return nil
    }

    /// 合成鼠标事件之前，先把窗口摆成「真实点击发生时」的状态：窗口是 key、App 在前台。
    /// 从 shell 起的进程两样都不是，而系统会直接丢掉非前台窗口的鼠标事件（键盘事件不受影响）。
    /// 激活是异步的、还可能被别的 App 抢回去，所以要重试几次而不是看一眼。
    private static func armWindow(_ wc: MainWindowController) -> (NSWindow?, Int) {
        var lost = 0
        for _ in 0..<20 {
            if NSApp.isActive, let w = wc.window, w.isKeyWindow { return (w, lost) }
            lost += 1
            NSApp.activate(ignoringOtherApps: true)
            wc.window?.makeKeyAndOrderFront(nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            if let w = wc.window, w.isKeyWindow, NSApp.isActive { return (w, lost) }
        }
        return (nil, lost)
    }

    /// 投递之后不能立刻返回：事件还在队列里等 run loop 派发，这期间 App 一旦掉出前台，
    /// 鼠标事件就被系统丢掉 —— 表现是命令回了 ok，而界面上什么都没发生。
    /// 真实点击不存在这个窗口（手指按下去的时候窗口本来就是前台的）。
    /// ZIPFM_CLICK_HOLD=0 可以把这段关掉，用来对照验证这个判断。
    /// 返回（派发期间在前台的次数，掉出去的次数）。
    private static func holdForeground(_ win: NSWindow) -> (Int, Int) {
        let hold = ProcessInfo.processInfo.environment["ZIPFM_CLICK_HOLD"]
            .flatMap(Double.init) ?? 0.7
        var observed = 0
        var lost = 0
        let until = Date().addingTimeInterval(hold)
        while Date() < until {
            if NSApp.isActive && win.isKeyWindow { observed += 1 } else { lost += 1 }
            if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
            if !win.isKeyWindow { win.makeKeyAndOrderFront(nil) }
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
        return (observed, lost)
    }

    private static func handle(_ line: String) {
        let parts = splitArgs(line)
        guard let cmd = parts.first else { return }
        guard let wc = controller, let panel = Optional(wc.activePanel) else {
            say("err no-window")
            return
        }

        switch cmd {
        case "state":
            let sel = panel.tableView.selectedRowIndexes.map(String.init).joined(separator: ",")
            let first = panel.entries.prefix(5).map { $0.name }.joined(separator: "|")
            say("path=\(panel.location.display) rows=\(panel.entries.count) sel=[\(sel)]"
                + " active=\(NSApp.isActive ? 1 : 0)"
                + " key=\((wc.window?.isKeyWindow ?? false) ? 1 : 0) first=\(first)")

        case "names":
            say(panel.entries.map { $0.name }.joined(separator: "|"))

        case "rowrect":
            guard let i = parts.dropFirst().first.flatMap(Int.init) else { say("err arg"); return }
            panel.tableView.scrollRowToVisible(i)
            let r = panel.screenRect(forRow: i)
            say(String(format: "x=%.1f y=%.1f w=%.1f h=%.1f", r.midX, r.midY, r.width, r.height))

        case "uprect":
            let r = panel.upButtonScreenRect()
            say(String(format: "x=%.1f y=%.1f w=%.1f h=%.1f enabled=%d",
                       r.midX, r.midY, r.width, r.height, panel.upButtonEnabled ? 1 : 0))

        case "cd":
            guard parts.count >= 2 else { say("err arg"); return }
            panel.navigate(toPath: parts[1])
            say("ok path=\(panel.location.display)")

        // 地址栏里敲路径后回车
        case "commit":
            guard parts.count >= 2 else { say("err arg"); return }
            panel.commitPath(parts[1])
            say("ok path=\(panel.location.display)")

        // 右键菜单的内容与可用性
        case "ctxmenu":
            guard let m = panel.tableNeedsContextMenu(panel.tableView) else {
                say("err nomenu"); return
            }
            let items = m.items.map { it -> String in
                it.isSeparatorItem ? "-" : "\(it.title)(\(it.isEnabled ? "on" : "off"))"
            }
            say(items.joined(separator: ","))

        case "setdots":
            guard let v = parts.dropFirst().first.flatMap(Int.init) else { say("err arg"); return }
            Settings.shared.showDots = (v != 0)
            panel.refresh()
            say("ok dots=\(Settings.shared.showDots)")

        case "sethidden":
            guard let v = parts.dropFirst().first.flatMap(Int.init) else { say("err arg"); return }
            Settings.shared.showHidden = (v != 0)
            panel.refresh()
            say("ok hidden=\(Settings.shared.showHidden)")

        case "winrect":
            var s = "win="
            if let w = wc.window {
                s += String(format: "%.0f,%.0f %.0fx%.0f visible=%d key=%d",
                            w.frame.origin.x, w.frame.origin.y,
                            w.frame.width, w.frame.height,
                            w.isVisible ? 1 : 0, w.isKeyWindow ? 1 : 0)
            }
            s += " screens="
            s += NSScreen.screens.map {
                String(format: "%.0f,%.0f %.0fx%.0f", $0.frame.origin.x, $0.frame.origin.y,
                       $0.frame.width, $0.frame.height)
            }.joined(separator: ";")
            s += " active=\(NSApp.isActive ? 1 : 0)"
            say(s)

        case "focus":
            NSApp.activate(ignoringOtherApps: true)
            if let w = wc.window { w.makeKeyAndOrderFront(nil) }
            say("ok active=\(NSApp.isActive ? 1 : 0)")

        // 在进程内合成鼠标事件，交给 AppKit 的事件队列正常派发。
        // 从后台 shell 起进程时窗口拿不到前台会话，外部合成的鼠标事件会被丢掉，
        // 这条路径才能真正验证「双击有没有落在列表上」。
        case "click":
            // click row <行号> [次数]  /  click up|dropdown|pathfield [次数]
            guard parts.count >= 2 else { say("err arg"); return }
            var clicks = 1
            var host: NSView
            var point = NSZeroPoint
            switch parts[1] {
            case "row":
                guard parts.count >= 3, let n = Int(parts[2]) else { say("err arg"); return }
                if parts.count >= 4 { clicks = Int(parts[3]) ?? 1 }
                panel.tableView.scrollRowToVisible(n)
                let r = panel.tableView.rect(ofRow: n)
                guard r.height > 0 else { say("err norow"); return }
                host = panel.tableView
                point = NSPoint(x: r.minX + 40, y: r.midY)
            case "up":
                if parts.count >= 3 { clicks = Int(parts[2]) ?? 1 }
                host = panel.upButtonView
                point = NSPoint(x: host.bounds.midX, y: host.bounds.midY)
            case "dropdown":
                if parts.count >= 3 { clicks = Int(parts[2]) ?? 1 }
                host = panel.dropdownView
                point = NSPoint(x: host.bounds.midX, y: host.bounds.midY)
            case "pathfield":
                if parts.count >= 3 { clicks = Int(parts[2]) ?? 1 }
                host = panel.pathFieldView
                point = NSPoint(x: host.bounds.midX, y: host.bounds.midY)
            default:
                say("err target"); return
            }
            guard clicks >= 1 else { say("err clicks"); return }
            let loc = host.convert(point, to: nil)

            let (armed, lostBefore) = armWindow(wc)
            guard let win = armed else {
                FileHandle.standardError.write(
                    "click-cmd target=\(parts[1]) err notkey lostBefore=\(lostBefore)\n"
                        .data(using: .utf8)!)
                say("err notkey"); return
            }
            let wn = win.windowNumber

            var events: [NSEvent] = []
            for i in 1...clicks {
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    guard let e = NSEvent.mouseEvent(
                        with: type, location: loc, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: wn, context: nil,
                        eventNumber: 0, clickCount: i, pressure: 1)
                    else { say("err event"); return }
                    events.append(e)
                }
            }
            // 按顺序排进 AppKit 自己的事件队列，交给主 run loop 正常派发
            // （NSApplication.sendEvent → 窗口 → hitTest → 视图），和真实鼠标同一条路。
            // 不能在这里同步调 sendEvent：表格的 mouseDown 会自己进鼠标跟踪循环去取
            // 队列里的后续事件，和我们抢同一个队列，双击就会时灵时不灵。
            for e in events { NSApp.postEvent(e, atStart: false) }

            let (observed, lostAfter) = holdForeground(win)
            let line = "click-cmd target=\(parts[1]) clicks=\(clicks) holdActive=\(observed)"
                + " lostAfter=\(lostAfter) lostBefore=\(lostBefore)\n"
            FileHandle.standardError.write(line.data(using: .utf8)!)
            say("ok clicked=\(clicks) active=\(NSApp.isActive ? 1 : 0)"
                + " key=\(win.isKeyWindow ? 1 : 0) held=\(observed) lost=\(lostAfter)")

        // 在列表里按住左键拖一段：验证「列表内部拖动 = 框选」。
        // drag row <从行> <到行> [alt]   从某一行拖到另一行（带 alt 就是 ⌥ 拖动 = 拖文件出去）
        // drag empty <到行>              从列表下方的空白处拖到某一行
        case "drag":
            guard parts.count >= 3 else { say("err arg"); return }
            let table = panel.tableView

            func centerOf(row: Int) -> NSPoint? {
                table.scrollRowToVisible(row)
                let r = table.rect(ofRow: row)
                guard r.height > 0 else { return nil }
                return NSPoint(x: r.minX + 40, y: r.midY)
            }

            var from = NSZeroPoint
            var toRow = 0
            switch parts[1] {
            case "row":
                guard parts.count >= 4,
                      let a = Int(parts[2]), let b = Int(parts[3]),
                      let p = centerOf(row: a) else { say("err arg"); return }
                from = p
                toRow = b
            case "empty":
                guard let b = Int(parts[2]) else { say("err arg"); return }
                let last = table.numberOfRows - 1
                let bottom = last >= 0 ? table.rect(ofRow: last).maxY : 0
                let y = min(table.bounds.height - 6, bottom + 14)
                guard y > bottom else { say("err noempty"); return }
                from = NSPoint(x: 40, y: y)
                toRow = b
            default:
                say("err target"); return
            }
            guard let to = centerOf(row: toRow) else { say("err norow"); return }

            let (armed, lostBefore) = armWindow(wc)
            guard let win = armed else {
                FileHandle.standardError.write(
                    "drag-cmd err notkey lostBefore=\(lostBefore)\n".data(using: .utf8)!)
                say("err notkey"); return
            }
            let wn = win.windowNumber
            let p1 = table.convert(from, to: nil)
            let p2 = table.convert(to, to: nil)
            let steps = 8
            let flags: NSEvent.ModifierFlags = parts.contains("alt") ? [.option] : []
            let t0 = ProcessInfo.processInfo.systemUptime
            func mk(_ type: NSEvent.EventType, _ p: NSPoint, _ t: TimeInterval) -> NSEvent? {
                NSEvent.mouseEvent(with: type, location: p, modifierFlags: flags,
                                   timestamp: t, windowNumber: wn, context: nil,
                                   eventNumber: 0, clickCount: 1, pressure: 1)
            }
            var events: [NSEvent] = []
            if let e = mk(.leftMouseDown, p1, t0) { events.append(e) }
            for i in 1...steps {
                let f = CGFloat(i) / CGFloat(steps)
                let p = NSPoint(x: p1.x + (p2.x - p1.x) * f, y: p1.y + (p2.y - p1.y) * f)
                if let e = mk(.leftMouseDragged, p, t0 + 0.01 * Double(i)) { events.append(e) }
            }
            if let e = mk(.leftMouseUp, p2, t0 + 0.2) { events.append(e) }
            for e in events { NSApp.postEvent(e, atStart: false) }

            let (observed, lostAfter) = holdForeground(win)
            FileHandle.standardError.write(
                ("drag-cmd from=\(Int(from.x)),\(Int(from.y)) to=\(Int(to.x)),\(Int(to.y))"
                 + " alt=\(flags.contains(.option) ? 1 : 0) holdActive=\(observed)"
                 + " lostAfter=\(lostAfter) lostBefore=\(lostBefore)\n").data(using: .utf8)!)
            // 不在这里报选中项：合成的鼠标事件要等这条命令返回后才派发，
            // 现在读到的还是上一次的状态，报出来只会误导。用 state 单独读。
            say("ok dragged=\(steps)")

        // 把若干路径当成「刚被拖进窗口」交给拖放处理入口。
        //
        // 为什么要有这条：合成的拖动（上面那条 drag）到不了窗口服务器那一步 ——
        // 松手后窗口服务器那条拖动会话收不了尾，drop 也就不会触发（实测：屏幕上会
        // 留下一个跨整屏的拖动影像窗口，把之后的鼠标点击全吃掉）。所以「拖进窗口
        // 会怎样」这条语义没法用合成拖动验证；这里直接把落点处理入口调一遍，
        // 走的仍是真实链路（面板 → onFilesDropped → 主窗口的 handleDrop）。
        case "drop":
            let paths = Array(parts.dropFirst())
            guard !paths.isEmpty else { say("err arg"); return }
            panel.onFilesDropped?(panel, paths.map { URL(fileURLWithPath: $0) })
            say("ok dropped=\(paths.count)")

        case "unzip":
            // 对给定的归档跑一次智能解压。走的和列表里点「解压（智能）」是同一条路
            // （wc.smartExtract），所以进度、落点规则、冲突处理都测得到。
            let targets = Array(parts.dropFirst())
            guard !targets.isEmpty else { say("err arg"); return }
            wc.smartExtract(targets)
            say("ok unzip=\(targets.count)")

        case "hit":
            // 命中测试：某控件中心点上，窗口真正会把事件派给谁。
            // 控件被遮挡 / 落在父视图 bounds 之外时，这里会暴露出来。
            guard parts.count >= 2 else { say("err arg"); return }
            var h: NSView
            switch parts[1] {
            case "up": h = panel.upButtonView
            case "dropdown": h = panel.dropdownView
            case "pathfield": h = panel.pathFieldView
            case "table": h = panel.tableView
            default: say("err target"); return
            }
            let mid = NSPoint(x: h.bounds.midX, y: h.bounds.midY)
            let inWindow = h.convert(mid, to: nil)
            let hitView = wc.window?.contentView?.hitTest(inWindow)
            var chain: [String] = []
            var v: NSView? = hitView
            while let cur = v, chain.count < 6 {
                chain.append(String(describing: type(of: cur)))
                v = cur.superview
            }
            say("target=\(String(describing: type(of: h))) hit=\(chain.first ?? "nil") chain=\(chain.joined(separator: ">"))")

        case "filemenu":
            // update() 会触发 AppKit 的菜单校验，得到的就是弹出时用户看到的状态
            guard let m = NSApp.mainMenu?.items.compactMap({ $0.submenu })
                .first(where: { $0.title == S.menuFile }) else { say("err nomenu"); return }
            m.update()
            say(m.items.map { it -> String in
                it.isSeparatorItem ? "-" : "\(it.title)(\(it.isEnabled ? "on" : "off"))"
            }.joined(separator: ","))

        case "toolbar":
            say(wc.toolbarStateDump)

        case "shot":
            // 路径里有空格，参数在这里已经按空格切开了，要重新拼回去
            guard parts.count >= 2 else { say("err arg"); return }
            let path = parts.dropFirst().joined(separator: " ")
            Capture.writeNow(path)
            say("ok shot=\(path)")

        case "pressup":
            panel.pressUpButton()
            say("ok")

        case "lang":
            // 当前界面语言，以及 bundle 里那份 .lproj 的每一条文案实际查出来是什么。
            // 键是从 bundle 自己的 .strings 读的，所以这里走的是真正的查表通路，
            // 不是把文件内容原样吐出来。
            func esc(_ s: String) -> String {
                s.replacingOccurrences(of: "\\", with: "\\\\")
                 .replacingOccurrences(of: "\n", with: "\\n")
                 .replacingOccurrences(of: "\t", with: "\\t")
            }
            var out = "ok lang=\(CurrentLanguage.identifier)"
                + " available=\(CurrentLanguage.available.joined(separator: ","))"
            for k in CurrentLanguage.keys(inTable: "Localizable") {
                out += "\nl\t\(esc(k))\t\(esc(L(k)))"
            }
            for k in CurrentLanguage.keys(inTable: "ServicesMenu") {
                out += "\ns\t\(esc(k))\t\(esc(L(k, table: "ServicesMenu")))"
            }
            out += "\nend"
            say(out)

        case "quit":
            NSApp.terminate(nil)

        default:
            say("err unknown \(cmd)")
        }
    }
}
