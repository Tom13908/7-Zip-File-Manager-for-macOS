#!/usr/bin/env python3
"""把 7-Zip 官方源码里的图标资源（.ico / .bmp）转成 PNG，供 macOS 版 GUI 直接使用。

覆盖三类素材：
  * CPP/7zip/Archive/Icons/*.ico  —— 每种归档格式的图标（Windows 版文件列表用的就是这批）
  * CPP/7zip/UI/FileManager/FM.ico, 7zipLogo.ico —— 程序图标 / 关于对话框 logo
  * CPP/7zip/UI/FileManager/*.bmp —— 工具栏按钮位图（24x24 小号、48x36 大号）

只依赖标准库（struct + zlib），自己实现 ICO/BMP 解码与 PNG 编码。
每个图像同时输出 @1x 与 @2x（@2x 用最近邻放大，保持像素质感不发虚）。

有一枚是合成的：「智能解压」工具栏按钮官方没有对应素材（Windows 版 FM 没这个功能），
由 Extract 的位图叠加一颗四角星徽标得到，见下面的 sparkle_mask / badge_rgba。
"""

import pathlib
import struct
import sys
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "vendor" / "7zip-26.03" / "CPP" / "7zip"
OUT = ROOT / "resources" / "icons"


# ---------------------------------------------------------------- PNG 编码

def write_png(path: pathlib.Path, w: int, h: int, rgba: bytes) -> None:
    """rgba: 长度为 w*h*4 的字节串，逐行自上而下。"""
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)  # filter type 0 (None)
        raw += rgba[y * stride:(y + 1) * stride]

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


