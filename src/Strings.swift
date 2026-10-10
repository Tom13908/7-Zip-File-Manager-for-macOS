// 界面文案与格式常量。
//
// 这里的每一条英文都与 Windows 版 7-Zip 的资源脚本逐条对齐，来源：
//   CPP/7zip/UI/FileManager/resource.rc
//   CPP/7zip/UI/GUI/Extract.rc
//   CPP/7zip/UI/GUI/CompressDialog.rc
// 这样菜单、对话框、按钮上的用词与 Windows 版完全一致。

import Foundation

enum S {

    // MARK: 程序

    static let appName = "7-Zip File Manager"
    static let fileManager = "7-Zip File Manager"

    // MARK: 工具栏按钮（resource.rc: IDS_ADD / IDS_EXTRACT / ...）

    static var btnAdd: String { L("Add") }
    static var btnExtract: String { L("Extract") }
    static var btnTest: String { L("Test") }
    static var btnCopy: String { L("Copy") }
    static var btnMove: String { L("Move") }
    static var btnDelete: String { L("Delete") }
    static var btnInfo: String { L("Info") }

    /// 智能解压。工具栏按钮、列表右键菜单、Finder 服务三处共用这一条。
    /// 这个名字同时是 Finder 服务菜单里的显示文字，而服务菜单是按显示文字排序的，
    /// 所以「中文以『解压』开头」这件事是靠译文保证的，不能擅自改成别的开头。
    static var extractSmart: String { L("Extract (Smart)") }

    // MARK: 文件菜单（resource.rc: IDM_MENU）

    static var menuFile: String { L("File") }
    static var menuOpen: String { L("Open") }
    static var menuOpenInside: String { L("Open Inside") }
    static var menuOpenInsideAll: String { L("Open Inside *") }
    static var menuOpenInsideOne: String { L("Open Inside #") }
    static var menuOpenOutside: String { L("Open Outside") }
    static var menuView: String { L("View") }
    static var menuEditItem: String { L("Edit") }
    static var menuRename: String { L("Rename") }
    static var menuCopyTo: String { L("Copy To...") }
    static var menuMoveTo: String { L("Move To...") }
    static var menuDelete: String { L("Delete") }
    static var menuSplit: String { L("Split file...") }
    static var menuCombine: String { L("Combine files...") }
    static var menuProperties: String { L("Properties") }
    static var menuCRC: String { L("CRC") }
    static var menuDiff: String { L("Diff") }
    static var menuCreateFolder: String { L("Create Folder") }
    static var menuCreateFile: String { L("Create File") }
    static var menuExit: String { L("Exit") }

    static var menuEdit: String { L("Edit") }
    static var menuSelectAll: String { L("Select All") }
    static var menuDeselectAll: String { L("Deselect All") }
    static var menuInvertSelection: String { L("Invert Selection") }
    static var menuSelect: String { L("Select...") }
    static var menuDeselect: String { L("Deselect...") }
    static var menuSelectByType: String { L("Select by Type") }
    static var menuDeselectByType: String { L("Deselect by Type") }

    static var menuViewMenu: String { L("View") }
    static var menuLargeIcons: String { L("Large Icons") }
    static var menuSmallIcons: String { L("Small Icons") }
    static var menuList: String { L("List") }
    static var menuDetails: String { L("Details") }
    static var menuArrangeByName: String { L("Name") }
    static var menuArrangeByType: String { L("Type") }
    static var menuArrangeByDate: String { L("Date") }
    static var menuArrangeBySize: String { L("Size") }
    static var menuArrangeNoSort: String { L("Unsorted") }
    static var menuFlatView: String { L("Flat View") }
    static var menuTwoPanels: String { L("2 Panels") }
    static var menuTime: String { L("Time") }
    static var menuToolbars: String { L("Toolbars") }
    static var menuArchiveToolbar: String { L("Archive Toolbar") }
    static var menuStandardToolbar: String { L("Standard Toolbar") }
    static var menuLargeButtons: String { L("Large Buttons") }
    static var menuShowButtonsText: String { L("Show Buttons Text") }
    static var menuOpenRootFolder: String { L("Open Root Folder") }
    static var menuUpOneLevel: String { L("Up One Level") }
    static var menuFoldersHistory: String { L("Folders History...") }
    static var menuRefresh: String { L("Refresh") }
    static var menuAutoRefresh: String { L("Auto Refresh") }

