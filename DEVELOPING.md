# 开发笔记

面向改这个 App 的人。安装与使用见 [README.md](README.md)。

## 目录

```
src/                  Swift 源码（AppKit，无第三方依赖）
resources/            Info.plist、图标、11 种语言的文案
scripts/              构建、安装、打包、自检
tools/                构建期脚本（Python）与自检辅助工具（Swift）
vendor/               7-Zip 官方源码，构建时下载，不签入
build/                产物
screenshots/          早期截图，含本机路径，已排除在仓库外
images/               README 用的配图
```

## 构建

```
scripts/fetch-source.sh     # 下载 7-Zip 26.03 源码，校验 SHA256，解压到 vendor/
scripts/build-engine.sh     # 编译 7zz（arm64 + x86_64，再 lipo 成 universal）
scripts/build-app.sh        # 编译 Swift 源码，装配 .app，写 Info.plist、图标、.lproj
scripts/install.sh          # 装到 /Applications 并注册 Finder 服务
scripts/build-dmg.sh        # 打成可分发的 DMG
```

`scripts/config.sh` 放着共用变量，其中 `MIN_OS=13.0` 是构建目标的最低系统版本。

**为什么下限卡在 13.0**：x86_64 切片在当前工具链下链接不到 13.0 以下。
CommandLineTools 里的 `libswiftCompatibility56.a` 只有 arm64 切片，而编译器对低于 13.0
的目标会强制加载它（库里是 Swift 并发的 TaskLocal / task 覆盖表，与非并发代码无关，
但链接器仍要有这个切片才肯放行）。实测：x86_64 @12.6 报 Undefined symbols，@13.0 通过；
arm64 @11.0 就能过。换成含 x86_64 切片的完整 Xcode 工具链，下限可以降到 11.0。

`tools/` 里几个构建期脚本：`mkinfo.py` 生成 Info.plist（含 `NSServices` 声明）、
`mkarchive_types.py` 从引擎源码里抽出扩展名表、`mkicons.py` / `mkicns.py` 从 7-Zip
官方素材合成 App 图标与工具栏图标、`mkl10n.py` 把 `resources/l10n/<语言>.strings`
装配成 App 包里的 `.lproj`、`mkdmg.py` 画 DMG 的背景图并写窗口布局。

## 自检

```
scripts/verify-ui.sh
```

它会先编译几个辅助工具（`svcrun`、`winlist`、`uiclick`、`serviceslist`），然后跑三轮：

- **面板交互**（`tools/uiprobe.py`，29 条）：单击选中、双击进目录、返回上一级四个入口、
  工具栏与菜单的可用状态、拖动框选、`⌥` 拖动、拖进窗口弹压缩对话框、双击归档进包、
  右键菜单、地址栏回车。
- **Finder 右键菜单**（`tools/svcprobe.py`，22 条）：5 个服务逐个从冷启动触发，
  核对文件动作、该弹的对话框、做完后窗口与进程都收掉，以及主窗口不该冒出来。
  「解压（智能）」的三条分支（单文件 / 单目录 / 多顶层项）各有一条用例。
- **多语言**（`tools/l10nprobe.py`）：把 App 按 11 种语言各起一次，问它一句 `lang`，
  让它把 bundle 里那份 `.lproj` 的每一条文案都查一遍报回来，再和
  `resources/l10n/<语言>.strings` 逐条对；另外核对 `zh-Hans-CN`、`zh-Hant-TW`、`xx-YY`
  这些标签的回退，以及系统「服务」菜单里显示的是不是同一种语言。

面板那轮固定用 `-AppleLanguages "(en)"` 起 App：它的断言看的是菜单条目的文字，
跟着系统语言跑就会随机器变。「界面确实被翻译了」由多语言那轮负责。

多语言那轮不直接读 `.lproj` 文件 —— 文件在不在，和「系统在这个语言下到底挑中哪一份」
是两件事，只有让 App 自己把每条文案查一遍才算证据。

