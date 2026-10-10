#!/bin/bash
# 构建 "7-Zip File Manager.app"（universal：arm64 + x86_64）。
#
# 产出：build/7-Zip File Manager.app
#   内容里自带 7zz 引擎（Contents/Resources/7zz），装到别的机器上不需要另外装东西。
#   两个架构的切片和 Info.plist 声明的最低系统版本必须一致，脚本末尾会校验。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
. "$ROOT/scripts/config.sh"

APP_NAME="7-Zip File Manager"
BUILD="$ROOT/build"
APP="$BUILD/$APP_NAME.app"
ENGINE="$ROOT/vendor/7zip-26.03/CPP/7zip/Bundles/Alone2/_o/7zz"
PY="${PYTHON:-python3}"

# ---------------------------------------------------------------- 前置资源

if [ ! -x "$ENGINE" ]; then
    echo "找不到 7zz 引擎（${ENGINE}）" >&2
    echo "先跑：scripts/fetch-source.sh && scripts/build-engine.sh" >&2
    exit 1
fi

if [ ! -f resources/icons/app/fm_48@2x.png ]; then
    echo "==> 生成图标资源"
    "$PY" tools/mkicons.py
fi

if [ ! -f resources/archive_types.json ]; then
    echo "==> 生成归档格式表"
    "$PY" tools/mkarchive_types.py
fi

echo "==> 生成 Info.plist"
"$PY" tools/mkinfo.py

echo "==> 装配本地化资源（<语言>.lproj）"
"$PY" tools/mkl10n.py

echo "==> 生成 AppIcon.icns"
"$PY" tools/mkicns.py

# ---------------------------------------------------------------- 编译

# 下限为什么是 13.0：x86_64 切片在当前工具链下链接不到 13.0 以下。
# CommandLineTools 里的 libswiftCompatibility56.a 只有 arm64 切片，而编译器对低于 13.0
# 的目标会强制加载它（库里是 Swift 并发的 TaskLocal / task 覆盖表，与非并发代码无关，
# 但链接器仍要有这个切片才肯放行）。实测：x86_64 @12.6 报 Undefined symbols，@13.0 通过；
# arm64 @11.0 就能过。换成含 x86_64 切片的完整 Xcode 工具链，下限可以降到 11.0。
echo "==> 编译 Swift 源码（arm64 + x86_64，最低 macOS ${MIN_OS}）"
mkdir -p "$BUILD"
for arch in arm64 x86_64; do
    echo "    $arch"
    swiftc -O -whole-module-optimization \
        -target "$arch-apple-macos$MIN_OS" \
        -o "$BUILD/7zip-fm.$arch" \
        src/*.swift \
        -framework AppKit
done
lipo -create "$BUILD/7zip-fm.arm64" "$BUILD/7zip-fm.x86_64" -output "$BUILD/7zip-fm"

# ---------------------------------------------------------------- 组装

echo "==> 组装 $APP_NAME.app"
# 不能直接 rm -rf 一个 .app：系统会把副本丢进废纸篓（实测每构建一次多一份，约 7 MB）。
# 先改成不带 .app 的名字再删，系统就不把它当应用处理。
# 名字带时间戳和 pid：万一旧目录没删掉，下次的 mv 也不会把新 App 塞进它里面。
# 删不掉不当作构建失败 —— 有些环境会拦批量删除，那不该挡住出包。
if [ -e "$APP" ]; then
    mv "$APP" "$BUILD/old-$(date +%Y%m%d-%H%M%S)-$$"
fi
for stale in "$BUILD"/old-*; do
    [ -e "$stale" ] || continue
    rm -rf "$stale" 2>/dev/null || true
    [ -e "$stale" ] && echo "    注意：$stale 没能删掉，构建照常，回头自己清一下就行" >&2
done
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD/7zip-fm" "$APP/Contents/MacOS/$APP_NAME"
cp resources/Info.plist "$APP/Contents/"
cp resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R resources/icons "$APP/Contents/Resources/"
cp resources/archive_types.json "$APP/Contents/Resources/"
cp -R resources/lproj/. "$APP/Contents/Resources/"
cp "$ENGINE" "$APP/Contents/Resources/7zz"

chmod +x "$APP/Contents/MacOS/$APP_NAME" "$APP/Contents/Resources/7zz"

# 二进制里的调试/构建痕迹清掉，签名也不会因此失效（在签名之前做）
strip -S "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || true
strip -S "$APP/Contents/Resources/7zz" 2>/dev/null || true

echo "==> 临时签名"
codesign --force --sign - "$APP"

# ---------------------------------------------------------------- 校验

minos() {  # $1=文件 $2=架构
    otool -arch "$2" -l "$1" | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; exit}'
}

echo "==> 校验"
PLIST_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$APP/Contents/Info.plist")"
lipo -info "$APP/Contents/MacOS/$APP_NAME"
lipo -info "$APP/Contents/Resources/7zz"
for arch in arm64 x86_64; do
    printf "    %-7s 主程序 minos=%s  引擎 minos=%s\n" "$arch" \
        "$(minos "$APP/Contents/MacOS/$APP_NAME" "$arch")" \
        "$(minos "$APP/Contents/Resources/7zz" "$arch")"
done
echo "    Info.plist LSMinimumSystemVersion=$PLIST_OS"

for arch in arm64 x86_64; do
    for f in "$APP/Contents/MacOS/$APP_NAME" "$APP/Contents/Resources/7zz"; do
        got="$(minos "$f" "$arch")"
        if [ "$got" != "$PLIST_OS" ]; then
            echo "不一致：$(basename "$f") 的 ${arch} 切片 minos=${got}，Info.plist 写的是 ${PLIST_OS}" >&2
            exit 1
        fi
    done
done

echo
echo "完成：$APP"
du -sh "$APP" | awk '{print "     体积 " $1}'
