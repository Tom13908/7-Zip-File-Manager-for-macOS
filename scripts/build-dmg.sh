#!/bin/bash
# 把 App 打包成可分发安装的 DMG。
#
# 产出：build/7-Zip File Manager <版本>.dmg
#   挂载后是一个标准的两图标窗口：左边 App，右边 Applications 快捷方式，
#   拖过去就装好了。
#
# 窗口那一套（大小、图标位置、背景箭头）由 tools/mkdmg.py 写进卷里的
# .DS_Store，不是靠 AppleScript 指挥 Finder —— 那条路在本机实测被 TCC 挡掉
# （-10004 权限违例）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VOLNAME="7-Zip File Manager"
APP_NAME="7-Zip File Manager"
BUILD="$ROOT/build"
APP="$BUILD/$APP_NAME.app"

# 清掉中间产物和旧产物。
#
# 不能直接 rm：同一轮里累计删掉的文件够多之后（卷里那份 App 副本有 400 多个文件），
# 系统会要求先确认，rm 于是失败 —— set -e 下整个构建就断在最后一步，DMG 生不出来。
# 拦下来就先扔废纸篓，再不行就留着并提示，绝不因为删不掉而中断出包。
discard() {
    for p in "$@"; do
        [ -e "$p" ] || continue
        rm -rf "$p" 2>/dev/null && continue
        if command -v trash >/dev/null 2>&1 && trash "$p" 2>/dev/null; then
            continue
        fi
        echo "    注意：$p 没能删掉，留着了，回头自己清一下" >&2
    done
}

if [ ! -d "$APP" ]; then
    echo "没有找到 ${APP}，先跑 scripts/build-app.sh" >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
              "$APP/Contents/Info.plist" 2>/dev/null || echo "0.0")
OUT="$BUILD/$APP_NAME $VERSION.dmg"
WORK="$BUILD/dmg-work"
TMP_DMG="$BUILD/dmg-rw.dmg"

# ------------------------------------------------------------ 打包依赖

# 三个库只在这一步用，装在 build/ 下的 venv 里，不碰系统环境。
PY="${PYTHON:-python3}"
VENV="$BUILD/_dmgvenv"
if ! "$PY" -c "import ds_store, mac_alias, PIL" 2>/dev/null; then
    if [ ! -x "$VENV/bin/python" ]; then
        echo "==> 建打包用的虚拟环境 $VENV"
        "$PY" -m venv "$VENV"
        "$VENV/bin/pip" install --quiet --upgrade pip
        "$VENV/bin/pip" install --quiet ds_store mac_alias pillow
    fi
    PY="$VENV/bin/python"
fi
echo "==> 打包用的 python：$PY"

# ------------------------------------------------------------ 装内容

echo "==> 准备卷内内容"
discard "$WORK"
mkdir -p "$WORK/.background"
ditto "$APP" "$WORK/$APP_NAME.app"
ln -s /Applications "$WORK/Applications"
"$PY" tools/mkdmg.py background "$WORK/.background"

# ------------------------------------------------------------ 可写镜像

echo "==> 创建可写镜像"
discard "$TMP_DMG"
hdiutil create -quiet -srcfolder "$WORK" -volname "$VOLNAME" \
    -fs HFS+ -format UDRW -ov "$TMP_DMG"

MNT="/Volumes/$VOLNAME"
if [ -d "$MNT" ]; then
    hdiutil detach "$MNT" -quiet || true
fi

echo "==> 挂载并写窗口布局"
hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$MNT" "$TMP_DMG"
"$PY" tools/mkdmg.py layout "$MNT"

sync
hdiutil detach "$MNT" -quiet

# ------------------------------------------------------------ 压缩输出

echo "==> 压缩"
discard "$OUT"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "${OUT%.dmg}" -quiet
discard "$TMP_DMG" "$WORK"

echo
echo "完成：$OUT"
ls -lh "$OUT" | awk '{print "     体积 " $5}'
hdiutil verify "$OUT" >/dev/null 2>&1 && echo "     校验通过" || echo "     校验失败"
