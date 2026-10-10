#!/usr/bin/env python3
"""验证 Finder 右键菜单（服务）这条通路。

界面内的按钮回归（tools/uiprobe.py）测不到这条路：服务由 LaunchServices 另起一个
进程，走的是 applicationWillFinishLaunching → servicesProvider，中间还要经过
粘贴板、启动时序、主窗口判定。这条通路一旦出问题，用户看到的是
「App 弹出来，然后什么都不发生」—— 既没有动作也没有提示，最难查。

做法：把一个真实文件放进通用粘贴板，再按服务名请求系统执行（与 Finder 做的事相同），
然后检查三件事：
  1) 该发生的文件动作发生了；
  2) 该弹的窗口弹了（对话框型服务）；
  3) **主窗口没有冒出来** —— 服务调用不该带走一个主窗口。

用法：tools/svcprobe.py
环境变量：ZIPFM_BUNDLE 指定别的 App 包（默认 build 里那份）。
"""

import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUNDLE = os.environ.get("ZIPFM_BUNDLE") or os.path.join(ROOT, "build", "7-Zip File Manager.app")
APP = os.path.join(BUNDLE, "Contents", "MacOS", "7-Zip File Manager")
SZZ = os.path.join(BUNDLE, "Contents", "Resources", "7zz")
SVC = os.path.join(ROOT, "build", "svcrun")
WINLIST = os.path.join(ROOT, "build", "winlist")
FIX = "/tmp/7zip-svctest"


def run(*args):
    return subprocess.run(args, capture_output=True, text=True)


def kill():
    run("pkill", "-f", "7-Zip File Manager")
    time.sleep(1.5)


def windows():
    """App 当前在屏幕上的窗口，返回 [(size, layer)]。窗口标题要屏幕录制权限，所以不看。"""
    out = run(WINLIST, "7-Zip").stdout
    res = []
    for line in out.splitlines():
        if not line.startswith("owner="):
            continue
        s = re.search(r"size=(\S+)", line)
        l = re.search(r"layer=(-?\d+)", line)
        if s and l:
            res.append((s.group(1), l.group(1)))
    return res


def trigger(service, *files):
    r = run(SVC, service, *files)
    if "found=1" not in r.stdout:
        return None
    return r.stdout.strip()


def fixture():
    shutil.rmtree(FIX, ignore_errors=True)
    os.makedirs(os.path.join(FIX, "payload"))
    with open(os.path.join(FIX, "one.txt"), "w") as f:
        f.write("aaa")
    with open(os.path.join(FIX, "payload", "inner.txt"), "w") as f:
        f.write("inner")
    # 只有单个顶层目录：智能解压应当把它整体摊到压缩包所在目录
    subprocess.run([SZZ, "a", os.path.join(FIX, "test.7z"), "payload", "-bso0", "-bsp0"],
                   cwd=FIX, check=True)
    # 只有单个文件
    with open(os.path.join(FIX, "solo.txt"), "w") as f:
        f.write("solo")
    subprocess.run([SZZ, "a", os.path.join(FIX, "single.7z"), "solo.txt", "-bso0", "-bsp0"],
                   cwd=FIX, check=True)
    # 多个顶层项、全是文件：智能解压不包 —— 直接摊在压缩包所在目录。
    # 名字要和留在 fixture 里的 one.txt 错开，否则解出来是覆盖同名文件，
    # 目录列表看不出变化，这条用例就永远都能「通过」。
    for n in ("m1.txt", "m2.txt"):
        with open(os.path.join(FIX, n), "w") as f:
            f.write("multi")
    subprocess.run([SZZ, "a", os.path.join(FIX, "multi.7z"), "m1.txt", "m2.txt",
                    "-bso0", "-bsp0"], cwd=FIX, check=True)
    # 多个顶层项、其中有目录：智能解压要新建一个与压缩包同名的文件夹
    for d in ("d1", "d2"):
        os.makedirs(os.path.join(FIX, d))
        with open(os.path.join(FIX, d, "inner.txt"), "w") as f:
            f.write(d)
    subprocess.run([SZZ, "a", os.path.join(FIX, "dirs.7z"), "d1", "d2",
                    "-bso0", "-bsp0"], cwd=FIX, check=True)
    shutil.rmtree(os.path.join(FIX, "payload"))
    os.remove(os.path.join(FIX, "solo.txt"))
    for n in ("m1.txt", "m2.txt"):
        os.remove(os.path.join(FIX, n))
    for d in ("d1", "d2"):
        shutil.rmtree(os.path.join(FIX, d))
    with open(os.path.join(FIX, "plain.bin"), "w") as f:
        f.write("definitely not an archive")


def main_sizes():
    """正常启动一次量出主窗口尺寸。服务调用时出现这个尺寸的窗口就是错的。"""
    kill()
    run("open", BUNDLE)
    time.sleep(4)
    seen = sorted({s for s, _ in windows()})
    kill()
    return seen


results = []


def report(name, expect, got, ok):
    results.append(ok)
    print("%-26s 期望 %-30s 实际 %-30s %s"
          % (name, expect, got, "OK" if ok else "FAIL"))


def content():
    return sorted(os.listdir(FIX))


