#!/bin/bash
# 交互自检：编译合成事件/查窗口的辅助工具，然后跑三轮端到端验证。
#
#   1) 面板交互（tools/uiprobe.py）：单击选中、双击进目录、返回上一级、
#      菜单与工具栏的可用状态、双击归档、右键菜单、地址栏回车。
#   2) Finder 右键菜单（tools/svcprobe.py）：各服务逐个从冷启动触发，
#      核对文件动作、该弹的窗口，以及**主窗口不该冒出来**。
#   3) 多语言（tools/l10nprobe.py）：把 App 按 11 种语言各起一次，逐条核对
#      界面文案落在哪种语言上，并检查系统服务菜单是不是同一种语言。
#
# 用法：scripts/verify-ui.sh
# 也可以指定别的 App 包：ZIPFM_BUNDLE="/Volumes/.../7-Zip File Manager.app" scripts/verify-ui.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUNDLE="${ZIPFM_BUNDLE:-$ROOT/build/7-Zip File Manager.app}"
APP="$BUNDLE/Contents/MacOS/7-Zip File Manager"
if [ ! -x "$APP" ]; then
    echo "找不到可执行文件：$APP" >&2
    echo "先跑 scripts/build-app.sh" >&2
    exit 1
fi

echo "==> 编译辅助工具"
swiftc -O -o build/uiclick tools/uiclick.swift                    # 往进程投键盘事件
swiftc -O -o build/svcrun  tools/svcrun.swift  -framework AppKit  # 从外部触发一次服务
swiftc -O -o build/winlist tools/winlist.swift -framework AppKit  # 列出某进程的窗口

# serviceslist 要包成 .app 再跑：服务菜单里显示的名字是按**调用方**的语言挑的，
# 裸可执行文件没有本地化元数据（Bundle.main.preferredLocalizations 只能是开发语言），
# 读出来永远是英文原文，而访达是 App、挑的是系统语言那一份。本地化语言表直接从
# 待测 bundle 的 Info.plist 抄，不另立一份。
SVCAPP="$ROOT/build/serviceslist.app"
mkdir -p "$SVCAPP/Contents/MacOS"
swiftc -O -o "$SVCAPP/Contents/MacOS/serviceslist" tools/serviceslist.swift -framework AppKit
cp "$BUNDLE/Contents/Info.plist" "$SVCAPP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable serviceslist' \
                         -c 'Set :CFBundleIdentifier com.example.serviceslist-probe' \
                         -c 'Set :CFBundleName serviceslist' \
                         -c 'Delete :NSServices' \
                         -c 'Delete :NSDocumentTypes' \
                         -c 'Delete :CFBundleIconFile' \
                         "$SVCAPP/Contents/Info.plist" >/dev/null 2>&1 || true

rc=0
skipped=""
echo
echo "==> 面板交互回归：$BUNDLE"
ZIPFM_APP="$APP" python3 tools/uiprobe.py
case $? in
    0)  ;;
    # 77 = 窗口在但拿不到前台，合成点击会被系统丢掉，见 tools/uiprobe.py
    77) skipped="面板交互回归" ;;
    *)  rc=1 ;;
esac

echo
echo "==> Finder 服务回归：$BUNDLE"
ZIPFM_BUNDLE="$BUNDLE" python3 tools/svcprobe.py || rc=1

echo
echo "==> 多语言回归：$BUNDLE"
python3 tools/l10nprobe.py "$BUNDLE" || rc=1

echo
if [ "$rc" != 0 ]; then
    echo "有失败项，见上"
elif [ -n "$skipped" ]; then
    # 变量后面紧跟全角括号时，bash 会把括号的第一个字节当成变量名的一部分，
    # 于是报 "skipped（: unbound variable" —— 必须写 ${skipped}
    echo "已执行的回归全部通过；未执行：${skipped}（环境没有可用的前台会话）"
else
    echo "三轮都通过"
fi
exit "$rc"