    static var menuFavorites: String { L("Favorites") }
    static var menuAddToFavorites: String { L("Add folder to Favorites as") }

    static var menuTools: String { L("Tools") }
    static var menuOptions: String { L("Options...") }
    static var menuBenchmark: String { L("Benchmark") }
    static var menuTempDir: String { L("Delete Temporary Files...") }

    /// Tools -> Options 里的那个复选框（原文见 FileManager/SettingsPage2.rc）
    static var optionsShowDots: String { L("Show \"..\" item") }

    /// 显示隐藏项。没有官方 7-Zip 原文可对（Windows 版 FM 没这一项），自定。
    static var optionsShowHidden: String { L("Show hidden items") }

    static var menuHelp: String { L("Help") }
    static var menuHelpContents: String { L("Contents...") }
    static var menuAbout: String { L("About 7-Zip...") }

    // MARK: 列名（PropertyName.rc）

    static var propPath: String { L("Path") }
    static var propName: String { L("Name") }
    static var propExtension: String { L("Extension") }
    static var propType: String { L("Type") }
    static var propFolder: String { L("Folder") }
    static var propSize: String { L("Size") }
    static var propPackedSize: String { L("Packed Size") }
    static var propAttributes: String { L("Attributes") }
    static var propCTime: String { L("Created") }
    static var propATime: String { L("Accessed") }
    static var propMTime: String { L("Modified") }
    static var propChangeTime: String { L("Changed") }
    static var propSolid: String { L("Solid") }
    static var propCommented: String { L("Commented") }
    static var propEncrypted: String { L("Encrypted") }
    static var propSplitBefore: String { L("Split Before") }
    static var propSplitAfter: String { L("Split After") }
    static var propDictionarySize: String { L("Dictionary") }
    static var propCRC: String { L("CRC") }
    static var propHostOS: String { L("Host OS") }
    static var propFileSystem: String { L("File System") }
    static var propUser: String { L("User") }
    static var propGroup: String { L("Group") }
    static var propBlock: String { L("Block") }
    static var propComment: String { L("Comment") }
    static var propPosition: String { L("Position") }
    static var propMethod: String { L("Method") }
    static var propVersion: String { L("Version") }
    static var propVolume: String { L("Volume") }
    static var propOffset: String { L("Offset") }

    /// Type 列的取值后缀（对应 7-Zip 的 "7z Archive" / "Plain Text File" 这种写法）
    static var propWordArchive: String { L("Archive") }
    static var propWordFile: String { L("File") }

    /// 多选时的计数行（PropertiesDialog.cpp）
    static var propFolders: String { L("Folders") }
    static var propFiles: String { L("Files") }
    static var propItems: String { L("items") }
    static var propMode: String { L("Mode") }
    static var propINode: String { L("iNode") }
    static var propLinks: String { L("Links") }
    static var propHardLink: String { L("Hard Link") }
    static var propSymLink: String { L("Symbolic Link") }
    static var propDevice: String { L("Device") }
    static var propErrors: String { L("Errors") }

    // MARK: 状态栏

    static var nSelectedItems: String { L("{0} object(s) selected") }
    static var computer: String { L("Computer") }

    // MARK: 解压对话框（GUI/ExtractDialog.rc + Extract.rc）

    static var extractTitle: String { L("Extract") }
    static var extractExtractTo: String { L("Extract to:") }
    static var extractPathMode: String { L("Path mode:") }
    static var extractElimDup: String { L("Eliminate duplication of root folder") }
    static var extractOverwriteMode: String { L("Overwrite mode:") }
    static var extractPassword: String { L("Password") }
    static var extractShowPassword: String { L("Show password") }
    static let extractNameEnable = ""
    static var extractSetFolder: String { L("Specify a location for extracted files.") }

    static var pathsFull: String { L("Full pathnames") }
    static var pathsNo: String { L("No pathnames") }
    static var pathsAbs: String { L("Absolute pathnames") }

