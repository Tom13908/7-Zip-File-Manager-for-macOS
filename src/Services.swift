// Finder 右键菜单集成。
//
// macOS 上不能像 Windows 那样往资源管理器里插壳扩展（那需要 FinderSync 扩展，
// 而扩展必须以带签名的主体 App 分发，还要求一个真正的 .app bundle 加扩展目标），
// 所以走系统自带的「服务」机制：Info.plist 里声明 NSServices，用户就能在
// Finder 右键 -> 服务里看到下面这些条目。
//
// 条目与 mkinfo.py 的 SERVICES 一一对应，行为都是「不弹主窗口，只出进度窗」。
//
// 注意菜单顺序不归这里管：Finder 的服务子菜单是按**本地化后的显示文字**排序的
// （同一 App 的条目排成一组，组内按文字排），Info.plist 里的声明顺序不起作用。
// 所以「Extract (Smart)」在中文界面排第一，靠的是译文写成「解压（智能）」。

import AppKit

// MARK: - 启动原因

/// 服务调用与正常启动都走 applicationDidFinishLaunching，系统不告诉启动原因。
/// 由服务回调在收到消息的第一时间置位，启动那边据此决定要不要弹主窗口。
enum LaunchContext {
    private(set) static var servingFinder = false

    /// 服务晚于启动宽限期才到时，主窗口已经先弹出来了，要把它收掉
    static var onServingFinder: (() -> Void)?

    /// 只应该在主线程调用
    static func markServingFinder() {
        servingFinder = true
        onServingFinder?()
    }
}

// MARK: - 服务实现

final class ServicesProvider: NSObject {

    /// 进度窗口没人持有会在下一次 runloop 被释放，这里留住
    private static var running: [ProgressWindowController] = []
    private static let operations = Operations()

    /// 服务入口。**每个服务方法的第一件事都是调它**：先把「正在服务」置位再去判断，
    /// 这样无论后面走到哪个分支、能不能做成，主窗口都不会冒出来。
    ///
    /// 原来的写法是先 `guard` 后 `beginServing()`，于是一旦选中的东西没通过判断，
    /// 方法就静默返回：`servingFinder` 没置位，启动宽限期一过主窗口照弹，
    /// 用户看到的就是「弹出软件的界面，然后没有任何反应」—— 既没动作也没提示。
    ///
    /// 返回 nil 表示没有可处理的对象（已经弹窗说明过了）。
    private func serving(_ name: String, _ pasteboard: NSPasteboard) -> [URL]? {
        LaunchContext.markServingFinder()
        NSApp.activate(ignoringOtherApps: true)

        let items = urls(from: pasteboard)
        NSLog("7zip-svc: %@ items=%d", name, items.count)
        guard !items.isEmpty else {
            // 从 Finder 正常触发走不到这里；真走到了也得说出来，不能一声不吭
            DispatchQueue.main.async {
                DialogKit.alert(S.svcNoFiles, "", style: .warning, parent: nil)
            }
            return nil
        }
        return items
    }

    /// 从选中的文件里挑出要交给引擎的。
    ///
    /// 一个都没匹配上扩展名表时，仍然把第一个交给引擎 —— 用户是明确点了「解压」的，
    /// 那张表只是给文件列表配图标用的，不该在这里替用户否决。真不是归档的话
    /// 引擎会报错，那个错误用户看得见。原来这里是直接 return，等于点了没反应。
    private func archiveTargets(_ name: String, _ files: [URL]) -> [URL] {
        let known = files.filter { Location.isArchiveFile($0.path) }
        if !known.isEmpty { return known }
        NSLog("7zip-svc: %@ none of %d file(s) is in the archive table, handing the first to the engine: %@",
              name, files.count, files[0].lastPathComponent)
        return [files[0]]
    }

    private func retain(_ wc: ProgressWindowController) {
        ServicesProvider.running.append(wc)
        ServicesProvider.running.removeAll { $0.model.finished }
    }