服务那轮由 LaunchServices 另起进程，面板那轮的方法用不上，所以走的是
「把文件放进通用粘贴板 → 按服务名请求系统执行」（`tools/svcrun`），
再用 `tools/winlist` 看它到底弹了什么窗口 —— 窗口标题要屏幕录制权限，所以只看尺寸和层级。

它用的是 `Info.plist` 里的英文名（`Extract Here`）。实测 `NSPerformService` 认的就是
这个名字：本地化只改菜单上显示什么，不改查找用的键。所以在中文系统下这轮照样跑得通，
也不用跟着系统语言改参数 —— 右键菜单显示成哪种语言由多语言那轮验。

## 截图

App 能自己把窗口画成 PNG，走的是 AppKit 的 `view.cacheDisplay`，
不需要屏幕录制权限，也不用把窗口摆到前台：

```
"build/7-Zip File Manager.app/Contents/MacOS/7-Zip File Manager" \
    --capture /tmp/main.png --delay 2 --open /tmp/Demo --panels 1
```

`--dialog <名字>` 可以把某个对话框直接调起来一起截（支持 `add`、`addoptions`、
`options`、`about`、`extract`、`properties`、`split`、`combine`、`diff` 等）。
窗口多于一个时，每个窗口各存一份，文件名带 `-<序号>-<窗口标题>` 后缀。

另有 `--dump-layout`（把视图树连同各自的实际尺寸打到 stderr）和
`--dump-menu`（菜单栏 + 加速键）两个开关。布局对不上源码时，看这两个比看截图像素准。

## 服务菜单

### 顺序

`Info.plist` 里 `NSServices` 的声明顺序不起作用。系统服务子菜单里同一 App 的条目排成一组，
**组内按本地化之后的菜单文字排序**。中文界面下「解压（智能）」靠「解压」二字排第一，
就是这个原因 —— 改名字的时候要留意这一点。

### 语言

这几条服务名显示成哪种语言，由**读菜单的那个进程**决定。读菜单的是访达，
所以实际跟着系统语言走，跟 App 里选的语言无关。pbs 缓存里每条服务存着多份译文
（`default` / `zh_CN` / `zh-Hans` …），访达按自己的本地化挑一份。

顺带一个陷阱：**裸命令行可执行文件没有本地化元数据**，`Bundle.main.preferredLocalizations`
只会是开发语言（en），永远读到英文原文。所以自检里那个读服务名的工具
（`tools/serviceslist.swift`）必须包成 `.app` 才能读出访达看到的名字 ——
`scripts/verify-ui.sh` 里就是这么干的。

### 改完要刷缓存

`pbs -flush` 实测无效（报 `XPC message error`）。有效的是删缓存再重启 pbs：

```
rm -f ~/Library/Preferences/com.apple.ServicesMenu.Services.plist \
      ~/Library/Caches/com.apple.nsservicescache.plist
killall pbs
```

同一个 bundle id 有多份副本（废纸篓里、以前挂过的 DMG 卷）会让菜单出现重名条目，
系统会加 ` (App 名)` 后缀来区分。清掉的办法是按路径注销再加 `-gc`：

```
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSR" -u "/废弃路径/7-Zip File Manager.app"
"$LSR" -gc
```

`~/.Trash` 受 TCC 保护，`-u` 可能报 `-10814`；那种情况清空废纸篓即可。

### 改代码时别破的规矩

- `NSApp.servicesProvider` 必须在 `applicationWillFinishLaunching` 之前设好。
  设晚了（比如放在 `applicationDidFinishLaunching` 里），这次服务请求已经派发完，
  会被整个丢掉：App 起来了、主窗口弹出来，然后什么都不发生。
- **服务方法里任何「不做事」的分支都必须有反馈。** 静默 `return` 的表现和上面那条
  一模一样，用户分不出是哪种，只能得到「点了没反应」。选中的东西没法处理时要弹出提示。