def upscale_nearest(w: int, h: int, rgba: bytes, factor: int) -> tuple:
    """最近邻整数倍放大，用于生成 @2x 位图。"""
    nw, nh = w * factor, h * factor
    out = bytearray(nw * nh * 4)
    for y in range(nh):
        sy = y // factor
        row = rgba[sy * w * 4:(sy + 1) * w * 4]
        dst = y * nw * 4
        if factor == 1:
            out[dst:dst + nw * 4] = row
            continue
        for x in range(nw):
            sx = (x // factor) * 4
            out[dst + x * 4:dst + x * 4 + 4] = row[sx:sx + 4]
    return nw, nh, bytes(out)


def emit(basename: str, group: str, w: int, h: int, rgba: bytes) -> None:
    d = OUT / group
    d.mkdir(parents=True, exist_ok=True)
    write_png(d / f"{basename}.png", w, h, rgba)
    nw, nh, big = upscale_nearest(w, h, rgba, 2)
    write_png(d / f"{basename}@2x.png", nw, nh, big)
    print(f"  {group}/{basename}  {w}x{h} (+@2x)")


# ---------------------------------------------------------------- BMP 解码

def decode_dib(data: bytes, want_alpha_mask: bool = True) -> tuple:
    """解码一段 DIB（BITMAPINFOHEADER 起头）。ICAL 里的图像数据就是这种。

    返回 (width, height, rgba)；高度是像素高度（DIB 里存的是两倍高，另一半是 AND 掩码）。
    """
    (hdr_size, w, h2, planes, bpp, compression,
     _img_size, _xppm, _yppm, clr_used, _clr_imp) = struct.unpack_from("<IiiHHIIiiII", data, 0)

    if compression != 0:
        raise ValueError(f"不支持的 BMP 压缩方式 {compression}")

    h = abs(h2) // 2 if want_alpha_mask else abs(h2)
    top_down = h2 < 0

    n_colors = clr_used or (1 << bpp if bpp <= 8 else 0)
    pal_off = hdr_size
    palette = []
    for i in range(n_colors):
        b, g, r, _ = data[pal_off + i * 4: pal_off + i * 4 + 4]
        palette.append((r, g, b))
    xor_off = pal_off + n_colors * 4

    stride = ((w * bpp + 31) // 32) * 4
    mask_stride = ((w + 31) // 32) * 4
    mask_off = xor_off + stride * h

    rgba = bytearray(w * h * 4)
    for y in range(h):
        sy = y if top_down else (h - 1 - y)
        row = xor_off + sy * stride
        mrow = mask_off + sy * mask_stride
        for x in range(w):
            if bpp == 32:
                b, g, r, a = data[row + x * 4: row + x * 4 + 4]
            elif bpp == 24:
                b, g, r = data[row + x * 3: row + x * 3 + 3]
                a = 255
            elif bpp == 8:
                r, g, b = palette[data[row + x]]
                a = 255
            elif bpp == 4:
                byte = data[row + x // 2]
                idx = (byte >> 4) if x % 2 == 0 else (byte & 0x0F)
                r, g, b = palette[idx]
                a = 255
            elif bpp == 1:
                byte = data[row + x // 8]
                bit = (byte >> (7 - x % 8)) & 1
                r, g, b = palette[bit]
                a = 255
            else:
                raise ValueError(f"不支持的位深 {bpp}")

            if want_alpha_mask and bpp != 32:
                # AND 掩码里 1 = 透明
                mbit = (data[mrow + x // 8] >> (7 - x % 8)) & 1
                a = 0 if mbit else 255
            elif bpp != 32 and (r, g, b) == (255, 0, 255):
                # 16 色图标用洋红当透明色
                a = 0

            o = (y * w + x) * 4
            rgba[o] = r
            rgba[o + 1] = g
            rgba[o + 2] = b
            rgba[o + 3] = a

    if bpp == 32:
        # 32 位图标：全透明像素偶尔带脏色，清掉
        for i in range(0, len(rgba), 4):
            if rgba[i + 3] == 0:
                rgba[i] = rgba[i + 1] = rgba[i + 2] = 0

    return w, h, bytes(rgba)


# ---------------------------------------------------------------- ICO 解码

def load_ico(path: pathlib.Path) -> list:
    """返回 [(width, height, rgba), ...]，按尺寸从小到大。"""
    d = path.read_bytes()
    reserved, img_type, count = struct.unpack_from("<HHH", d, 0)
    if reserved != 0 or img_type != 1:
        raise ValueError(f"{path.name} 不是 ICO 文件")

    out = []
    for i in range(count):
        w, h, _cc, _res, _planes, _bpp, size, off = struct.unpack_from("<BBBBHHII", d, 6 + i * 16)
        w = w or 256
        h = h or 256
        blob = d[off: off + size]
        if blob[:8] == b"\x89PNG\r\n\x1a\n":
            raise ValueError(f"{path.name} 含 PNG 压缩图像，暂不支持")
        dw, dh, rgba = decode_dib(blob)
        out.append((dw, dh, rgba))
    out.sort(key=lambda t: t[0] * t[1])
    return out


# ------------------------------------------------- 合成：智能解压按钮的徽标

def sparkle_mask(n: int, p: float = 0.55, shrink: float = 0.98) -> list:
    """n×n 的四角星覆盖率（0..1，逐行自上而下）。

    `|u|^p + |v|^p <= 1`，u/v 是归一化到 [-1,1] 的坐标。p 取 1 时是个菱形，
    取小于 1 时四条边往里凹，就得到四角星。每像素再 3×3 超采样一次，免得边缘毛刺。
    """
    center = n / 2.0
    r = center * shrink
    ss = 3
    cov = []
    for y in range(n):
        row = []
        for x in range(n):
            hits = 0
            for sy in range(ss):
                for sx in range(ss):
                    u = abs(x + (sx + 0.5) / ss - center) / r
                    v = abs(y + (sy + 0.5) / ss - center) / r
                    if u ** p + v ** p <= 1.0:
                        hits += 1
            row.append(hits / (ss * ss))
        cov.append(row)
    return cov


def badge_rgba(n: int) -> tuple:
    """带 1px 描边的四角星徽标。

    描边是必需的：徽标压在图标本体上，没有描边就会和底下的图形糊在一起。
    取深灰而不是纯黑 —— 图标本体的边框就是黑的，纯黑描边贴上去分不出层次。
    """
    fill = (255, 198, 40)
    line = (58, 58, 58)
    outer = sparkle_mask(n)
    inner = sparkle_mask(n - 2)

    out = bytearray(n * n * 4)
    for y in range(n):
        for x in range(n):
            a = outer[y][x]
            if a <= 0.0:
                continue
            ii = inner[y - 1][x - 1] if (1 <= y <= n - 2 and 1 <= x <= n - 2) else 0.0
            ii = min(ii, a)
            o = (y * n + x) * 4
            for k in range(3):
                out[o + k] = int(round((line[k] * (a - ii) + fill[k] * ii) / a))
            out[o + 3] = int(round(a * 255))
    return n, n, bytes(out)


def overlay(dw: int, dh: int, dst: bytearray, sw: int, sh: int, src: bytes,
            ox: int, oy: int) -> None:
    """把 src 按 alpha 混合到 dst 的 (ox, oy) 处，原地改 dst。"""
    for y in range(sh):
        ty = oy + y
        if not (0 <= ty < dh):
            continue
        for x in range(sw):
            tx = ox + x
            if not (0 <= tx < dw):
                continue
            so = (y * sw + x) * 4
            sa = src[so + 3] / 255.0
            if sa <= 0.0:
                continue
            do = (ty * dw + tx) * 4
            da = dst[do + 3] / 255.0
            oa = sa + da * (1 - sa)
            if oa <= 0.0:
                continue
            for k in range(3):
                dst[do + k] = int(round((src[so + k] * sa + dst[do + k] * da * (1 - sa)) / oa))
            dst[do + 3] = int(round(oa * 255))


def load_bmp(path: pathlib.Path, icon_w: int) -> list:
    """工具栏位图是横向排列的图标条，按 icon_w 切成若干张。"""
    d = path.read_bytes()
    data_off = struct.unpack_from("<I", d, 10)[0]
    (hdr_size, w, h, planes, bpp, compression,
     _img_size, _xppm, _yppm, clr_used, _clr_imp) = struct.unpack_from("<IiiHHIIiiII", d, 14)

    n_colors = clr_used or (1 << bpp if bpp <= 8 else 0)
    palette = []
    for i in range(n_colors):
        b, g, r, _ = d[14 + hdr_size + i * 4: 14 + hdr_size + i * 4 + 4]
        palette.append((r, g, b))

    stride = ((w * bpp + 31) // 32) * 4
    tiles = []
    n_tiles = max(1, w // icon_w)
    for t in range(n_tiles):
        rgba = bytearray(icon_w * h * 4)
        for y in range(h):
            sy = h - 1 - y
            row = data_off + sy * stride
            for x in range(icon_w):
                sx = t * icon_w + x
                if bpp == 4:
                    byte = d[row + sx // 2]
                    idx = (byte >> 4) if sx % 2 == 0 else (byte & 0x0F)
                    r, g, b = palette[idx]
                elif bpp == 8:
                    r, g, b = palette[d[row + sx]]
                elif bpp == 24:
                    b, g, r = d[row + sx * 3: row + sx * 3 + 3]
                else:
                    raise ValueError(f"工具栏位图位深 {bpp} 未处理")
                o = (y * icon_w + x) * 4
                rgba[o], rgba[o + 1], rgba[o + 2] = r, g, b
                # 洋红 (255,0,255) 是 7-Zip 位图里的透明色
                rgba[o + 3] = 0 if (r, g, b) == (255, 0, 255) else 255
        tiles.append((icon_w, h, bytes(rgba)))
    return tiles


# ---------------------------------------------------------------- 主流程

def main() -> int:
    if not SRC.exists():
        print(f"找不到源码目录 {SRC}", file=sys.stderr)
        return 1

    print("[1/4] 归档格式图标 (Archive/Icons/*.ico)")
    first = None
    for ico in sorted((SRC / "Archive" / "Icons").glob("*.ico")):
        try:
            imgs = load_ico(ico)
        except ValueError as e:
            print(f"  跳过 {ico.name}: {e}")
            continue
        # 取最大的一枚作为基准，其余尺寸也一并导出（macOS 会按需选用）
        w, h, rgba = imgs[-1]
        emit(ico.stem, "archive", w, h, rgba)
        if first is None:
            first = (w, h, rgba)

    print("[2/4] 程序图标 (FileManager/FM.ico)")
    for w, h, rgba in load_ico(SRC / "UI" / "FileManager" / "FM.ico"):
        emit(f"fm_{w}", "app", w, h, rgba)

    print("[3/4] 关于对话框 logo (FileManager/7zipLogo.ico)")
    for w, h, rgba in load_ico(SRC / "UI" / "FileManager" / "7zipLogo.ico"):
        emit("logo", "app", w, h, rgba)

    print("[4/4] 工具栏按钮 (FileManager/*.bmp)")
    fm = SRC / "UI" / "FileManager"
    names = ["Add", "Extract", "Test", "Copy", "Move", "Delete", "Info"]
    for n in names:
        tiles = load_bmp(fm / f"{n}2.bmp", 24)
        emit(f"{n.lower()}_small", "toolbar", *tiles[0])
        tiles = load_bmp(fm / f"{n}.bmp", 48)
        emit(f"{n.lower()}_large", "toolbar", *tiles[0])

    # 「智能解压」是 macOS 侧独有的功能，官方素材里没有这一枚，
    # 拿 Extract 的位图在右上角加一颗四角星拼出来。
    for src_name, out_name, tile_w, badge in [("Extract2", "extractsmart_small", 24, 12),
                                              ("Extract", "extractsmart_large", 48, 17)]:
        # 小图标那颗往左下压一点，正好骑在蓝盒子的右上角上
        inset = 1 if tile_w == 24 else 3
        tw, th, tile = load_bmp(fm / f"{src_name}.bmp", tile_w)[0]
        buf = bytearray(tile)
        bw, bh, star = badge_rgba(badge)
        overlay(tw, th, buf, bw, bh, star, tw - bw - inset, inset)
        emit(out_name, "toolbar", tw, th, bytes(buf))

    print("完成。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