    /// 从服务粘贴板里取出选中的文件/文件夹
    private func urls(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let items = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] {
            return items
        }
        return []
    }

    /// 解压的公共部分：目标目录 + 覆盖策略都由调用方定，这里只负责发命令和显示进度
    private func extract(_ files: [URL], destination: @escaping (URL) -> String,
                         overwrite: ExtractOverwriteMode) {
        for f in files {
            var o = ExtractOptions()
            o.destination = destination(f)
            o.pathMode = .full
            o.overwrite = overwrite
            let total = Operations.archiveTotalSize(at: f.path)
            try? FileManager.default.createDirectory(atPath: o.destination,
                                                     withIntermediateDirectories: true)
            let wc = ServicesProvider.operations.extract(archive: f.path, names: [], options: o,
                                                         totalBytes: total, parent: nil)
            retain(wc)
        }
    }

    // MARK: 解压

    /// 智能解压（Bandizip 的「智能解压至此」）。落点由包内结构决定，见 SmartExtract。
    @objc func extractSmart(_ pasteboard: NSPasteboard, userData: String,
                            error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let items = serving("extractSmart", pasteboard) else { return }
        let files = archiveTargets("extractSmart", items)
        let parent = files[0].deletingLastPathComponent().path
        // 多个归档一起选时：只要它们都在同一个目录里，才让用户答一次冲突问题，
        // 否则逐个问 —— 落点不同的归档混在一起问一个问题没有意义。
        var answered: ExtractOverwriteMode?
        for f in files {
            let here = f.deletingLastPathComponent().path
            let dest = SmartExtract.destination(archive: f.path, password: nil)
            var mode: ExtractOverwriteMode = .overwrite
            // 只有「摊在压缩包所在目录」这一种落点才可能撞上已有文件；
            // 新建文件夹那条落点目录本来就是空的
            if dest == here {
                let hits = SmartExtract.existingTopLevel(archive: f.path, destination: dest, password: nil)
                if !hits.isEmpty {
                    if here == parent, let a = answered {
                        mode = a
                    } else {
                        guard let a = OverwritePrompt.resolve(conflicts: hits, destination: dest,
                                                              parent: nil) else { return }
                        mode = a
                        if here == parent { answered = a }
                    }
                }
            }
            extract([f], destination: { _ in dest }, overwrite: mode)
        }
    }

    /// 解压到当前文件夹（对应 Windows 的 “Extract Here”）
    @objc func extractHere(_ pasteboard: NSPasteboard, userData: String,
                           error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let items = serving("extractHere", pasteboard) else { return }
        let files = archiveTargets("extractHere", items)
        for f in files {
            let dest = f.deletingLastPathComponent().path
            let hits = SmartExtract.existingTopLevel(archive: f.path, destination: dest, password: nil)
            guard let mode = OverwritePrompt.resolve(conflicts: hits, destination: dest,
                                                     parent: nil) else { return }
            extract([f], destination: { _ in dest }, overwrite: mode)
        }
    }

    /// 弹出解压对话框，目标路径自己选（原来的 “Extract files...”）
    @objc func extractToDialog(_ pasteboard: NSPasteboard, userData: String,
                               error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let items = serving("extractToDialog", pasteboard) else { return }
        let files = archiveTargets("extractToDialog", items)
        let first = files[0]
        let dir = first.deletingLastPathComponent().path
        guard let o = ExtractDialog.run(archive: first.path, baseDir: dir, parent: nil) else { return }
        let total = files.reduce(Int64(0)) { $0 + Operations.archiveTotalSize(at: $1.path) }
        let wc = ServicesProvider.operations.extract(archive: first.path, names: [], options: o,
                                                     totalBytes: total, parent: nil)
        retain(wc)
        // 多个归档时，其余的按同一个设置接着解
        for f in files.dropFirst() {
            var sub = o
            sub.destination = (o.destination as NSString)
                .appendingPathComponent(f.deletingPathExtension().lastPathComponent)
            try? FileManager.default.createDirectory(atPath: sub.destination,
                                                     withIntermediateDirectories: true)
            let w = ServicesProvider.operations.extract(
                archive: f.path, names: [], options: sub,
                totalBytes: Operations.archiveTotalSize(at: f.path), parent: nil)
            retain(w)
        }
    }

    // MARK: 压缩

    /// 压缩。原来「Compress to 7z」「Compress to Zip」「Add to Archive…」是三条独立服务，
    /// 前两条按默认参数闷头压、格式写死在服务名里，三条做的其实是同一件事，
    /// 现在合成一条：一律弹出「Add to Archive」对话框，格式、级别、名字都在里面选。
    @objc func compressWithDialog(_ pasteboard: NSPasteboard, userData: String,
                                  error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let files = serving("compressWithDialog", pasteboard) else { return }
        let dir = files[0].deletingLastPathComponent().path
        let total = files.reduce(Int64(0)) { $0 + Operations.sizeOfItem(at: $1.path) }
        guard let (archive, options) = AddDialog.run(targets: files.map { $0.path },
                                                     inWorkingDir: dir,
                                                     totalBytes: total, parent: nil) else { return }
        let wc = ServicesProvider.operations.add(archive: archive,
                                                 files: files.map { $0.lastPathComponent },
                                                 workingDirectory: dir, options: options,
                                                 totalBytes: total, parent: nil)
        retain(wc)
    }

    // MARK: 测试

    /// 校验归档（对应 “Test archive”）
    @objc func testArchive(_ pasteboard: NSPasteboard, userData: String,
                           error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let items = serving("testArchive", pasteboard) else { return }
        let files = archiveTargets("testArchive", items)
        let total = files.reduce(Int64(0)) { $0 + Operations.archiveTotalSize(at: $1.path) }
        let wc = ServicesProvider.operations.test(archives: files.map { $0.path }, password: nil,
                                                  totalBytes: total, parent: nil)
        retain(wc)
    }
}
