#!/bin/bash
# 把构建好的 App 装到 /Applications，并让 Finder 认出它的右键菜单。
#
#   scripts/install.sh              装到 /Applications
#   DEST_DIR=~/Applications scripts/install.sh   装到别处（测试用）
#
# 装完要做的两件事在最后会打印出来：Finder 里启用服务项、第一次打开。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/build/7-Zip File Manager.app"
DEST_DIR="${DEST_DIR:-/Applications}"
DEST="$DEST_DIR/7-Zip File Manager.app"
LSR="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [ ! -d "$SRC" ]; then
    echo "没有找到 ${SRC}，先跑 scripts/build-app.sh" >&2
    exit 1
fi

if [ -e "$DEST" ]; then
    echo "目标位置已经有同名的 App：$DEST"
    echo -n "覆盖掉它？[y/N] "
    read -r ans
    case "$ans" in
        y|Y)
            # 同 build-app.sh：直接 rm -rf 一个 .app 会让系统往废纸篓塞副本
            mv "$DEST" "$DEST_DIR/.old-app"
            rm -rf "$DEST_DIR/.old-app"
            ;;
        *) echo "已取消"; exit 1 ;;
    esac
fi

mkdir -p "$DEST_DIR"
# ditto 比 cp -R 可靠：会保留签名、权限和扩展属性
ditto "$SRC" "$DEST"
echo "已安装：$DEST"

# 让 LaunchServices 立刻认到这个 App（不然 Finder 要等下次登录才看到）
if [ -x "$LSR" ]; then
    "$LSR" -f "$DEST" >/dev/null 2>&1 || true
fi

cat <<'EOF'

接下来两件事要手动做一次：

1. 打开 Finder 的右键菜单
   选取一个 .7z / .zip 之类的压缩包 → 右键 →「快速操作 / 服务」，
   就能看到 Extract Here、Extract to Folder、Extract Files…、Test Archive。
   如果没有，去「系统设置 → 键盘 → 键盘快捷键 → 服务 → 文件与文件夹」
   把它们勾上。

   对着普通文件右键则是 Compress to 7z、Compress to Zip、Add to Archive…。

2. 第一次打开
   这个 App 是在本机编译并临时签名的，没有隔离属性，双击就能开。
   如果是别人传给你的（或者从压缩包里解出来的），macOS 会拦一次，
   这时右键点图标选「打开」即可；实在不行就执行：
       xattr -dr com.apple.quarantine "/Applications/7-Zip File Manager.app"

卸载：把 App 拖到废纸篓。它只写两处：
       ~/Library/Preferences/org.7-zip.FileManager.plist（设置）
       LaunchServices 里的 App 注册记录（拖走 App 后系统自己会清掉）。
EOF