    static var overwriteAsk: String { L("Ask before overwrite") }
    static var overwriteWithoutPrompt: String { L("Overwrite without prompt") }
    static var overwriteSkipExisting: String { L("Skip existing files") }
    static var overwriteRename: String { L("Auto rename") }
    static var overwriteRenameExisting: String { L("Auto rename existing files") }

    static var progressExtracting: String { L("Extracting") }
    static var progressSkipping: String { L("Skipping") }
    static var cantOpenArchive: String { L("Cannot open file '{0}' as archive") }
    static var cantOpenEncrypted: String { L("Cannot open encrypted archive '{0}'. Wrong password?") }
    static var updateNotSupported: String { L("Update operations are not supported for this archive.") }

    // MARK: Finder 服务（右键菜单）

    /// 服务被调用却没收到文件。正常从 Finder 触发走不到这里，
    /// 但一旦走到就必须说出来 —— 静默什么都不做的表现是「点了没反应」。
    static var svcNoFiles: String { L("No files were passed to the service") }

    // MARK: 解压前的同名冲突 / 归档已存在

    /// 冲突对话框的动作。覆盖 / 改名是新加的，跳过沿用下面的通用按钮文案
    /// （S.skip），免得同一个词出现两条译文。
    static var overwrite: String { L("Overwrite") }
    static var rename: String { L("Rename") }

    static var conflictMessage: String { L("Some items already exist in the destination folder.") }

    /// 「归档已存在」对话框：并入旧包，还是回去改名字
    static var archiveExistsMessage: String { L("The archive already exists. Merge the new files into it, or choose another name.") }
    static var mergeIntoArchive: String { L("Merge into the existing archive") }
    static var chooseAnotherName: String { L("Choose another name") }

    /// 多选压缩时默认归档名里的那个固定词。
    /// 与访达对 Archive 的译法保持一致，所以直接复用 "Archive" 这条。
    static var defaultArchiveWord: String { L("Archive") }

    // MARK: 压缩对话框（GUI/CompressDialog.rc）

    static var addTitle: String { L("Add to archive") }
    static var addArchive: String { L("Archive:") }
    static var addArchiveFormat: String { L("Archive format:") }
    static var addCompressionLevel: String { L("Compression level:") }
    static var addCompressionMethod: String { L("Compression method:") }
    static var addDictionarySize: String { L("Dictionary size:") }
    static var addWordSize: String { L("Word size:") }
    static var addSolidBlockSize: String { L("Solid block size:") }
    /// 固实块下拉里的两项（CompressDialog.rc 的 IDS_COMPRESS_NON_SOLID / IDS_COMPRESS_SOLID）
    static var solidNonSolid: String { L("Non-solid") }
    static var solidFull: String { L("Solid") }
    static var addThreads: String { L("Number of CPU threads:") }
    static var addMemoryCompress: String { L("Memory usage for Compressing:") }
    static var addMemoryDecompress: String { L("Memory usage for Decompressing:") }
    static var addSplitVolumes: String { L("Split to volumes, bytes:") }
    static var addParameters: String { L("Parameters:") }
    static var addOptionsButton: String { L("Options") }
    static var addUpdateMode: String { L("Update mode:") }
    static var addPathMode: String { L("Path mode:") }
    static var addGroupOptions: String { L("Options") }
    static var addGroupEncryption: String { L("Encryption") }
    static var addSfx: String { L("Create SFX archive") }
    static var addShared: String { L("Compress shared files") }
    static var addDeleteAfter: String { L("Delete files after compression") }
    static var addEnterPassword: String { L("Enter password:") }
    static var addReenterPassword: String { L("Reenter password:") }
    static var addShowPassword: String { L("Show password") }
    static var addEncryptionMethod: String { L("Encryption method:") }
    static var addEncryptFileNames: String { L("Encrypt file names") }
    static var addPasswordsDoNotMatch: String { L("Passwords do not match") }

    // Add 对话框里 Options 按钮弹出的那层（CompressOptionsDialog.rc）
    static var addGroupLinks: String { L("Links") }
    static var addGroupTime: String { L("Time") }
    static var addStoreSymLinks: String { L("Store symbolic links") }
    static var addStoreHardLinks: String { L("Store hard links") }
    static var addStoreMTime: String { L("Store modification time") }
    static var addStoreCTime: String { L("Store creation time") }
    static var addStoreATime: String { L("Store last access time") }
    static var addArchiveTimeLatest: String { L("Set archive time to latest file time") }
    static var addPreserveATime: String { L("Do not change source files last access time") }

