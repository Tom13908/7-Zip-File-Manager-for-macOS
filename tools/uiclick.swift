// 往指定进程合成一次鼠标点击 / 按键。
// 用法：
//   uiclick <pid> <x> <y> [clicks]      clicks=2 就是双击
//   uiclick <pid> key <keycode> [flags] keycode 见 HIToolbox（51=Backspace）

import CoreGraphics
import Foundation

let a = CommandLine.arguments
guard a.count >= 3, let pid = pid_t(a[1]) else {
    FileHandle.standardError.write("usage: uiclick <pid> <x> <y> [clicks] | uiclick <pid> key <keycode>\n"
        .data(using: .utf8)!)
    exit(2)
}

//  --tap-hid 时走窗口服务器（CGEventPost 到 cghidEventTap）而不是直接投到 pid。
//  直接投 pid 对键盘有效，对鼠标有时会被丢掉；合成鼠标还是过一遍窗口服务器更像真机。

func post(_ e: CGEvent) {
    if CommandLine.arguments.contains("--tap-hid") {
        e.post(tap: .cghidEventTap)
    } else {
        e.postToPid(pid)
    }
}

if a[2] == "key" {
    guard a.count >= 4, let code = UInt16(a[3]) else { exit(2) }
    var flags: CGEventFlags = []
    if a.count >= 5 {
        switch a[4] {
        case "cmd": flags = .maskCommand
        case "ctrl": flags = .maskControl
        case "alt": flags = .maskAlternate
        case "shift": flags = .maskShift
        default: break
        }
    }
    let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!
    let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)!
    down.flags = flags
    up.flags = flags
    post(down)
    usleep(30_000)
    post(up)
    usleep(50_000)
    exit(0)
}

guard a.count >= 4, let x = Double(a[2]), let y = Double(a[3]) else { exit(2) }
let clicks = a.count >= 5 ? (Int(a[4]) ?? 1) : 1
let p = CGPoint(x: x, y: y)

let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p,
                   mouseButton: .left)!
post(move)
usleep(30_000)

for i in 1...clicks {
    let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                       mouseCursorPosition: p, mouseButton: .left)!
    let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                     mouseCursorPosition: p, mouseButton: .left)!
    down.setIntegerValueField(.mouseEventClickState, value: Int64(i))
    up.setIntegerValueField(.mouseEventClickState, value: Int64(i))
    post(down)
    usleep(40_000)
    post(up)
    usleep(40_000)
}
usleep(150_000)
