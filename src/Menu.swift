// 菜单栏。结构与条目照抄 Windows 版 7-Zip File Manager 的菜单资源
// （CPP/7zip/UI/FileManager/resource.rc 里的 IDM_MENU），
// 只在 macOS 必须的地方调整：最前面是应用菜单，退出用 Cmd+Q。

import AppKit

extension MainWindowController: NSMenuItemValidation {}

extension MainWindowController {

    private func item(_ title: String, _ action: Action?, key: String = "",
                      modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let it = NSMenuItem(title: title,
                            action: action == nil ? nil : #selector(menuDispatch(_:)),
                            keyEquivalent: key)
        it.target = self
        it.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        it.isEnabled = action != nil
        it.representedObject = action.map { NSNumber(value: $0.rawValue) }
        return it
    }

    @objc func menuDispatch(_ sender: NSMenuItem) {
        guard let n = sender.representedObject as? NSNumber,
              let a = Action(rawValue: n.intValue) else { return }
        performAction(a)
    }

    /// 当前面板下这个命令能不能用。菜单打开时 AppKit 会逐个问一遍，
    /// 所以选中项一变、菜单就是新的（Windows 版的菜单也是每次弹出时重算，
    /// 走的是 MyLoadMenu.cpp 的 OnMenuActivating → CreateFileMenu）。
    func isEnabled(_ a: Action) -> Bool {
        let p = activePanel
        let sel = p.selectedEntries()
        let inArchive = p.location.isArchive
        let single = sel.count == 1
        switch a {
        case .open, .openOutside, .copyTo, .moveTo, .delete, .properties:
            return !sel.isEmpty
        case .openInside:
            return single && ((sel.first?.isArchive ?? false)
                              || (inArchive && (sel.first?.isDir ?? false)))
        case .view, .edit:
            return single && !(sel.first?.isDir ?? true)
        case .rename:
            return single
        case .split:
            return single && !inArchive && !(sel.first?.isDir ?? true)
        case .combine:
            return sel.count >= 2 && !inArchive
        case .diff:
            return sel.count == 2 && !inArchive
        case .createFile:
            return !inArchive
        case .selectByType, .deselectByType:
            return !sel.isEmpty
        case .upOneLevel:
            // 和地址栏那个「上一级」按钮同一条规则（PanelItems.cpp:523）
            return p.location.parent != nil
        default:
            return true
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let n = item.representedObject as? NSNumber,
              let a = Action(rawValue: n.intValue) else { return true }
        return isEnabled(a)
    }

    /// 只在菜单里出现、不走 performAction 的项
    @objc func menuNewWindow(_ sender: Any) {
        let wc = MainWindowController(initialLocation: Location(root: activePanel.location.display))
        MainWindowController.extraWindows.append(wc)
    }

    static var extraWindows: [MainWindowController] = []

    func buildMenu() {
        let s = Settings.shared
        let main = NSApp.mainMenu ?? NSMenu()
        main.removeAllItems()

        // ---- 应用菜单
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(item(S.menuAbout, .about, key: "", modifiers: []))
        appMenu.addItem(.separator())
        appMenu.addItem(item(S.optionsTitle, .options, key: ","))
        appMenu.addItem(.separator())
        if #available(macOS 14.0, *) {
            let services = NSMenuItem(title: S.appServices, action: nil, keyEquivalent: "")
            let sub = NSMenu()
            services.submenu = sub
            NSApp.servicesMenu = sub
            appMenu.addItem(services)
            appMenu.addItem(.separator())
        }
        let hide = NSMenuItem(title: S.appHide, action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(hide)
        let hideOthers = NSMenuItem(title: S.appHideOthers, action: #selector(NSApplication.hideOtherApplications(_:)),
                                    keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(title: S.appShowAll, action: #selector(NSApplication.unhideAllApplications(_:)),
                                   keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(item(S.menuExit, .exit, key: "q"))

        // ---- File
        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let file = NSMenu(title: S.menuFile)
        fileItem.submenu = file

        file.addItem(item(S.menuOpen, .open, key: "\r", modifiers: []))
        file.addItem(item(S.menuOpenInside, .openInside, key: "\u{F72D}", modifiers: [.control]))
        file.addItem(item(S.menuOpenOutside, .openOutside, key: "\r", modifiers: [.shift]))
        file.addItem(.separator())
        // 加速键对齐 Windows 版的 PanelKey.cpp：F3 查看、F4 编辑。
        // 这两个键在 FilePanel 的键盘处理里本来就实现了，菜单这边只是把键显示出来。
        file.addItem(item(S.menuView, .view, key: "\u{F706}", modifiers: []))
        file.addItem(item(S.menuEditItem, .edit, key: "\u{F707}", modifiers: []))
        file.addItem(.separator())
        file.addItem(item(S.menuRename, .rename, key: "\u{F705}", modifiers: []))
        file.addItem(item(S.menuCopyTo, .copyTo, key: "\u{F708}", modifiers: []))
        file.addItem(item(S.menuMoveTo, .moveTo, key: "\u{F709}", modifiers: []))
        file.addItem(item(S.menuDelete, .delete, key: "\u{08}", modifiers: [.command]))
        file.addItem(.separator())
        file.addItem(item(S.menuSplit, .split))
        file.addItem(item(S.menuCombine, .combine))
        file.addItem(.separator())
        file.addItem(item(S.menuProperties, .properties, key: "i"))
        file.addItem(item(S.menuDiff, .diff))
        file.addItem(.separator())
        file.addItem(item(S.menuCreateFolder, .createFolder, key: "\u{F70A}", modifiers: []))
        file.addItem(item(S.menuCreateFile, .createFile, key: "\u{F707}", modifiers: [.shift]))
        file.addItem(.separator())
        let newWindow = NSMenuItem(title: S.menuNewWindow, action: #selector(menuNewWindow(_:)), keyEquivalent: "n")
        newWindow.target = self
        file.addItem(newWindow)
        file.addItem(item(S.menuExit, .exit, key: "q"))

        // ---- Edit
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: S.menuEdit)
        editItem.submenu = edit
        edit.addItem(item(S.menuSelectAll, .selectAll, key: "a"))
        edit.addItem(item(S.menuDeselectAll, .deselectAll, key: "a", modifiers: [.command, .shift]))
        edit.addItem(item(S.menuInvertSelection, .invertSelection))
        edit.addItem(.separator())
        edit.addItem(item(S.menuSelect, .selectMask))
        edit.addItem(item(S.menuDeselect, .deselectMask))
        edit.addItem(.separator())
        edit.addItem(item(S.menuSelectByType, .selectByType))
        edit.addItem(item(S.menuDeselectByType, .deselectByType))

        // ---- View
        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let view = NSMenu(title: S.menuViewMenu)
        viewItem.submenu = view
        let vm = s.viewMode
        for (i, title) in [S.menuLargeIcons, S.menuSmallIcons, S.menuList, S.menuDetails].enumerated() {
            let a: Action = [.viewLargeIcons, .viewSmallIcons, .viewList, .viewDetails][i]
            let it = item(title, a, key: String(i + 1), modifiers: [.control])
            it.state = (vm == i) ? .on : .off
            view.addItem(it)
        }
        view.addItem(.separator())
        let sortTitles: [(String, Action)] = [
            (S.menuArrangeByName, .sortName), (S.menuArrangeByType, .sortType),
            (S.menuArrangeByDate, .sortDate), (S.menuArrangeBySize, .sortSize),
            (S.menuArrangeNoSort, .sortNone),
        ]
        for (title, a) in sortTitles {
            let it = item(title, a)
            it.state = (activePanel.sortKey == sortKeyFor(a)) ? .on : .off
            view.addItem(it)
        }
        view.addItem(.separator())
        view.addItem(item(S.menuTwoPanels, .twoPanels, key: "\u{F70C}", modifiers: []))
        view.addItem(item(S.menuOpenRootFolder, .openRoot))
        view.addItem(item(S.menuUpOneLevel, .upOneLevel, key: "\u{F72C}", modifiers: [.control]))
        view.addItem(item(S.menuFoldersHistory, .foldersHistory, key: "\u{F70F}", modifiers: [.command]))
        view.addItem(.separator())
        view.addItem(item(S.menuRefresh, .refresh, key: "r"))
        let autoRefresh = item(S.menuAutoRefresh, .autoRefresh)
        autoRefresh.state = s.autoRefresh ? .on : .off
        view.addItem(autoRefresh)

        let toolbars = NSMenuItem(title: S.menuToolbars, action: nil, keyEquivalent: "")
        let tbMenu = NSMenu()
        let t1 = item(S.menuArchiveToolbar, .toggleArchiveToolbar)
        t1.state = s.showArchiveToolbar ? .on : .off
        let t2 = item(S.menuStandardToolbar, .toggleStandardToolbar)
        t2.state = s.showStandardToolbar ? .on : .off
        let t3 = item(S.menuLargeButtons, .largeButtons)
        t3.state = s.largeButtons ? .on : .off
        let t4 = item(S.menuShowButtonsText, .showButtonsText)
        t4.state = s.showButtonsText ? .on : .off
        tbMenu.addItem(t1); tbMenu.addItem(t2)
        tbMenu.addItem(.separator())
        tbMenu.addItem(t3); tbMenu.addItem(t4)
        toolbars.submenu = tbMenu
        view.addItem(toolbars)

        // ---- Favorites
        let favItem = NSMenuItem()
        main.addItem(favItem)
        let fav = NSMenu(title: S.menuFavorites)
        favItem.submenu = fav
        let addFav = NSMenuItem(title: S.menuAddToFavorites, action: nil, keyEquivalent: "")
        let addSub = NSMenu()
        addFav.submenu = addSub
        addSub.addItem(item(S.menuAddToFavorites, .addFavorite))
        fav.addItem(addFav)
        fav.addItem(.separator())
        for (i, f) in s.favorites.enumerated() {
            let it = NSMenuItem(title: f["name"] ?? f["path"] ?? "?",
                                action: #selector(menuFavorite(_:)), keyEquivalent: "")
            it.target = self
            it.tag = i
            fav.addItem(it)
        }

        // ---- Tools
        let toolsItem = NSMenuItem()
        main.addItem(toolsItem)
        let tools = NSMenu(title: S.menuTools)
        toolsItem.submenu = tools
        tools.addItem(item(S.menuOptions, .options, key: ","))
        tools.addItem(.separator())
        tools.addItem(item(S.menuBenchmark, .benchmark))
        tools.addItem(.separator())
        tools.addItem(item(S.menuTempDir, .tempDir))

        // ---- Help
        let helpItem = NSMenuItem()
        main.addItem(helpItem)
        let help = NSMenu(title: S.menuHelp)
        helpItem.submenu = help
        help.addItem(item(S.menuHelpContents, .helpContents, key: "?"))
        help.addItem(item(S.menuAbout, .about))
    }

    private func sortKeyFor(_ a: Action) -> String {
        switch a {
        case .sortName: return Columns.name
        case .sortType: return "type"
        case .sortDate: return Columns.mtime
        case .sortSize: return Columns.size
        case .sortNone: return ""
        default: return ""
        }
    }

    @objc func menuFavorite(_ sender: NSMenuItem) {
        let favs = Settings.shared.favorites
        guard sender.tag >= 0, sender.tag < favs.count, let path = favs[sender.tag]["path"] else { return }
        activePanel.navigate(toPath: path)
    }
}
