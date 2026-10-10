#!/usr/bin/env python3
"""从官方 FM.ico 生成 AppIcon.icns。

FM.ico 只有 16/32/48 三个尺寸（Windows 上也只到 48，资源管理器那边靠缩放），
所以 128 以上的档位是拿 48x48 按最近邻放大来的——图标本身是纯黑白图形，
放大不糊，只会有像素台阶，比插值发虚更接近原样。
"""

import pathlib
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import mkicons  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
ICO = ROOT / "vendor" / "7zip-26.03" / "CPP" / "7zip" / "UI" / "FileManager" / "FM.ico"
OUT = ROOT / "resources" / "AppIcon.icns"


def resize_nearest(w: int, h: int, rgba: bytes, nw: int, nh: int) -> bytes:
    """任意倍数最近邻放大（整数倍以下的档位也会用到）。"""
    out = bytearray(nw * nh * 4)
    for y in range(nh):
        sy = min(h - 1, y * h // nh)
        row = rgba[sy * w * 4:(sy + 1) * w * 4]
        dst = y * nw * 4
        for x in range(nw):
            sx = min(w - 1, x * w // nw) * 4
            out[dst + x * 4:dst + x * 4 + 4] = row[sx:sx + 4]
    return bytes(out)


def main() -> int:
    images = mkicons.load_ico(ICO)
    by_size = {w: (w, h, d) for w, h, d in images}
    src48 = by_size.get(48) or images[-1]
    print("源尺寸:", sorted(by_size))

    def at(size: int) -> bytes:
        if size in by_size:
            return by_size[size][2]
        return resize_nearest(*src48, size, size)

    # iconset 规定的档位：文件名 -> 像素尺寸
    plan = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 48),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    tmp = pathlib.Path(tempfile.mkdtemp(prefix="7zip-icns-"))
    iconset = tmp / "AppIcon.iconset"
    iconset.mkdir()
    for name, size in plan:
        mkicons.write_png(iconset / name, size, size, at(size))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    r = subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(OUT)],
                       capture_output=True, text=True)
    shutil.rmtree(tmp, ignore_errors=True)
    if r.returncode != 0:
        print(r.stdout, r.stderr, file=sys.stderr)
        return r.returncode
    print(f"写出 {OUT.relative_to(ROOT)}（{OUT.stat().st_size} 字节）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
