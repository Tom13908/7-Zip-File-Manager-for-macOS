#!/usr/bin/env python3
"""逐语言验证：App 里的界面文案确实换成了那一种语言。

做法是真的把 App 起起来（`-AppleLanguages "(xx)" --automation`），问它一句 `lang`，
让它把 bundle 里那份 .lproj 的每一条文案都查一遍报回来，再和
resources/l10n/<语言>.strings 里的权威译文逐条对。

为什么不直接读 .lproj 文件：文件在不在、写得对不对，和「系统在这个语言下到底
挑中哪一份」是两件事。只有让 App 自己查一遍才算证据。

同时核对 Finder 服务菜单（ServicesMenu.strings）—— 右键菜单的语言和软件语言同步，
判据就是这次查表的结果。

用法：python3 tools/l10nprobe.py [App 包路径]
退出码：0 全对；1 有对不上的项。
"""

import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
L10N = ROOT / "resources" / "l10n"

CODES = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "de", "fr", "es", "pt-BR", "it", "ru"]

# 系统给的语言标签比 .lproj 名字细，应当归并到我们有的那一份上
FALLBACK = [("zh-Hans-CN", "zh-Hans"), ("zh-Hant-TW", "zh-Hant"), ("en-GB", "en"),
            ("ja-JP", "ja"), ("xx-YY", "en")]

ENTRY = re.compile(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;')

# 服务菜单那几条的名字，从 Info.plist 读，与 mkinfo.py 保持单一出处
def _service_titles() -> list:
    import plistlib
    plist = plistlib.loads((ROOT / "resources" / "Info.plist").read_bytes())
    return [d["NSMenuItem"]["default"] for d in plist["NSServices"]]


SERVICE_TITLES = _service_titles()


def unescape(s: str) -> str:
    out, i = [], 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(s[i + 1], s[i + 1]))
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


def query(app: str, lang, workdir: str):
    """起一次 App，问一句 lang，把 (语言, 全部文案) 取回来。"""
    args = [app, "--automation", "--panels", "1", "--open", workdir]
    if lang:
        args += ["-AppleLanguages", f"({lang})"]
    p = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.DEVNULL, text=True)
    try:
        ready = p.stdout.readline()
        if not ready.startswith("ready"):
            raise RuntimeError(f"App 没起来：{ready.strip()!r}")
        p.stdin.write("lang\n")
        p.stdin.flush()

        meta, rows = {}, []
        while True:
            line = p.stdout.readline()
            if not line:
                break
            line = line.rstrip("\n")
            if line == "end":
                break
            if line.startswith("ok "):
                for kv in line[3:].split(" "):
                    k, _, v = kv.partition("=")
                    meta[k] = v
            elif line[:2] in ("l\t", "s\t"):
                where, k, v = line.split("\t", 2)
                rows.append((where, unescape(k), unescape(v)))
        return meta, rows
    finally:
        try:
            p.stdin.write("quit\n")
            p.stdin.flush()
        except Exception:
            pass
        p.terminate()
        try:
            p.wait(timeout=5)
        except subprocess.TimeoutExpired:
            p.kill()


