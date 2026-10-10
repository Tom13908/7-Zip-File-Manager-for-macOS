#!/usr/bin/env python3
"""把 resources/l10n/<语言>.strings 装配成 App 包里的 .lproj 目录。

resources/l10n/ 里放的是**权威译文**（UTF-8，`"英文原文" = "译文";`），这里是唯一
会去动它们的程序：抽取键、查漏、转码、写盘。

产出（resources/lproj/）：

    <语言>.lproj/Localizable.strings    —— 界面文案，供 src/Localize.swift 的 L() 查
    <语言>.lproj/ServicesMenu.strings   —— Finder 右键菜单里那几条服务的名字

两份都用 UTF-16（带 BOM）写。`.strings` 的传统编码就是 UTF-16，Apple 的
「Localizing the Services Menu」也点名要求 ServicesMenu.strings 用 UTF-16。

键从两处抽：

  * src/Strings.swift 里所有 L("...") 的字面量
  * tools/mkinfo.py 的 SERVICES —— 服务菜单显示的名字只在那里定义，Swift 侧看不到

用法：

    python3 tools/mkl10n.py           # 校验 + 写盘
    python3 tools/mkl10n.py check     # 只校验，不写盘

译文从哪来：与 Windows 版 7-Zip 逐条对齐 —— 对得上的直接取自官方语言包
（https://www.7-zip.org 的安装程序里 Lang/*.txt，en.ttt 是对照的英文原文、
各语言文件行号与它一一对应），官方没有的是 macOS 侧独有文案（服务菜单名字、
AppKit 惯例菜单项、启动位置 / 主路径这些设置项），按同样的用词风格补齐。
官方译文里的 Windows 加速键（`&File`、`复制到(&C)`）在导入时已经去掉，
macOS 用的是 keyEquivalent。
"""

import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
L10N = ROOT / "resources" / "l10n"
OUT = ROOT / "resources" / "lproj"

# 顺序即 System Settings 里的显示顺序，第一个是源语言
LANG_CODES = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "de", "fr", "es", "pt-BR", "it", "ru"]

# 语言的自称，写进 .lproj 的注释行（不影响运行）
LANG_NAMES = {
    "en": "English", "zh-Hans": "简体中文", "zh-Hant": "繁體中文", "ja": "日本語",
    "ko": "한국어", "de": "Deutsch", "fr": "Français", "es": "Español",
    "pt-BR": "Português (Brasil)", "it": "Italiano", "ru": "Русский",
}

ENTRY = re.compile(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;')


def unescape(s: str) -> str:
    out, i = [], 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            n = s[i + 1]
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(n, n))
            i += 2
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


def read_strings(path: pathlib.Path) -> dict:
    table = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        m = ENTRY.match(line.strip())
        if m:
            table[unescape(m.group(1))] = unescape(m.group(2))
    return table


def swift_keys() -> list:
    src = (ROOT / "src" / "Strings.swift").read_text(encoding="utf-8")
    keys = []
    for m in re.finditer(r'\bL\(\s*"((?:[^"\\]|\\.)*)"', src):
        k = unescape(m.group(1))
        if k and k not in keys:
            keys.append(k)
    return keys


def service_titles() -> list:
    """服务菜单要显示的名字，与 Info.plist 的 NSServices 同源。"""
    sys.path.insert(0, str(ROOT / "tools"))
    import mkinfo
    return [label for _, label, _ in mkinfo.SERVICES]


def quote(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def main(argv) -> int:
    write = "check" not in argv

    keys = swift_keys()
    services = service_titles()
    for s in services:
        if s not in keys:
            keys.append(s)

    rc = 0
    tables = {}
    for code in LANG_CODES:
        path = L10N / f"{code}.strings"
        if not path.exists():
            print(f"缺文件：{path.relative_to(ROOT)}", file=sys.stderr)
            rc = 1
            continue
        tables[code] = read_strings(path)

    for code in LANG_CODES:
        table = tables.get(code)
        if table is None:
            continue
        gaps = [k for k in keys if k not in table]
        stale = [k for k in table if k not in keys]
        if gaps:
            rc = 1
            print(f"{code}: 缺 {len(gaps)} 条译文：", file=sys.stderr)
            for g in gaps:
                print(f"    {g!r}", file=sys.stderr)
        if stale:
            # 源码里已经删掉的串还留在译文里 —— 只提醒，不当失败
            print(f"{code}: 有 {len(stale)} 条已经用不到的译文，建议清掉：{stale}")

    if rc or not write:
        if not rc:
            print(f"校验通过：{len(keys)} 条文案 × {len(LANG_CODES)} 种语言")
        return rc

    OUT.mkdir(parents=True, exist_ok=True)
    for code in LANG_CODES:
        d = OUT / f"{code}.lproj"
        d.mkdir(parents=True, exist_ok=True)
        table = tables[code]

        rows = [f"/* {LANG_NAMES[code]} — {len(keys)} 条，由 tools/mkl10n.py 从 "
                f"resources/l10n/{code}.strings 生成 */", ""]
        rows += [f"{quote(k)} = {quote(table[k])};" for k in sorted(table)]
        (d / "Localizable.strings").write_text("\n".join(rows) + "\n", encoding="utf-16")

        # 服务菜单只放那几条服务的名字（键就是 Info.plist 里的英文原文）
        rows = ["/* Finder 服务菜单条目名 */", ""]
        rows += [f"{quote(s)} = {quote(table[s])};" for s in services]
        (d / "ServicesMenu.strings").write_text("\n".join(rows) + "\n", encoding="utf-16")

    print(f"写出 {OUT.relative_to(ROOT)}/：{len(LANG_CODES)} 种语言 × "
          f"{len(keys)} 条文案，服务菜单 {len(services)} 条")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
