// 列出某个 App 当前在屏幕上的所有窗口，用来回答「它到底弹出了什么」。
//
// 只读窗口的归属、层级和尺寸，不读窗口标题 —— 标题在 macOS 10.15+ 要屏幕录制权限，
// 尺寸和层级不用。判断「主窗口还是对话框」「有没有窗口」够用了。
//
// 用法：winlist [进程名子串]
//   tools/winlist.swift → build/winlist "7-Zip"

import AppKit

let needle = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""

guard let list = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
else {
    FileHandle.standardError.write("拿不到窗口列表\n".data(using: .utf8)!)
    exit(1)
}

var count = 0
for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    if !needle.isEmpty && !owner.localizedCaseInsensitiveContains(needle) { continue }
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    func num(_ k: String) -> Double { (b[k] as? NSNumber)?.doubleValue ?? -1 }
    let layer = (w[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
    let alpha = (w[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? -1
    print(String(format: "owner=%@ layer=%d alpha=%.2f pos=%.0f,%.0f size=%.0fx%.0f",
                 owner, layer, alpha, num("X"), num("Y"), num("Width"), num("Height")))
    count += 1
}
print("count=\(count) matched=\(needle.isEmpty ? "(全部)" : needle)")