def main() -> int:
    bundle = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 \
        else ROOT / "build" / "7-Zip File Manager.app"
    app = bundle / "Contents" / "MacOS" / "7-Zip File Manager"
    if not os.path.exists(app):
        print(f"找不到可执行文件：{app}", file=sys.stderr)
        return 1

    want_all = {c: read_strings(L10N / f"{c}.strings") for c in CODES}
    n_keys = len(want_all["en"])
    workdir = "/tmp"

    rc = 0
    for code in CODES:
        meta, rows = query(str(app), code, workdir)
        want = want_all[code]
        got = {}
        bad = []

        if meta.get("lang") != code:
            bad.append(f"挑中的语言是 {meta.get('lang')}，不是 {code}")
        have = (meta.get("available") or "").split(",")
        if sorted(set(have)) != sorted(CODES):
            bad.append(f"包里的语言是 {sorted(set(have))}，应是 {sorted(CODES)}")

        n_svc = 0
        for where, k, v in rows:
            got[k] = v
            if where == "s":
                n_svc += 1
            if want.get(k) is None:
                bad.append(f"{k!r} 不在 {code}.strings 里")
            elif v != want[k]:
                bad.append(f"{k!r}: 期望 {want[k]!r}，实际 {v!r}")
        for k in want:
            if k not in got:
                bad.append(f"{k!r} 没查出来")

        print(f"{code:8s} {len(rows):4d} 条（服务 {n_svc}） "
              f"{'OK' if not bad else 'FAIL'}")
        for b in bad[:8]:
            print(f"         {b}")
        if len(bad) > 8:
            print(f"         ...还有 {len(bad) - 8} 条")
        if bad:
            rc = 1

    print()
    for probe_lang, expect in FALLBACK:
        meta, _ = query(str(app), probe_lang, workdir)
        got = meta.get("lang")
        ok = got == expect
        verdict = "OK" if ok else f"FAIL（应为 {expect}）"
        print(f"回退 {probe_lang:10s} -> {str(got):8s} {verdict}")
        if not ok:
            rc = 1

    meta, _ = query(str(app), None, workdir)
    system_lang = meta.get("lang")
    print(f"系统语言 -> {system_lang}")

    rc |= check_services_menu(bundle, system_lang)

    print()
    if rc == 0:
        print(f"全部通过：{len(CODES)} 种语言 × {n_keys} 条文案逐条对上，"
              f"服务菜单 {len(SERVICE_TITLES)} 条跟着同一种语言")
    else:
        print("有对不上的项，见上")
    return rc


def check_services_menu(bundle: pathlib.Path, system_lang) -> int:
    """系统「服务」菜单里到底显示什么语言。

    这是整条链的最后一环：pbs 缓存的还是 Info.plist 里的英文原文，显示时才按
    提供方 bundle 的 ServicesMenu.strings 换成本地化名字。系统菜单是客户端拼的，
    所以只能这样读回来，不能靠读文件推断。

    只在本 App 已经装到 /Applications、且装的那一份就是这次构建出来的这一份时
    才判定 —— 否则测的是别的副本，结论没有意义。
    """
    titles_bin = (ROOT / "build" / "serviceslist.app" / "Contents" / "MacOS" / "serviceslist")
    exe = "Contents/MacOS/7-Zip File Manager"
    installed = pathlib.Path("/Applications/7-Zip File Manager.app")
    if not titles_bin.exists():
        print("服务菜单（系统级）：未编译 build/serviceslist.app，跳过")
        return 0
    if not (installed / exe).exists():
        print("服务菜单（系统级）：/Applications 里没有本 App，跳过")
        return 0
    same = (installed / exe).read_bytes() == (bundle / exe).read_bytes()
    if not same:
        print("服务菜单（系统级）：/Applications 里装的是别的构建，跳过"
              "（重装后再跑这条才有意义）")
        return 0

    want = read_strings(L10N / f"{system_lang}.strings") if system_lang else {}
    # serviceslist 是把「服务」菜单真弹出来读标题的，读完靠菜单被关掉才退出 ——
    # 没人管它就永远停在菜单跟踪的事件循环里。给个上限，把无限挂起变成一句报错。
    try:
        out = subprocess.run([str(titles_bin), ""], capture_output=True, text=True,
                             timeout=120).stdout
    except subprocess.TimeoutExpired:
        print("服务菜单（系统级）：列出服务菜单超时（菜单弹出后没被关掉？"
              "按一下 Esc 或点一下别处，再跑一次）")
        return 1
    listed = out.splitlines()

    # 同一个服务如果还有别的副本在提供，系统会给它加一个「 (App 名)」后缀做区分
    def appeared(name: str) -> bool:
        return any(t == name or t.startswith(name + " (") for t in listed)

    missing = [t for t in SERVICE_TITLES if not appeared(want.get(t, t))]
    if missing:
        print(f"服务菜单（系统级）：{system_lang} 下这几条没出现：{missing}")
        return 1
    print(f"服务菜单（系统级）：{system_lang} 下 {len(SERVICE_TITLES)} 条全部以"
          f"{system_lang}出现在系统服务菜单里")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
