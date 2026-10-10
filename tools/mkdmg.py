#!/usr/bin/env python3
"""生成 DMG 的背景图和窗口布局（.DS_Store）。

挂载 DMG 后 Finder 打开的那个窗口——窗口多大、两个图标摆在哪里、中间的箭头——
全都由卷里的 .DS_Store 决定。本来可以用 AppleScript 指挥 Finder 去摆，
但那一步要过 TCC 授权，在本机实测直接返回 -10004（权限违例）。
所以这里自己把 .DS_Store 写出来。

两个子命令：

    mkdmg.py background <输出目录>     生成 background.png 与 background@2x.png
    mkdmg.py layout <挂载点>           在挂载点里写 .DS_Store 和 .background/

.ds_store / mac_alias 两个库只用在打包这一步，不影响 App 本身。
"""

import pathlib
import sys

# ---------------------------------------------------------------- 布局参数

WINDOW_W, WINDOW_H = 640, 400          # 窗口内容区尺寸（点）
WINDOW_POS = (200, 120)                # 窗口左上角在屏幕上的位置
ICON_SIZE = 128                        # 图标显示尺寸
APP_ICON_POS = (150, 190)              # App 图标中心
DEST_ICON_POS = (490, 190)             # Applications 快捷方式的中心
VOLUME_NAME = "7-Zip File Manager"
APP_NAME = "7-Zip File Manager.app"
BG_NAME = "background.png"
BG_DIR = ".background"

BG_TOP = (250, 250, 252)
BG_BOTTOM = (238, 238, 242)

# 箭头是窗口里唯一的提示：从 App 指向 Applications，告诉用户把左边拖到右边。
# 画得粗一些、颜色实一些 —— 之前那版又细又淡，在一张浅色背景上几乎看不见。
# 两端各留 14pt 空隙，正好贴住两个图标（图标 128pt、中心 150 / 490）。
ARROW_COLOR = (146, 149, 157)
ARROW_Y = 190
ARROW_X0, ARROW_X1 = 228, 412
ARROW_THICK = 14
ARROW_HEAD_W, ARROW_HEAD_H = 44, 44


# ---------------------------------------------------------------- 背景图

def draw_background(scale: int) -> "PIL.Image.Image":
    from PIL import Image, ImageDraw
    ss = 4                                     # 超采样倍数，缩回来就是抗锯齿
    w, h = WINDOW_W * scale * ss, WINDOW_H * scale * ss
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)

    # 竖向微渐变，避免一整块死白
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=tuple(
            round(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3)))

    def s(v):
        return v * scale * ss

    y = s(ARROW_Y)
    x0, x1 = s(ARROW_X0), s(ARROW_X1)
    half = s(ARROW_THICK) / 2
    head_w, head_h = s(ARROW_HEAD_W), s(ARROW_HEAD_H)

    # 箭杆
    d.rounded_rectangle([x0, y - half, x1 - head_w * 0.55, y + half],
                        radius=half, fill=ARROW_COLOR)
    # 箭头
    d.polygon([(x1 - head_w, y - head_h / 2),
               (x1, y),
               (x1 - head_w, y + head_h / 2)], fill=ARROW_COLOR)

    return img.resize((WINDOW_W * scale, WINDOW_H * scale), Image.LANCZOS)


def cmd_background(outdir: str) -> None:
    out = pathlib.Path(outdir)
    out.mkdir(parents=True, exist_ok=True)
    draw_background(1).save(out / BG_NAME)
    draw_background(2).save(out / "background@2x.png")
    print(f"背景图 -> {out / BG_NAME}, {out / 'background@2x.png'}")


# ---------------------------------------------------------------- 窗口布局

def window_settings() -> dict:
    """bwsp：窗口本身（位置、大小、隐藏侧栏和工具栏）。"""
    x, y = WINDOW_POS
    return {
        "ShowStatusBar": False,
        "WindowBounds": f"{{{{{x}, {y}}}, {{{WINDOW_W}, {WINDOW_H}}}}}",
        "ContainerShowSidebar": False,
        "PreviewPaneVisibility": False,
        "SidebarWidth": 0,
        "ShowSidebar": False,
        "ShowTabView": False,
        "ShowToolbar": False,
        "ShowPathbar": False,
    }


def icon_view_settings(alias_bytes: bytes) -> dict:
    """icvp：图标视图的外观——图标多大、背景用图片、标签在图标下方。"""
    return {
        "viewOptionsVersion": 1,
        "backgroundType": 2,               # 2 = 用图片（1 = 纯色）
        "backgroundImageAlias": alias_bytes,
        "arrangeBy": "none",               # 位置我们自己定，别让 Finder 重排
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "gridSpacing": 100.0,
        "iconSize": float(ICON_SIZE),
        "labelOnBottom": True,
        "showIconPreview": False,
        "showItemInfo": False,
        "textSize": 12.0,
    }


def cmd_layout(mount: str) -> None:
    from ds_store import DSStore
    from ds_store.store import DSStoreEntry, ILocCodec, PlistCodec
    from mac_alias import Alias

    root = pathlib.Path(mount)
    if not root.is_dir():
        sys.exit(f"挂载点不存在：{root}")

    bg = root / BG_DIR / BG_NAME
    if not bg.is_file():
        sys.exit(f"卷里没有背景图：{bg}（先把 .background/ 拷进去再跑这一步）")

    # alias 记的是卷内路径。必须先挂载、文件真实存在，才能算出来。
    alias = Alias.for_file(str(bg))

    entries = [
        DSStoreEntry(".", "bwsp", PlistCodec, window_settings()),
        DSStoreEntry(".", "icvp", PlistCodec, icon_view_settings(alias.to_bytes())),
        DSStoreEntry(APP_NAME, "Iloc", ILocCodec, APP_ICON_POS),
        DSStoreEntry("Applications", "Iloc", ILocCodec, DEST_ICON_POS),
    ]
    entries.sort()

    ds = root / ".DS_Store"
    if ds.exists():
        ds.unlink()
    with DSStore.open(str(ds), "w+", initial_entries=entries) as d:
        d.flush()

    print(f"窗口布局 -> {ds}")
    print(f"  窗口 {WINDOW_W}x{WINDOW_H} @ {WINDOW_POS}")
    print(f"  {APP_NAME} @ {APP_ICON_POS}   Applications @ {DEST_ICON_POS}")


# ---------------------------------------------------------------- 入口

def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    cmd, arg = sys.argv[1], sys.argv[2]
    if cmd == "background":
        cmd_background(arg)
    elif cmd == "layout":
        cmd_layout(arg)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
