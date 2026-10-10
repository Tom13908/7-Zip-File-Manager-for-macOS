#!/usr/bin/env python3
"""生成 Info.plist。

三块内容都是按 7-Zip for Windows 的行为反推的：

  * CFBundleDocumentTypes / UTExportedTypeDeclarations
      —— 对应 Windows 安装程序的「文件关联」。扩展名清单直接取 7zz i 的格式表
         （resources/archive_types.json），所以 GUI 认得的格式和引擎能开的一致。
  * NSServices
      —— 对应 Windows 资源管理器右键菜单里的那几条（解压 / 压缩 / 校验）。
         macOS 没有第三方壳扩展，只能走系统的「服务」机制。
  * 其余是 .app 的基本身份信息。

用完直接写 resources/Info.plist，构建脚本把它拷进 bundle。
"""

import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from mkl10n import LANG_CODES  # 支持的语言清单与 .lproj 由同一处定义

ROOT = pathlib.Path(__file__).resolve().parent.parent
TYPES = ROOT / "resources" / "archive_types.json"
OUT = ROOT / "resources" / "Info.plist"

BUNDLE_ID = "org.7-zip.FileManager"
APP_NAME = "7-Zip File Manager"
VERSION = "26.03"
ARCHIVE_UTI = "org.7-zip.archive"

# 最低系统版本。必须与两个架构切片的 minos 一致（见 scripts/build-app.sh 的 MIN_OS）：
# 声明得比切片低，LaunchServices 会放行、dyld 随后拒绝加载；
# 声明得比切片高，能跑的机器反而被挡在门外。
MIN_OS = "13.0"

# 右键菜单条目：(信息里声明的选择器, 菜单显示文字, 作用对象)
#   作用对象 archive = 只对归档出现；item = 文件和文件夹都有（压缩用）
#
# 这里的**书写顺序不影响菜单顺序**：Finder 的服务子菜单是按「本地化后的那行
# 显示文字」排序的（`localizedStandardCompare`），同一 App 的条目排成一组，
# 组内按文字排。实测方式见 skills/macos-app-localization-services-menu。
# 所以「Extract (Smart)」在中文界面排第一，靠的是「解压」这两个字，不是靠排在数组前面。
#
# 压缩只留一条：原来「Compress to 7z」「Compress to Zip」「Add to Archive…」
# 三条做的都是同一件事，合并成一条带对话框的。
SERVICES = [
    ("extractSmart", "Extract (Smart)", "archive"),
    ("extractHere", "Extract Here", "archive"),
    ("extractToDialog", "Extract to…", "archive"),
    ("testArchive", "Test Archive", "archive"),
    ("compressWithDialog", "Compress with 7-Zip…", "item"),
]


def xml_escape(s: str) -> str:
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def ind(n: int) -> str:
    return "\t" * n


def str_array(tag: str, values: list, n: int) -> str:
    out = [f"{ind(n)}<key>{tag}</key>", f"{ind(n)}<array>"]
    out += [f"{ind(n + 1)}<string>{xml_escape(v)}</string>" for v in values]
    out.append(f"{ind(n)}</array>")
    return "\n".join(out)


def service_dict(message: str, label: str, target: str, n: int) -> str:
    send_types = [ARCHIVE_UTI, "public.archive"] if target == "archive" else ["public.item"]
    parts = [
        f"{ind(n)}<dict>",
        f"{ind(n + 1)}<key>NSMenuItem</key>",
        f"{ind(n + 1)}<dict>",
        f"{ind(n + 2)}<key>default</key>",
        f"{ind(n + 2)}<string>{xml_escape(label)}</string>",
        f"{ind(n + 1)}</dict>",
        f"{ind(n + 1)}<key>NSMessage</key>",
        f"{ind(n + 1)}<string>{message}</string>",
        # 只在 Finder 里出现，别去别的 App 的「服务」菜单里凑热闹
        f"{ind(n + 1)}<key>NSRequiredContext</key>",
        f"{ind(n + 1)}<dict>",
        f"{ind(n + 2)}<key>NSApplicationIdentifier</key>",
        f"{ind(n + 2)}<string>com.apple.finder</string>",
        f"{ind(n + 1)}</dict>",
    ]
    parts.append(str_array("NSSendFileTypes", send_types, n + 1))
    parts.append(f"{ind(n)}</dict>")
    return "\n".join(parts)


