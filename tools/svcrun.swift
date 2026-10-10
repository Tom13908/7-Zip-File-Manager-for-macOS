// 从外部触发一次 Finder 服务，用来验证右键菜单那条通路。
//
// Finder 调服务和这里做的事完全一样：把选中的文件放进通用粘贴板，然后按服务名
// 请求服务系统执行。So 这个工具测出来的结论，就是用户在 Finder 右键点下去会得到的结论。
//
// 用法：svcrun <服务名> <文件...>
//   svcrun "Extract Here" /tmp/x/arch.7z
//
// 退出码：0 = 服务被找到并执行；3 = 系统里没有这个服务（名字错或服务没注册）。

import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("用法: svcrun <服务名> <文件...>\n".data(using: .utf8)!)
    exit(2)
}

let serviceName = args[1]
let urls = args.dropFirst(2).map { URL(fileURLWithPath: $0) }

for u in urls where !FileManager.default.fileExists(atPath: u.path) {
    FileHandle.standardError.write("文件不存在：\(u.path)\n".data(using: .utf8)!)
    exit(2)
}

let pb = NSPasteboard.general
pb.clearContents()
guard pb.writeObjects(urls as [NSURL]) else {
    FileHandle.standardError.write("写粘贴板失败\n".data(using: .utf8)!)
    exit(4)
}

let found = NSPerformService(serviceName, pb)
print("service=\(serviceName) found=\(found ? 1 : 0) files=\(urls.count)")

// 接收方要按粘贴板名去读数据，进程别马上退
RunLoop.current.run(until: Date().addingTimeInterval(1.5))
exit(found ? 0 : 3)
