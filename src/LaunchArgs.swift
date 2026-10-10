// 命令行开关。
//
// 正常双击启动时一个都用不到。它们只服务于「不用屏幕录制权限也能看界面」：
//    --capture <文件>   把窗口自绘到位图写出去，然后退出
//    --delay <秒>       等界面数据加载完再截（默认 1.5）
//    --open <路径>      起始位置（目录或归档文件）
//    --panels <1|2>     面板数

import Foundation

enum LaunchArgs {

    private static func value(_ flag: String) -> String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: flag), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    /// nil 表示这次是正常启动，不做离屏截图
    static var capturePath: String? { value("--capture") }

    static var captureDelay: TimeInterval {
        guard let v = value("--delay"), let d = Double(v) else { return 1.5 }
        return d
    }

    static var initialPath: String? { value("--open") }

    /// 开发用：启动后直接把某个对话框调起来，配合 --capture 截图检查
    static var dialog: String? { value("--dialog") }

    /// 开发用：Add 对话框打开时预选的格式（配合 --dialog add）
    static var addFormat: String? { value("--add-format") }

    /// 开发用：Add 对话框打开时预选的压缩级别名（Store / Normal / Ultra …）
    static var addLevel: String? { value("--add-level") }

    /// 开发用：把窗口里的视图树连同各自的实际尺寸打到 stderr。
    /// 布局对不上源码时，看这个比看截图像素准。
    static var dumpLayout: Bool { CommandLine.arguments.contains("--dump-layout") }

    /// 开发用：把菜单栏连同加速键打出来（核对是否与 Windows 版一致）
    static var dumpMenu: Bool { CommandLine.arguments.contains("--dump-menu") }

    /// 开发用：从 stdin 读命令、往 stdout 写结果，配合 tools/uiprobe.py 做交互验证
    static var automation: Bool {
        CommandLine.arguments.contains("--automation") || automationIO != nil
    }

    /// 开发用：命令/结果走目录里的 cmd、out 文件（--automation-io <dir>）
    static var automationIO: String? { value("--automation-io") }

    static var panels: Int? {
        guard let v = value("--panels"), let n = Int(v) else { return nil }
        return max(1, min(2, n))
    }
}