    static var methodStore: String { L("Store") }
    static var methodFastest: String { L("Fastest") }
    static var methodFast: String { L("Fast") }
    static var methodNormal: String { L("Normal") }
    static var methodMaximum: String { L("Maximum") }
    static var methodUltra: String { L("Ultra") }

    static var updateAdd: String { L("Add and replace files") }
    static var updateUpdate: String { L("Update and add files") }
    static var updateFreshen: String { L("Freshen existing files") }
    static var updateSync: String { L("Synchronize files") }

    static var pathModeRelative: String { L("Relative pathnames") }
    static var pathModeFull: String { L("Full pathnames") }
    static var pathModeAbs: String { L("Absolute pathnames") }

    // MARK: 进度窗口（ProgressDialog2.rc）

    static var progressCompressing: String { L("Compressing") }
    static var progressTesting: String { L("Testing") }
    static var progressScanning: String { L("Scanning...") }
    static var progressCopying: String { L("Copying...") }
    static var progressMoving: String { L("Moving...") }
    static var progressDeleting: String { L("Deleting...") }
    static var progressCombining: String { L("Combining...") }
    static var progressSplitting: String { L("Splitting...") }
    /// 校验归档的结果（Windows 版是弹一个消息框，不留在进度窗口里）
    static var everythingIsOk: String { L("Everything is Ok") }

    static var pTotalSize: String { L("Total size:") }
    static var pProcessed: String { L("Processed:") }
    static var pCompressedSize: String { L("Compressed size:") }
    static var pRemaining: String { L("Remaining time:") }
    static var pElapsed: String { L("Elapsed time:") }
    static var pSpeed: String { L("Speed:") }
    static var pRatio: String { L("Compression ratio:") }
    static var pErrors: String { L("Errors:") }
    static var pCurrentFile: String { L("Current file:") }
    static var pFilesRead: String { L("Files read from disk:") }
    static var pBackground: String { L("Background") }
    static var pPause: String { L("Pause") }

    // MARK: 其它对话框

    static var createFolderName: String { L("Folder name:") }
    static var createFolderDefault: String { L("New Folder") }
    static var createFilePrompt: String { L("File Name:") }
    static var createFileDefault: String { L("New File") }
    static var createFolderError: String { L("Error Creating Folder") }
    static var createFileError: String { L("Error Creating File") }
    static var confirmFileDelete: String { L("Confirm File Delete") }
    static var confirmFolderDelete: String { L("Confirm Folder Delete") }
    static var confirmItemsDelete: String { L("Confirm Multiple File Delete") }
    static var wantToDeleteFile: String { L("Are you sure you want to delete '{0}'?") }
    static var wantToDeleteFolder: String { L("Are you sure you want to delete the folder '{0}' and all its contents?") }
    static var wantToDeleteItems: String { L("Are you sure you want to delete these {0} items?") }
    static var errorDeleting: String { L("Error Deleting File or Folder") }
    static var selectOneFile: String { L("You must select one file") }
    static var selectMask: String { L("Mask:") }
    static var foldersHistory: String { L("Folders History") }
    static var propertiesTitle: String { L("Properties") }
    static var commentTitle: String { L("Comment") }
    static var commentLabel: String { L("Comment:") }
    static var openTypeAllFiles: String { L("All Files") }
    static var optionsTitle: String { L("Options") }
    static var overwriteTitle: String { L("Confirm File Replace") }

    // MARK: 选项里的启动位置与语言（macOS 侧独有，Windows 版的资源里没有对应条目）

    static var optionsStartupLabel: String { L("Open at startup:") }
    static var optionsStartupLast: String { L("Last opened folder") }
    static var optionsStartupHome: String { L("Home folder") }

    static var optionsHomeLabel: String { L("Home folder:") }
    static var optionsChoose: String { L("Choose...") }
    static var optionsHomeMissing: String { L("Folder not found") }

