#!/bin/bash
# 拉取 7-Zip 26.03 官方源码并解压到 vendor/7zip-26.03。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="26.03"
URL="https://github.com/ip7z/7zip/releases/download/${VERSION}/7z${VERSION//./}-src.tar.xz"
SHA256="9cbde5099c6deb73691b0579063da5827522ccbbcba3f0020fd04e8c8c16c0d4"

VENDOR="$ROOT/vendor"
TARBALL="$VENDOR/7z${VERSION//./}-src.tar.xz"
DEST="$VENDOR/7zip-$VERSION"

mkdir -p "$VENDOR"

if [ ! -f "$TARBALL" ]; then
    echo "==> 下载 $URL"
    curl -fL --retry 3 -o "$TARBALL" "$URL"
fi

echo "==> 校验 SHA256"
ACTUAL="$(shasum -a 256 "$TARBALL" | awk '{print $1}')"
if [ "$ACTUAL" != "$SHA256" ]; then
    echo "校验失败：期望 ${SHA256}，实际 ${ACTUAL}" >&2
    exit 1
fi
echo "    $ACTUAL"

if [ -d "$DEST" ]; then
    echo "==> $DEST 已存在，跳过解压"
else
    echo "==> 解压"
    TMP="$(mktemp -d)"
    tar -xf "$TARBALL" -C "$TMP"
    mkdir -p "$DEST"
    # 压缩包顶层是 Asm/ C/ CPP/ DOC/
    for d in Asm C CPP DOC; do
        mv "$TMP/$d" "$DEST/"
    done
    rm -rf "$TMP"
    echo "    解压到 $DEST"
fi

echo "==> 完成。下一步：scripts/build-engine.sh"