def build(extensions: list) -> str:
    documented = [
        f"{ind(2)}<dict>",
        f"{ind(3)}<key>CFBundleTypeName</key>",
        f"{ind(3)}<string>7-Zip Archive</string>",
        f"{ind(3)}<key>CFBundleTypeRole</key>",
        f"{ind(3)}<string>Editor</string>",
        # 只是「也能用我打开」，不抢系统已有的默认程序
        f"{ind(3)}<key>LSHandlerRank</key>",
        f"{ind(3)}<string>Alternate</string>",
        f"{ind(3)}<key>LSItemContentTypes</key>",
        f"{ind(3)}<array>",
        f"{ind(4)}<string>{ARCHIVE_UTI}</string>",
        f"{ind(3)}</array>",
        f"{ind(2)}</dict>",
    ]

    uti = [
        f"{ind(2)}<dict>",
        f"{ind(3)}<key>UTTypeIdentifier</key>",
        f"{ind(3)}<string>{ARCHIVE_UTI}</string>",
        f"{ind(3)}<key>UTTypeDescription</key>",
        f"{ind(3)}<string>7-Zip Archive</string>",
        f"{ind(3)}<key>UTTypeConformsTo</key>",
        f"{ind(3)}<array>",
        f"{ind(4)}<string>public.archive</string>",
        f"{ind(4)}<string>public.data</string>",
        f"{ind(3)}</array>",
        f"{ind(3)}<key>UTTypeTagSpecification</key>",
        f"{ind(3)}<dict>",
    ]
    uti.append(str_array("public.filename-extension", extensions, 4))
    uti += [f"{ind(3)}</dict>", f"{ind(2)}</dict>"]

    services = [service_dict(m, l, t, 2) for m, l, t in SERVICES]

    head = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
        '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
        '<plist version="1.0">',
        '<dict>',
        f'{ind(1)}<key>CFBundleDevelopmentRegion</key>',
        f'{ind(1)}<string>en</string>',
        # 声明 bundle 支持哪些语言。LaunchServices 靠这个（而不只是 Resources 里
        # 有哪些 .lproj）来挑语言，服务菜单的名字也按它翻。
        f'{ind(1)}<key>CFBundleLocalizations</key>',
        f'{ind(1)}<array>',
    ] + [f'{ind(2)}<string>{c}</string>' for c in LANG_CODES] + [
        f'{ind(1)}</array>',
        f'{ind(1)}<key>CFBundleExecutable</key>',
        f'{ind(1)}<string>{APP_NAME}</string>',
        f'{ind(1)}<key>CFBundleIconFile</key>',
        f'{ind(1)}<string>AppIcon</string>',
        f'{ind(1)}<key>CFBundleIdentifier</key>',
        f'{ind(1)}<string>{BUNDLE_ID}</string>',
        f'{ind(1)}<key>CFBundleInfoDictionaryVersion</key>',
        f'{ind(1)}<string>6.0</string>',
        f'{ind(1)}<key>CFBundleName</key>',
        f'{ind(1)}<string>{APP_NAME}</string>',
        f'{ind(1)}<key>CFBundleDisplayName</key>',
        f'{ind(1)}<string>{APP_NAME}</string>',
        f'{ind(1)}<key>CFBundlePackageType</key>',
        f'{ind(1)}<string>APPL</string>',
        f'{ind(1)}<key>CFBundleShortVersionString</key>',
        f'{ind(1)}<string>{VERSION}</string>',
        f'{ind(1)}<key>CFBundleVersion</key>',
        f'{ind(1)}<string>{VERSION}</string>',
        f'{ind(1)}<key>CFBundleSignature</key>',
        f'{ind(1)}<string>????</string>',
        f'{ind(1)}<key>LSApplicationCategoryType</key>',
        f'{ind(1)}<string>public.app-category.utilities</string>',
        f'{ind(1)}<key>LSMinimumSystemVersion</key>',
        f'{ind(1)}<string>{MIN_OS}</string>',
        f'{ind(1)}<key>NSHighResolutionCapable</key>',
        f'{ind(1)}<true/>',
        f'{ind(1)}<key>NSPrincipalClass</key>',
        f'{ind(1)}<string>NSApplication</string>',
        f'{ind(1)}<key>NSHumanReadableCopyright</key>',
        f'{ind(1)}<string>7-Zip {VERSION} (C) Igor Pavlov. GUI front end for macOS.</string>',
        f'{ind(1)}<key>NSSupportsAutomaticTermination</key>',
        f'{ind(1)}<false/>',
        f'{ind(1)}<key>NSSupportsSuddenTermination</key>',
        f'{ind(1)}<false/>',
    ]

    out = head + [
        f'{ind(1)}<key>CFBundleDocumentTypes</key>',
        f'{ind(1)}<array>',
    ] + documented + [
        f'{ind(1)}</array>',
        f'{ind(1)}<key>UTExportedTypeDeclarations</key>',
        f'{ind(1)}<array>',
    ] + uti + [
        f'{ind(1)}</array>',
        f'{ind(1)}<key>NSServices</key>',
        f'{ind(1)}<array>',
    ] + services + [
        f'{ind(1)}</array>',
        '</dict>',
        '</plist>',
        '',
    ]
    return "\n".join(out)


def main() -> int:
    data = json.loads(TYPES.read_text(encoding="utf-8"))
    exts = sorted(set(data["extensions"]))
    # 001 这种分卷后缀不是独立的文档类型，去掉更干净
    exts = [e for e in exts if not e.isdigit()]
    OUT.write_text(build(exts), encoding="utf-8")
    print(f"写出 {OUT.relative_to(ROOT)}：{len(exts)} 个扩展名，{len(SERVICES)} 个服务")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