    static var yes: String { L("Yes") }
    static var no: String { L("No") }
    static var yesToAll: String { L("Yes to All") }
    static var noToAll: String { L("No to All") }
    static var autoRename: String { L("Auto Rename") }
    static var cancel: String { L("Cancel") }
    static var ok: String { L("OK") }
    static var close: String { L("Close") }
    static var help: String { L("Help") }
    static var browse: String { L("Browse") }
    static var skip: String { L("Skip") }

    // MARK: 程序菜单（AppKit 的惯例项，7-Zip 的 Windows 资源里没有对应条目）

    static var appHide: String { L("Hide 7-Zip") }
    static var appHideOthers: String { L("Hide Others") }
    static var appShowAll: String { L("Show All") }
    static var appServices: String { L("Services") }
    static var menuNewWindow: String { L("New Window") }

    // MARK: 提示与报错

    static var errorRenaming: String { L("Error Renaming File or Folder") }
    static var mustSelectArchives: String { L("You must select one or more archives") }
    static var createFolderInArchive: String { L("Creating a folder inside an archive would rewrite the whole archive, which 7-Zip does not support.") }
    static var combineTo: String { L("Combine to:") }
    static var cannotCreateOutput: String { L("Cannot create output file") }
    static var cannotReadNamed: String { L("Cannot read {0}") }
    static var selectTwoFiles: String { L("Select two files") }
    static var noDifferences: String { L("No differences") }
    static var itemsDeleted: String { L("{0} item(s) deleted.") }
    static var cannotReadFile: String { L("(cannot read file)") }
    static var hexTitle: String { L("{0} (hex)") }
    static var errorPathNotFound: String { L("The system cannot find the path specified:") }
    static var cancelled: String { L("Cancelled") }
    static var breakSignaled: String { L("Break signaled") }
    static var notEnoughMemory: String { L("Not enough memory") }
    static var calcChecksum: String { L("Calculate checksum") }

    // MARK: 拆分 / 合并

    static var splitTitle: String { L("Split File") }
    static var splitVolumeSize: String { L("Volume size, bytes:") }
    static var btnContinue: String { L("Continue") }

    // MARK: Add 对话框里分卷下拉的预设（只有带说明的那几个需要翻）

    static var volCD650: String { L("650M - CD") }
    static var volCD700: String { L("700M - CD") }
    static var volFat4092: String { L("4092M - FAT") }
    static var volDvd4480: String { L("4480M - DVD") }
    static var volDvdDl8128: String { L("8128M - DVD DL") }
    static var volBd23040: String { L("23040M - BD") }

    // MARK: Add 对话框里 Options 那一栏的动作摘要

    static var optSymLinks: String { L("sym links") }
    static var optHardLinks: String { L("hard links") }
    static var optCTime: String { L("creation time") }
    static var optATime: String { L("access time") }
    static var optNoMTime: String { L("no modification time") }
    static var optArchiveTimeLatest: String { L("archive time = latest") }
    static var optKeepATime: String { L("keep access time") }

    // MARK: 关于对话框

    static var aboutTitle: String { L("7-Zip {0} (macOS)") }
    static var aboutEngine: String { L("Engine: 7-Zip {0}") }
    static var aboutCopyright: String { L("Copyright (C) 1999-2026 Igor Pavlov") }
    static var aboutWarranty: String { L("7-Zip comes with ABSOLUTELY NO WARRANTY.") }
    static var aboutLicense: String { L("Licensed under the GNU LGPL + unRAR restriction.") }

    // MARK: 首次启动：是否设为默认打开方式
    //
    // 只有标题与说明两条需要翻译 —— 勾选框上的文字就是扩展名本身（7z、zip…），
    // 各语言一样，不进译文表。

    static var defaultAppOfferTitle: String { L("Set 7-Zip as the default app for archives?") }
    static var defaultAppOfferBody: String {
        L("Choose the file types you want 7-Zip to open. Disk images are off by default — macOS mounts those when you double-click them.")
    }

    // MARK: 使用说明（Help -> Contents）
    //
    // 这一段是多行长文，键名用 "help.text"，英文原文放在下面的常量里兜底。

    static var helpText: String { L("help.text", helpTextEN) }

