// 列出系统「服务」菜单里当前实际出现的条目文字。
//
// 右键菜单（Finder 的服务子菜单）用的是同一份数据：LaunchServices 把各 App 的
// Info.plist 读进来，再按 *提供方 bundle 的本地化* 把 NSServices/NSMenuItem/default
// 那条字符串翻成当前语言。所以「服务菜单里显示什么」只能这样读，不能靠读 Info.plist
// 猜 —— 猜出来的永远是英文原文。
//
// AppKit 是等到菜单要显示时才去填条目的（menuNeedsUpdate），所以这里真的弹一次菜单，
// 把条目读出来后再取消，不然拿到的是空列表。
//
// **必须包成 .app 才能读出本地化后的名字。** 挑哪一份译文是按*调用方*的语言决定的，
// 而一个裸可执行文件没有本地化元数据，`Bundle.main.preferredLocalizations` 只能是
// 开发语言（英文），于是永远读到英文原文；访达是 App，挑的是系统语言那一份。
// `scripts/verify-ui.sh` 因此把它装进 build/serviceslist.app 再跑。
// 想指定语言，就直接给可执行文件传 `-AppleLanguages "(zh-Hans)"`。
//
// 用法：serviceslist [过滤子串] [-AppleLanguages "(语言)"]

import AppKit

let needle = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let main = NSMenu()
let appItem = NSMenuItem()
main.addItem(appItem)
let appMenu = NSMenu()
let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
let servicesMenu = NSMenu(title: "Services")
servicesItem.submenu = servicesMenu
appMenu.addItem(servicesItem)
appItem.submenu = appMenu
app.mainMenu = main
app.servicesMenu = servicesMenu

app.finishLaunching()

func collect(_ menu: NSMenu) -> [String] {
    var out: [String] = []
    for item in menu.items {
        if !item.isSeparatorItem { out.append(item.title) }
        if let sub = item.submenu { out += collect(sub) }
    }
    return out
}

var titles = collect(servicesMenu)

if titles.isEmpty {
    // 弹一次让它填充，再用定时器取消（不然会一直挂着）
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                     styleMask: [.titled], backing: .buffered, defer: false)
    let v = w.contentView!
    // 定时器必须挂到 .common 上。弹菜单进的是 NSEventTrackingRunLoopMode 的事件循环，
    // 挂在默认模式上的定时器在里面不触发 —— cancelTracking() 就永远等不到，
    // 本工具会一直停在菜单跟踪里（屏幕上菜单一直开着，要人工按 Esc 才退）。
    let cancel = Timer(timeInterval: 0.6, repeats: false) { _ in
        titles = collect(servicesMenu)
        servicesMenu.cancelTracking()
    }
    RunLoop.current.add(cancel, forMode: .common)
    servicesMenu.popUp(positioning: nil,
                       at: NSPoint(x: 20, y: 20), in: v)
    RunLoop.current.run(until: Date().addingTimeInterval(1.0))
    titles = collect(servicesMenu)
}

for t in titles where needle.isEmpty || t.localizedCaseInsensitiveContains(needle) {
    print(t)
}
print("count=\(titles.count) matched=\(needle.isEmpty ? "(全部)" : needle)")
