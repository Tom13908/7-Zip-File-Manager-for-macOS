#!/bin/bash
# 编译 7zz 引擎，产出 arm64 + x86_64 的 universal 可执行文件：
#   vendor/7zip-26.03/CPP/7zip/Bundles/Alone2/_o/7zz
#
# 官方 makefile 不设 macOS 最低版本，编译器默认拿当前系统当目标，
# 编出来的包在低版本系统上起不来。这里显式钉住 MIN_OS。
#
# MY_ARCH 是官方 makefile 预留的变量，它同时出现在 CFLAGS、CXXFLAGS
# 和链接行的 LFLAGS_ALL 里，所以一个变量就能同时管住架构和最低版本。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/scripts/config.sh"

SRC="$ROOT/vendor/7zip-26.03/CPP/7zip/Bundles/Alone2"
OUT="$SRC/_o/7zz"
JOBS="$(sysctl -n hw.ncpu)"

if [ ! -f "$SRC/makefile.gcc" ]; then
    echo "找不到 7-Zip 源码：$SRC" >&2
    echo "先跑 scripts/fetch-source.sh" >&2
    exit 1
fi

build_arch() {
    local arch="$1" dir="$2"
    echo "==> 7zz / ${arch}（最低 macOS ${MIN_OS}）"
    # 每个架构一个输出目录，否则第二遍会直接复用第一遍的目标文件
    rm -rf "$SRC/$dir"
    env MACOSX_DEPLOYMENT_TARGET="$MIN_OS" \
        make -C "$SRC" -j"$JOBS" -f makefile.gcc \
             O="$dir" MY_ARCH="-target $arch-apple-macos$MIN_OS"
}

build_arch arm64  _o_arm64
build_arch x86_64 _o_x64

echo "==> 合成 universal"
mkdir -p "$SRC/_o"
lipo -create "$SRC/_o_arm64/7zz" "$SRC/_o_x64/7zz" -output "$OUT"

echo "==> 产物"
lipo -info "$OUT"
for arch in arm64 x86_64; do
    printf "    %-7s minos=%s\n" "$arch" \
        "$(otool -arch "$arch" -l "$OUT" | awk '/LC_BUILD_VERSION/{f=1} f&&/minos/{print $2; exit}')"
done
"$OUT" | head -2