    static let helpTextEN = """
    7-Zip File Manager — Help

    Toolbar
      Add        Pack the selected items into an archive (opens "Add to Archive")
      Extract    Unpack the selected archive, or the selected items inside an archive
      Test       Verify the integrity of the selected archive
      Copy       Copy the selected items to another folder
      Move       Move the selected items to another folder
      Delete     Move to Trash (inside an archive, remove from the archive)
      Info       Show properties

    Keyboard
      Enter          Open / descend
      Ctrl+PgDn      Enter the selected archive
      Shift+Enter    Open with the default application
      Backspace      Up one level
      F2             Rename
      F3 / Space     View the file contents
      F4             Edit with the default application
      F5 / F6        Copy to / Move to
      F7             Create a folder
      Del            Delete
      F9             Toggle one/two panels
      Tab            Switch between panels
      Ctrl+1..4      Large icons / Small icons / List / Details
      Cmd+R          Refresh
      Cmd+A          Select all
      Cmd+I          Properties

    Inside an archive
      Double-click a folder to descend into it; double-click a nested archive to
      unpack it into a temporary folder and open it.

    Context menu
      Right-click the file list for file operations; right-click a column header
      to choose which columns to show and how to sort.
    """

}

// MARK: - 压缩等级 / 更新模式 / 路径模式的枚举

/// 压缩级别。rawValue 直接就是传给引擎的 -mx 值：
/// CompressDialog.cpp 的 g_Levels 里只有 0/1/3/5/7/9 这几档有名字，2/4/6/8 是空的。
enum CompressionLevel: Int, CaseIterable {
    case store = 0, fastest = 1, fast = 3, normal = 5, maximum = 7, ultra = 9

    var title: String {
        switch self {
        case .store: return S.methodStore
        case .fastest: return S.methodFastest
        case .fast: return S.methodFast
        case .normal: return S.methodNormal
        case .maximum: return S.methodMaximum
        case .ultra: return S.methodUltra
        }
    }
}

enum UpdateMode: Int, CaseIterable {
    case add = 0, update, freshen, sync

    var title: String {
        switch self {
        case .add: return S.updateAdd
        case .update: return S.updateUpdate
        case .freshen: return S.updateFreshen
        case .sync: return S.updateSync
        }
    }

    /// 对应 7zz 的参数（7-Zip 的 GUI 用 -u<mode> 表达同样的语义）
    var arguments: [String] {
        switch self {
        case .add: return ["-u-"]          // 只加新文件，不动已存在的
        case .update: return []            // 默认：更新已存在 + 追加新文件
        case .freshen: return ["-up0q3r2x2y2z1w2"]
        case .sync: return ["-u-", "-up1q1r1x1y1z1w1"]
        }
    }
}

enum ExtractPathMode: Int, CaseIterable {
    case full = 0, noPaths, absolute

    var title: String {
        switch self {
        case .full: return S.pathsFull
        case .noPaths: return S.pathsNo
        case .absolute: return S.pathsAbs
        }
    }
}

enum ExtractOverwriteMode: Int, CaseIterable {
    case ask = 0, overwrite, skip, rename, renameExisting

    var title: String {
        switch self {
        case .ask: return S.overwriteAsk
        case .overwrite: return S.overwriteWithoutPrompt
        case .skip: return S.overwriteSkipExisting
        case .rename: return S.overwriteRename
        case .renameExisting: return S.overwriteRenameExisting
        }
    }

    /// ask 没有对应的命令行开关——GUI 自己弹窗问，不交给引擎
    var argument: String? {
        switch self {
        case .ask: return nil
        case .overwrite: return "-aoa"
        case .skip: return "-aos"
        case .rename: return "-aot"
        case .renameExisting: return "-aou"
        }
    }
}

// MARK: - 文件列表的列定义
//
// 列顺序与默认可见性照抄 FileManager/PanelItems.cpp：
// 文件系统里的默认列宽 Name=160、其余=100（GetColumnWidth）。

struct ColumnSpec {
    let id: String
    let title: String
    let width: CGFloat
    let alignRight: Bool
    /// 进入归档后才出现的列（Windows 版里由归档自身报告的属性决定）
    let archiveOnly: Bool

    init(_ id: String, _ title: String, _ width: CGFloat,
         alignRight: Bool = false, archiveOnly: Bool = false) {
        self.id = id
        self.title = title
        self.width = width
        self.alignRight = alignRight
        self.archiveOnly = archiveOnly
    }
}