- 服务调用不该把主窗口带出来：判定的第一件事就是置位「正在服务」，再去判断其余条件。
  真晚了（已经弹出来了），把它 `orderOut` 掉；别用 `close`，那会触发
  「最后一个窗口关闭即退出」，而服务那边还没建出进度窗口。
- `Extract Here` 这类明确指令不要用扩展名表去否决用户。表只是给列表配图标用的，
  认不出来时把文件交给引擎，让引擎报它自己的错 —— 那张表读不出来时
  （`archive_types.json` 缺失）也不会变成「什么都认不出，于是什么都不做」。
- **操作成功时进度窗口要自己关掉**（出错才留着）。留一个停在 0% 的窗口在那儿，
  用户会以为操作卡住了：解压几十 MB 的包常常快到来不及产生第二行进度
  （引擎只在百分比变化时才打印），那个窗口里的数字本来就不会动。
  它作为最后一个窗口关掉时 App 会跟着退出，这正是从右键菜单调起来时应有的样子。
- **引擎刷进度用的是退格，不是回车。** `7zz` 更新进度那一行是「先发一串 `\x08` 退回去，
  再写新内容盖住」，全程不换行；只按 `\r` / `\n` 切段的话，整条进度会一直堆在行缓冲里
  出不来，进度条就停在 0%（`EngineTask.consume` 改成逐字符处理退格）。
  而且只认**退格块的第一格**：跟着的每一格都会把文件名一节一节吃掉（`big.bin` 退成 `b`）。
  还有，stdout / stderr 两个管道各有自己的 handler、在不同队列上并发调进解析，
  整段解析要一起进锁 —— 只锁缓冲区读写会撞在同一个 `String` 上（实测 SIGSEGV）。

## 自检通道

面板交互那轮通过 `--automation` 从 stdin 收命令，鼠标动作把 `NSEvent` 排进 App
自己的事件队列、由主 run loop 正常派发（`NSApplication.sendEvent` → 窗口 →
`hitTest` → 视图），和真实鼠标同一条路。九条别踩的坑：

- 不要改成在命令处理里同步调 `sendEvent`：表格的 `mouseDown` 会自己进鼠标跟踪
  循环去取队列里的后续事件，两边抢同一个队列，双击会时灵时不灵。
- 排完事件不能立刻返回。事件还在队列里等 run loop 派发，这期间 App 一旦不在前台，
  鼠标事件被系统丢掉，表现是命令回了 `ok` 而界面毫无反应。所以投递之后要守着前台、
  把 run loop 转到事件派发出去为止。真实点击没有这个窗口（按下去时窗口本来就是前台的）。
- 从终端起进程时窗口拿不到前台会话，外部用 `CGEvent` 合成的鼠标事件会被系统丢掉，
  所以点击只能在 App 进程内合成。
- 拖动用 `drag row <从行> <到行> [alt]` / `drag empty <到行>` 合成。别指望事后马上读到
  选中项：命令这一段是同步执行的，事件要等它返回之后才由主 run loop 送进窗口，
  紧接着读到的还是上一次的状态。要单独用 `state` 读。
- **合成拖动过后必须自己收尾。** 带上 `alt` 的拖动会真的起一条拖放会话，而松手那一半
  只进了 App 自己的事件队列，窗口服务器那条会话收不了尾：屏幕上会留下一个跨整屏的
  拖动影像窗口（`CGWindowList` 里 `layer=500`、尺寸等于整块屏幕），它接管鼠标，之后
  每一次点击都被它吃掉 —— 表现出来是「单击选不中、双击不换目录」，接着每条断言连着挂，
  看着像一堆功能同时坏了。发一个 `Esc`（键码 53）把它取消掉，界面立刻恢复。
- **落点语义（拖进窗口 = 压缩）用 `drop <路径>…` 验，不用合成拖动。** 上面那条决定了
  合成拖动根本触发不了 `drop`；`drop` 命令直接把路径交给拖放的处理入口，走的仍是真实
  链路（面板 → `onFilesDropped` → 主窗口的 `handleDrop`）。它弹的是模态对话框，会卡住
  这条命令的回包，所以要 `send` 之后用带超时的读去取回包，别同步等。