def case(name, service, targets, expect_content, need_window=None):
    """跑一个服务用例。
    expect_content: 结束后 fixture 目录里应当出现的文件名（完整列表）
    need_window:    True/False —— 是否应当至少有一个窗口
    """
    kill()
    fixture()
    before = content()
    line = trigger(service, *[os.path.join(FIX, t) for t in targets])
    if line is None:
        report(name, "服务可被调用", "系统里找不到该服务", False)
        return
    time.sleep(4)
    ws = windows()
    after = content()

    added = [f for f in after if f not in before]
    report(name + "（文件动作）", ",".join(sorted(expect_content)),
           ",".join(added) if added else "（无新文件）",
           sorted(added) == sorted(expect_content))

    stray = [s for s, _ in ws if s in MAIN_SIZES]
    report(name + "（没弹主窗口）", "无 %s 尺寸的窗口" % MAIN_SIZES,
           ("出现了 " + ",".join(stray)) if stray else "未出现", not stray)

    if need_window is not None:
        report(name + "（窗口）", "有窗口" if need_window else "无窗口",
               "有 %d 个" % len(ws) if ws else "无窗口", bool(ws) == need_window)


def main():
    for tool, src in ((SVC, "tools/svcrun.swift"), (WINLIST, "tools/winlist.swift")):
        if not os.path.exists(tool):
            print("缺少 %s，先跑 scripts/verify-ui.sh 生成" % tool)
            return 1

    global MAIN_SIZES
    MAIN_SIZES = main_sizes()
    print("主窗口尺寸（服务调用时不该出现）：%s" % MAIN_SIZES)

    # 解压到当前文件夹。归档里的 payload/ 会落在 fixture 根下。
    case("Extract Here", "Extract Here", ["test.7z"], ["payload"])

    # 做完之后：进度窗口自己关掉，App 也不该继续挂在后台。
    # 以前它会停在 0% 上不动，看起来就像解压卡住了 —— 用户报的就是这个。
    kill()
    fixture()
    trigger("Extract Here", os.path.join(FIX, "test.7z"))
    time.sleep(4)
    ws = windows()
    report("解压完进度窗自己关", "无窗口", ("有 %d 个" % len(ws)) if ws else "无窗口", not ws)
    alive = run("pgrep", "-f", "7-Zip File Manager").stdout.split()
    report("解压完 App 自己退出", "0 个进程", "%d 个进程" % len(alive), not alive)

    # 大一点的归档：解压要花上一两秒，进度条真的动过，做完仍然要自己关掉
    kill()
    fixture()
    blob = os.path.join(FIX, "blob.bin")
    with open(blob, "wb") as f:
        f.write(os.urandom(1024) * 24000)      # 24 MB，压不动
    big = os.path.join(FIX, "big.7z")
    subprocess.run([SZZ, "a", big, "blob.bin", "-mx1", "-bso0", "-bsp0"], cwd=FIX, check=True)
    os.remove(blob)
    trigger("Extract Here", big)
    time.sleep(6)
    got = "blob.bin" if os.path.exists(os.path.join(FIX, "blob.bin")) else "（无）"
    report("大归档解压出来", "blob.bin", got, got == "blob.bin")
    ws = windows()
    report("大归档解压完窗口也关", "无窗口", ("有 %d 个" % len(ws)) if ws else "无窗口", not ws)

    kill()
    fixture()
    trigger("Extract Here", os.path.join(FIX, "test.7z"))
    time.sleep(4)
    got = "payload/inner.txt" if os.path.exists(os.path.join(FIX, "payload", "inner.txt")) else "（无）"
    report("Extract Here（归档内容）", "payload/inner.txt", got,
           got == "payload/inner.txt")

    # 智能解压：包内结构决定落点（见 src/SmartExtract.swift）
    #   单个顶层目录 -> 那个目录整体落在压缩包所在目录
    case("Extract (Smart) 单目录", "Extract (Smart)", ["test.7z"], ["payload"])
    #   单个文件 -> 直接落在压缩包所在目录
    case("Extract (Smart) 单文件", "Extract (Smart)", ["single.7z"], ["solo.txt"])
    #   多个顶层项、全是文件 -> 摊在压缩包所在目录，不新建文件夹
    case("Extract (Smart) 多项全是文件", "Extract (Smart)", ["multi.7z"], ["m1.txt", "m2.txt"])
    #   多个顶层项、其中有目录 -> 新建一个与压缩包同名的文件夹
    case("Extract (Smart) 多项含目录", "Extract (Smart)", ["dirs.7z"], ["dirs"])

    # 弹出解压对话框（目标路径自己在对话框里选）
    case("Extract to…", "Extract to…", ["test.7z"], [], need_window=True)
    # 弹出压缩对话框（格式在对话框里选）
    case("Compress with 7-Zip…", "Compress with 7-Zip…", ["one.txt"], [], need_window=True)

    # 校验归档：结果就是那一句 OK，进度窗口关掉之后必须留下提示，
    # 否则「测完了」和「什么都没发生」在界面上是一样的。
    kill()
    fixture()
    trigger("Test Archive", os.path.join(FIX, "test.7z"))
    time.sleep(4)
    ws = windows()
    report("Test Archive（有结果提示）", "至少一个窗口",
           ("有 %d 个" % len(ws)) if ws else "无窗口", bool(ws))

    # 非归档文件走解压：不能静默什么都不做，也不能弹主窗口
    kill()
    fixture()
    trigger("Extract Here", os.path.join(FIX, "plain.bin"))
    time.sleep(4)
    ws = windows()
    stray = [s for s, _ in ws if s in MAIN_SIZES]
    report("非归档（要有反应）", "至少一个窗口", "有 %d 个" % len(ws) if ws else "无窗口",
           bool(ws))
    report("非归档（没弹主窗口）", "无 %s 尺寸的窗口" % MAIN_SIZES,
           ("出现了 " + ",".join(stray)) if stray else "未出现", not stray)

    kill()
    shutil.rmtree(FIX, ignore_errors=True)
    ok = sum(1 for r in results if r)
    print()
    print("通过 %d/%d" % (ok, len(results)))
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