enum Columns {
    static let name = "name"
    static let size = "size"
    static let packedSize = "packedSize"
    static let mtime = "mtime"
    static let ctime = "ctime"
    static let atime = "atime"
    static let attributes = "attributes"
    static let crc = "crc"
    static let method = "method"
    static let encrypted = "encrypted"
    static let comment = "comment"
    static let folder = "folder"
    static let solid = "solid"
    static let block = "block"
    static let hostOS = "hostOS"
    static let version = "version"
    static let offset = "offset"

    /// 文件系统里可选的列（对应 FSFolder.cpp 的属性表 + PanelItems.cpp 的默认可见性）
    static let fileSystem: [ColumnSpec] = [
        ColumnSpec(name, S.propName, 160),
        ColumnSpec(size, S.propSize, 100, alignRight: true),
        ColumnSpec(packedSize, S.propPackedSize, 100, alignRight: true),
        ColumnSpec(mtime, S.propMTime, 100),
        ColumnSpec(ctime, S.propCTime, 100),
        ColumnSpec(atime, S.propATime, 100),
        ColumnSpec(attributes, S.propAttributes, 100),
        ColumnSpec(comment, S.propComment, 100),
    ]

    /// 归档里可选的列
    static let archive: [ColumnSpec] = [
        ColumnSpec(name, S.propName, 160),
        ColumnSpec(size, S.propSize, 100, alignRight: true),
        ColumnSpec(packedSize, S.propPackedSize, 100, alignRight: true),
        ColumnSpec(mtime, S.propMTime, 100),
        ColumnSpec(ctime, S.propCTime, 100),
        ColumnSpec(atime, S.propATime, 100),
        ColumnSpec(attributes, S.propAttributes, 100),
        ColumnSpec(crc, S.propCRC, 100),
        ColumnSpec(method, S.propMethod, 140),
        ColumnSpec(encrypted, S.propEncrypted, 80),
        ColumnSpec(comment, S.propComment, 100, archiveOnly: true),
        ColumnSpec(solid, S.propSolid, 60, archiveOnly: true),
        ColumnSpec(block, S.propBlock, 60, archiveOnly: true),
        ColumnSpec(hostOS, S.propHostOS, 80, archiveOnly: true),
        ColumnSpec(version, S.propVersion, 60, archiveOnly: true),
        ColumnSpec(offset, S.propOffset, 80, alignRight: true, archiveOnly: true),
    ]

    /// 文件系统里的默认可见列：Name / Size / Modified / Created。
    /// PanelItems.cpp 的 GetColumnVisible 明确把 kpidPackSize、kpidAttrib、
    /// kpidATime、kpidChangeTime 对文件系统关掉了，所以这几列默认不出现。
    /// 列头右键可以随时增删，和 Windows 版一样。
    static let hiddenByDefaultInFileSystem: Set<String> = [
        packedSize, atime, attributes, comment,
    ]

    /// 归档里默认可见：Name / Size / Packed Size / Modified / CRC / Method / Encrypted
    static let hiddenByDefaultInArchive: Set<String> = [
        ctime, atime, attributes, comment, solid, block, hostOS, version, offset,
    ]

    /// 各列最宽可能的取值，用来量出「这列至少要有多宽」。
    /// 7-Zip 的列宽（kpidName 160、其余 100）是按 Segoe UI 9pt 定的，
    /// 同一串文字在 macOS 系统字体下要宽得多，照搬 100 会把时间截成
    /// "2026-09-10 1..."，所以这里按实际字重量一遍取较大者。
    static func sampleValue(_ id: String) -> String {
        switch id {
        case name: return "MMMMMMMMMMMMMMM"
        case size, packedSize, offset: return "9 999 999 999 999"
        case mtime, ctime, atime: return "2026-09-10 13:45"
        case attributes: return "-rwxr-xr-x"
        case crc: return "00000000 00000000"
        case method: return "LZMA2:24m"
        case encrypted: return "++"
        case comment: return "mmmmmmmmmmmmmm"
        case solid, block, hostOS, version: return "mmmm"
        default: return ""
        }
    }
}