- **路径要加引号**（`drop "/Users/…/笔记 一.txt"`）。参数是按空格切的，文件名带空格时
  不加引号会被拆成好几个路径，引擎那边就变成「文件不存在」。
- **`unzip <归档>…` 走的是列表里「解压（智能）」那条路**（`wc.smartExtract`），
  用来在自检里看解压侧的进度和落点；`drop` 只覆盖压缩侧。
- 对话框挡住的时候**不要发还等着回包的命令**：主队列被那条 `drop` 占着，读回包会一直挂。
  要确认「弹了没有」，用 `winlist` 数窗口；要确认「名字是什么」，直接看按完确定之后
  真的产出了什么文件 —— 比截图稳。

自检把每次点击当时的前台状态（`active` / `key` / 派发窗口内掉出前台的次数）一起打出来，
失败时会附上。看到失败先看这几个数：`active=0` 就是环境没把 App 摆到前台，
不是界面逻辑的问题。每条点击断言前面会先回到一个已知目录再点，
这样一条失败不会把后面每条都带歪。

## 列表里的框选与拖动

**框选（拖动扩选）是 `NSTableView` 自己做的**，不是我们写的；但只在不实现
`tableView(_:pasteboardWriterForRow:)` 时才轮到它。一旦实现了这个方法
（哪怕像现在这样按 `⌥` 才返回内容），表格就会优先起拖放，不按 `⌥` 时返回 nil 才会退回框选。

另外不要试着重写 `mouseDragged` / `mouseUp` 来给框选加个选择框 —— 拖动整段发生在
`NSTableView` 自己的跟踪循环里，这两个回调不会被调用，`NSEvent.addLocalMonitorForEvents`
也收不到那些事件。

## 测试前先确认服务落到哪一份 App 上

同一个 bundle id 可以有好几份副本，LaunchServices 会自己挑（实测优先 `/Applications` 里那份）。
要是只重建了 `build/`，服务那轮测的就是机器上装的旧版本，结论全错。查法：

```
pgrep -f "7-Zip File Manager" | while read p; do ps -p $p -o comm=; done
```

要让测试打到 `build/` 那份，得先把 `/Applications` 那份挪开
（`lsregister -u` 单注销不够，实测仍会挑 `/Applications`）。

## 本地化

译文与 Windows 版 7-Zip 逐条对齐 —— 对得上的直接取自官方语言包
（[7-zip.org](https://www.7-zip.org) 安装程序里的 `Lang/*.txt`，`en.ttt` 是对照的英文原文，
各语言文件行号与它一一对应）；官方没有的 macOS 侧文案（服务菜单名字、`Hide Others`
这类 AppKit 惯例项、启动位置 / 主路径这些设置项）按同样的用词补齐。官方译文带的
Windows 加速键（`&File`、`复制到(&C)`）在导入时去掉，macOS 用的是 keyEquivalent。

翻译文件在 `resources/l10n/<语言>.strings`（UTF-8，键就是英文原文）。
改完跑一次 `tools/mkl10n.py` 装配成 App 包里的 `.lproj`，构建脚本会自动调用它。

服务菜单的译文放在 `<语言>.lproj/ServicesMenu.strings`，中文译文必须以「解压」开头
（见上面「服务菜单 → 顺序」）。

## 改完记得同步客户端

改完源码只重建、不覆写安装位置的话，打开 App 看到的还是旧版本：

```
ditto "build/7-Zip File Manager.app" "/Applications/7-Zip File Manager.app"
shasum -a 256 "build/7-Zip File Manager.app/Contents/MacOS/7-Zip File Manager" \
              "/Applications/7-Zip File Manager.app/Contents/MacOS/7-Zip File Manager"
```

两处哈希一致才算同步完成。换了可执行文件之后服务菜单的缓存也要刷一次（见上）。
