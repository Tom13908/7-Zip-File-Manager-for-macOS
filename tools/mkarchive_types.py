#!/usr/bin/env python3
"""从 7zz 自己的 `i` 输出里抽出「归档格式 -> 扩展名」对照表。

7-Zip 在 Windows 上靠注册表认归档；这里改成从引擎自身的格式表生成，
好处是只要重新编译引擎，认得的格式就跟着变，不需要手动维护扩展名清单。

产出 resources/archive_types.json:
  {
    "extensions": ["7z", "zip", ...],        // 所有可当归档打开的扩展名
    "byExt": {"7z": "7z", "tgz": "tar", ...} // 扩展名 -> 图标名(resources/icons/archive/*.png)
  }
"""

import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "vendor" / "7zip-26.03" / "CPP" / "7zip"
ENGINE = SRC / "Bundles" / "Alone2" / "_o" / "7zz"
ICONS = ROOT / "resources" / "icons" / "archive"
OUT = ROOT / "resources" / "archive_types.json"

# `7zz i` 的 Formats 表每行形如：
#   <24 列标志位>  <格式名>  <扩展名...>  <签名...>
# 扩展名列不是定宽（列表长了会被撑开），所以不能按列切，只能按 token 判定：
# 从格式名往后逐个吃「像扩展名」的 token，遇到第一个不像的就停——那里就是签名的开头。
FLAGS_COLS = 26
EXT_TOKEN = re.compile(r"^[a-z0-9][a-z0-9_+-]{1,11}$")  # 至少两位，可数字开头（"7z"）
EXT_SINGLE = {"z"}  # 单字母扩展名，只有 z 是真的

# 扩展名 -> 图标名。图标来自 Archive/Icons/*.ico，没对应图标的用通用图标。
ICON_ALIAS = {
    "7z": "7z", "zip": "zip", "zipx": "zip", "jar": "zip", "xpi": "zip", "apk": "zip",
    "tar": "tar", "gz": "gz", "tgz": "tar", "bz2": "bz2", "tbz": "tar", "tbz2": "tar",
    "xz": "xz", "txz": "tar", "lzma": "lzma", "zst": "zst", "z": "z", "lzh": "lzh",
    "rar": "rar", "cab": "cab", "iso": "iso", "img": "iso", "wim": "wim", "dmg": "dmg",
    "xar": "xar", "cpio": "cpio", "rpm": "rpm", "deb": "deb", "arj": "arj",
    "lz": "lzma", "br": "lzma", "vhd": "vhd", "vmdk": "vhd", "vdi": "vhd",
    "msi": "cab", "doc": "zip", "xls": "zip", "ppt": "zip",
}

# 排除两类：
#   1. 7-Zip 格式表里混进来的「裸文件格式」——它们不是归档，当归档打开没有意义
#   2. Hash 格式带出来的一堆校验文件扩展名（.md5/.sha256/...），这些是校验清单不是归档
EXCLUDE_EXT = {
    # 裸文件格式
    "obj", "lib", "exe", "dll", "sys", "so", "dylib", "a", "o", "class", "pyc",
    "b64", "ihex", "srec", "tek", "flv", "swf", "png", "jpg", "gif", "bmp",
    "mp3", "mp4", "wav", "avi", "mkv", "ttf", "otf", "woff", "pdf", "elf",
    "macho", "pe", "coff", "mbr", "gpt", "squashfs", "cramfs", "apm", "vdi",
    "te", "lit", "simg", "ppkg", "scap", "aaf",
    # 校验文件
    "md5", "sha", "sha1", "sha2", "sha3", "sha224", "sha256", "sha384", "sha512",
    "sha512-224", "sha512-256", "sha3-224", "sha3-256", "sha3-384", "sha3-512",
    "blake2b", "blake2s", "blake2sp", "xxh64", "crc32", "crc64", "cksum", "asc",
}


def run_i() -> str:
    if not ENGINE.exists():
        print(f"找不到引擎 {ENGINE}，请先编译 7zz", file=sys.stderr)
        sys.exit(1)
    return subprocess.run([str(ENGINE), "i"], capture_output=True, text=True,
                          stdin=subprocess.DEVNULL).stdout


def parse_formats(text: str) -> dict:
    """返回 {格式名: [扩展名, ...]}"""
    out = {}
    in_formats = False
    for line in text.splitlines():
        if line.startswith("Formats:"):
            in_formats = True
            continue
        if not in_formats:
            continue
        if not line.strip():
            break

        body = line[FLAGS_COLS:].strip()
        if not body:
            continue
        parts = body.split()
        name = parts[0]
        if not name[:1].isalnum():
            continue

        exts = []
        for tok in parts[1:]:
            if EXT_TOKEN.fullmatch(tok) or tok in EXT_SINGLE:
                exts.append(tok)
            else:
                break  # 签名开始了
        out.setdefault(name, [])
        out[name] += [e for e in exts if e not in out[name]]
    return out


def main() -> int:
    formats = parse_formats(run_i())
    have_icons = {p.stem for p in ICONS.glob("*.png") if "@2x" not in p.name}

    by_ext = {}
    for fmt, exts in formats.items():
        for e in exts:
            if e in EXCLUDE_EXT:
                continue
            by_ext.setdefault(e, ICON_ALIAS.get(e, fmt.lower()))

    # 图标名必须真实存在，否则退回通用 7z 图标
    missing = sorted({v for v in by_ext.values() if v not in have_icons})
    for e, icon in list(by_ext.items()):
        if icon not in have_icons:
            by_ext[e] = "7z"

    data = {
        "engine": "7-Zip 26.03",
        "formats": {k: v for k, v in sorted(formats.items())},
        "extensions": sorted(by_ext),
        "byExt": dict(sorted(by_ext.items())),
    }
    OUT.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n")
    print(f"格式 {len(formats)} 个，扩展名 {len(by_ext)} 个 -> {OUT.name}")
    if missing:
        print(f"缺少图标的格式（已退回通用图标）: {', '.join(missing)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
