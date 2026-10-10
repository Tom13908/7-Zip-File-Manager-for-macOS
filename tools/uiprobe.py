#!/usr/bin/env python3
"""端到端验证面板的交互：双击进入目录、点「上一级」、Backspace、双击「..」。

用法：tools/uiprobe.py
鼠标动作由 App 自己在进程内合成（走 NSWindow.sendEvent → hitTest → 单元格），
原因见 src/Automation.swift 里 "click" 命令的注释：从后台 shell 起进程时窗口
拿不到前台会话，外部 CGEvent 合成的鼠标事件会被系统丢掉，测出来的结论是假的。
"""

import os
import re
import select
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.environ.get("ZIPFM_APP") or os.path.join(
    ROOT, "build", "7-Zip File Manager.app", "Contents", "MacOS", "7-Zip File Manager")
UICLICK = os.path.join(ROOT, "build", "uiclick")
WINLIST = os.path.join(ROOT, "build", "winlist")
TESTDIR = "/tmp/7zip-uiprobe"


def build_fixture():
    shutil.rmtree(TESTDIR, ignore_errors=True)
    os.makedirs(os.path.join(TESTDIR, "subdir", "deep"))
    os.makedirs(os.path.join(TESTDIR, "another"))
    with open(os.path.join(TESTDIR, "subdir", "deep", "leaf.txt"), "w") as f:
        f.write("x")
    with open(os.path.join(TESTDIR, "zzz.txt"), "w") as f:
        f.write("x")
    szz = os.path.join(ROOT, "build", "7-Zip File Manager.app", "Contents", "Resources", "7zz")
    if os.path.exists(szz):
        subprocess.run([szz, "a", "arch.7z", "subdir", "-bso0", "-bsp0"],
                       cwd=TESTDIR, check=True)


class App:
    def __init__(self):
        # 上一轮留下的实例必须先清掉：两个同名进程同时活着时，
        # 合成出来的鼠标事件会打不到本进程的窗口上，表现为「所有点击都没反应」。
        subprocess.run(["pkill", "-f", "7-Zip File Manager"], capture_output=True)
        time.sleep(0.8)
        # stderr 收起来不要丢掉：App 会把每次合成点击当时的窗口前台状态写在那里，
        # 出问题时这是唯一能分清「点击没生效」和「App 当时不在前台」的证据。
        self.errdir = tempfile.mkdtemp(prefix="7zip-uiprobe-err-")
        self.errfile = open(os.path.join(self.errdir, "stderr.txt"), "w+")
        # 固定成英文：这里的断言看的是菜单条目的文字，跟着系统语言跑会随机器变。
        # 「界面确实被翻译了」由 tools/l10nprobe.py 单独逐语言验。
        self.p = subprocess.Popen([APP, "-AppleLanguages", "(en)",
                                   "--automation", "--open", TESTDIR, "--panels", "1"],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=self.errfile, text=True, bufsize=1)
        ready = self.p.stdout.readline().strip()
        if not ready.startswith("ready"):
            sys.exit("app 没就绪：%r" % ready)
        self._wait_window()
        self.cmd("setdots 0")   # 保证第 0 行是本目录的第一个条目

    def stderr_tail(self):
        try:
            self.errfile.flush()
            with open(os.path.join(self.errdir, "stderr.txt")) as f:
                return [l.rstrip() for l in f.readlines()
                        if "click-cmd" in l or "ignored open" in l]
        except Exception as e:
            return ["<读 stderr 失败：%s>" % e]

    # 窗口起来后等它拿到前台的时间。机器被用户操作时系统会把前台留给用户，
    # 这个过程可能长达十几秒，所以不是看一眼就下结论。
    FOCUS_WAIT = 15.0

    def _wait_window(self):
        """等窗口显示出来、并且 App 到了前台再开始点。

        两种等不到的情况要分开报，因为它们一个是被测功能的问题、一个不是：
          - visible=0：App 压根没建出窗口 —— 被测功能的问题，退出码 1；
          - visible=1 而 active=0：窗口在，但 App 拿不到前台。从后台 shell
            起的进程、或此刻用户正在操作别的 App，系统都不会把前台让给它。
            鼠标事件会被系统丢掉，测下去只能得到假结论，所以按「未执行」
            退出（退出码 77），由调用方报成跳过而不是失败。
        """
        t0 = time.time()
        visible = False
        while time.time() - t0 < self.FOCUS_WAIT:
            r = self.cmd("winrect")
            visible = visible or "visible=1" in r
            if visible and "active=1" in r:
                time.sleep(0.4)
                return
            self.cmd("focus")
            time.sleep(0.2)
        if not visible:
            sys.exit("面板回归失败：主窗口一直没显示出来（App 没建出窗口）")
        print("主窗口已经显示出来，但 App 拿不到前台："
              "系统会把前台留给正在操作的用户，或本进程不是由前台会话启动的。")
        print("这种情况下合成鼠标事件会被系统丢掉，继续测只能得到假结论，"
              "所以本轮面板回归不执行 —— 这是环境状态，不是被测功能的问题。")
        sys.exit(77)

    def cmd(self, c):
        self.p.stdin.write(c + "\n")
        self.p.stdin.flush()
        return self.p.stdout.readline().strip()

    def send(self, c):
        """只发不等回包。模态对话框挡着时命令会卡在里面，回包要等对话框关掉。"""
        self.p.stdin.write(c + "\n")
        self.p.stdin.flush()

    def windows(self):
        """App 当前在屏幕上的窗口，返回 [(尺寸, 层级)]。标题要屏幕录制权限，所以不看。"""
        out = subprocess.run([WINLIST, "7-Zip"], capture_output=True, text=True).stdout
        res = []
        for line in out.splitlines():
            if not line.startswith("owner="):
                continue
            s = re.search(r"size=(\S+)", line)
            l = re.search(r"layer=(-?\d+)", line)
            if s and l:
                res.append((s.group(1), l.group(1)))
        return res

    def path(self):
        m = re.search(r"path=(\S+)", self.cmd("state"))
        return m.group(1) if m else None

    def state(self):
        """path 之外还带 App 自己的前台状态（active/key）——
        合成鼠标事件只在前台窗口才被派发，这是分清「点击没生效」和
        「App 当时不在前台」的唯一依据。"""
        return self.cmd("state")

    def rows(self):
        return self.cmd("names").split("|")

    def sel(self):
        m = re.search(r"sel=\[([^\]]*)\]", self.cmd("state"))
        return m.group(1) if m else None

    def dblclick(self, row, clicks=2):
        return self.cmd("click row %d %d" % (row, clicks))

    def click_up(self):
        """真的点在地址栏那个向上箭头上（走 sendEvent → hitTest），
        不用 performClick —— 那绕过了命中测试，等于没测。"""
        return self.cmd("click up 1")

    def toolbar(self):
        return self.cmd("toolbar")

    def uprect(self):
        m = re.search(r"enabled=(\d)", self.cmd("uprect"))
        return m.group(1) if m else "?"

    def filemenu(self):
        return self.cmd("filemenu")

    def key(self, code, flags=None):
        args = [UICLICK, str(self.p.pid), "key", str(code)]
        if flags:
            args.append(flags)
        subprocess.run(args, check=True)

    def quit(self):
        try:
            self.cmd("quit")
        except Exception:
            pass
        try:
            self.p.wait(timeout=5)
        except Exception:
            self.p.kill()
        # stderr 临时目录自己收掉，别每跑一次就留一份
        try:
            self.errfile.close()
            shutil.rmtree(self.errdir, ignore_errors=True)
        except Exception:
            pass


def report(name, expect, got, extra=None):
    ok = got == expect
    print("%-24s 期望 %-26s 实际 %-26s %s" % (name, expect, got, "OK" if ok else "FAIL"))
    if not ok and extra:
        for l in extra[-12:]:
            print("        %s" % l)
    return ok


def main():
    build_fixture()
    app = App()
    results = []

    print("起始路径：%s" % app.path())
    print("列表：%s" % app.rows())

    focus_log = []

    def wait_path(expect, timeout=6.0):
        """进入归档要起 7zz 列目录，比一次点击慢，等到结果出来为止。
        顺路把每次轮询时 App 的前台状态记下来。"""
        deadline = time.time() + timeout
        del focus_log[:]
        while True:
            st = app.state()
            m = re.search(r"path=(\S+)", st)
            got = m.group(1) if m else None
            a = re.search(r"active=(\d)", st)
            k = re.search(r"key=(\d)", st)
            if a and k and (a.group(1) != "1" or k.group(1) != "1"):
                focus_log.append("active=%s key=%s path=%s" % (a.group(1), k.group(1), got))
            if got == expect or time.time() >= deadline:
                return got
            time.sleep(0.2)

    def focus_note():
        if not focus_log:
            return ["（轮询期间 App 一直在前台 active=1 key=1）"]
        return ["轮询期间有 %d 次不在前台：" % len(focus_log)] + focus_log[:5]

    def go(dirpath, timeout=4.0):
        """把面板摆到一个已知目录再开始下一条断言。
        合成点击的生效可能晚于轮询超时，晚到的那一下会把后面每条断言都带歪 ——
        之前出现「一条失败跟着六条失败」就是这么来的。先归位，失败才互相隔离。"""
        app.cmd("cd " + dirpath)
        got = wait_path(dirpath, timeout)
        if got != dirpath:
            print("%-24s 期望 %-26s 实际 %-26s FAIL（无法归位，后面这条跳过）"
                  % ("归位到 " + dirpath, dirpath, got))
            results.append(False)
            return False
        return True

    def report_path(name, expect, timeout=6.0):
        """路径类断言轮询到结果出现为止：合成点击是异步派发的，
        固定 sleep 会把「派发慢了」误判成「功能没生效」。"""
        got = wait_path(expect, timeout)
        results.append(report(name, expect, got, extra=focus_note() + app.stderr_tail()))

    def wait_sel(expect, timeout=3.0):
        """选中项也是异步派发的：合成出来的鼠标事件要等命令返回后才由主 run loop
        送进窗口，紧接着读到的还是上一次的状态。"""
        deadline = time.time() + timeout
        got = app.sel()
        while got != expect and time.time() < deadline:
            time.sleep(0.15)
            got = app.sel()
        return got

    def dbl(name, row_or_name, expect, start=None):
        if start is not None and not go(start):
            return
        names = app.rows()
        if isinstance(row_or_name, int):
            row = row_or_name
        elif row_or_name in names:
            row = names.index(row_or_name)
        else:
            print("%-24s 当前列表 %s 里没有 %r  FAIL" % (name, names[:4], row_or_name))
            results.append(False)
            return
        print("    [%s] rows=%s row=%d click=%s" % (name, names[:4], row, app.dblclick(row)))
        report_path(name, expect)

    # 0) 单击能不能选中（区分「事件没到列表」和「到了但双击没被识别」）
    app.dblclick(1, clicks=1)
    time.sleep(0.3)
    results.append(report("单击选中", "1", app.sel()))

    # 1) 双击目录进入
    dbl("双击目录行", "another", TESTDIR + "/another", start=TESTDIR)

    # 2) 点地址栏那个「上一级」箭头返回（真实点击，不是 performClick）
    if go(TESTDIR + "/another"):
        print("    [点向上箭头] click=%s" % app.click_up())
        report_path("点向上箭头", TESTDIR)

    # 2b) 根目录下这个按钮要不可用（PanelItems.cpp:523）
    app.cmd("cd /")
    time.sleep(0.3)
    results.append(report("根目录下箭头禁用", "0", app.uprect()))
    app.cmd("cd " + TESTDIR)
    time.sleep(0.3)
    results.append(report("普通目录下箭头可用", "1", app.uprect()))

    # 2c) 主工具栏不跟着选中项变（Windows 里这几个从不置灰；
    #     这里是它的 7 个加一个 macOS 侧独有的「智能解压」= 8）
    app.cmd("setdots 0")
    toolbar = app.toolbar()
    results.append(report("工具栏全可用", "8",
                          str(toolbar.count("=on"))))

    # 3) 连续进入两层
    dbl("双击 subdir", "subdir", TESTDIR + "/subdir", start=TESTDIR)
    dbl("双击 deep", "deep", TESTDIR + "/subdir/deep", start=TESTDIR + "/subdir")

    # 4) Backspace 退一级
    if go(TESTDIR + "/subdir/deep"):
        app.key(51)
        report_path("Backspace 上一级", TESTDIR + "/subdir")

    # 5) Show dots 打开后第一行是「..」，双击它回上一级
    print("setdots 1 -> %s" % app.cmd("setdots 1"))
    if go(TESTDIR):
        names = app.rows()
        print("开 Show dots 后前两行：%s" % names[:2])
        if names and names[0] == "..":
            dbl("双击「..」行", 0, "/tmp")
        else:
            print("%-24s 列表里没有「..」行  FAIL" % "双击「..」行")
            results.append(False)

    def click_row0_selected(name, timeout=3.0):
        """单击选中第一行，等选中真的落上再往下判 —— 菜单的可用性是跟着选中项算的。"""
        app.dblclick(0, clicks=1)
        deadline = time.time() + timeout
        while time.time() < deadline:
            s = app.sel()
            if s:
                return True
            time.sleep(0.15)
        print("%-24s 单击后一直没有选中项  FAIL" % name)
        results.append(False)
        return False

    # 7) 右键菜单不是空的，且进入目录时「Open」可用
    app.cmd("setdots 0")
    if go(TESTDIR):
        menu = app.cmd("ctxmenu")
        print("右键菜单（未选中）：%s" % menu[:150])
        results.append(report("右键菜单有 Open", "1", "1" if "Open(" in menu else "0"))

        if click_row0_selected("选中第一行"):
            menu = app.cmd("ctxmenu")
            print("右键菜单（已选中）：%s" % menu[:150])
            results.append(report("选中后 Open 可用", "Open(on)",
                                  "Open(on)" if "Open(on)" in menu else "Open(off)"))

    # 8) 地址栏敲路径回车
    app.cmd("commit " + TESTDIR + "/subdir")
    report_path("地址栏回车导航", TESTDIR + "/subdir")

    # 8b) File 菜单按选中项置灰：刚导航完没有选中项，大部分该是灰的
    if go(TESTDIR):
        menu = app.filemenu()
        print("File 菜单（未选中）：%s" % menu[:160])
        results.append(report("未选中 Copy To 灰", "Copy To...(off)",
                              "Copy To...(off)" if "Copy To...(off)" in menu else "Copy To...(on)"))
        if click_row0_selected("选中第一行(File 菜单)"):
            menu = app.filemenu()
            results.append(report("选中目录后 Copy To 亮", "Copy To...(on)",
                                  "Copy To...(on)" if "Copy To...(on)" in menu else "Copy To...(off)"))
            results.append(report("选中目录后 View 灰", "View(off)",
                                  "View(off)" if "View(off)" in menu else "View(on)"))

    # 9) Ctrl+PgUp 上一级（Windows 的快捷键）
    if go(TESTDIR + "/subdir"):
        app.key(116, "ctrl")   # 116 = PageUp
        report_path("Ctrl+PgUp 上一级", TESTDIR)

    # 9b) 按住左键在列表上拖动 = 框选多选。以前这里是拖放（把行拖出去），
    # 想选几行只会拉出一个拖动影像，鼠标一松还落到本目录上。
    app.cmd("setdots 0")
    if go(TESTDIR):
        rows = app.rows()
        print("    [拖动 0→2] rows=%s %s" % (rows, app.cmd("drag row 0 2")))
        results.append(report("拖动选中 0-2", "0,1,2", wait_sel("0,1,2")))

        print("    [拖动 3→1] %s" % app.cmd("drag row 3 1"))
        results.append(report("拖动改选 1-3", "1,2,3", wait_sel("1,2,3")))

        results.append(report("拖动不换目录", TESTDIR, app.path()))

        # ⌥ 拖动才是把文件拖出去（保留原来的能力）。它不起框选，
        # 而且拖回本目录松手时不能把文件本身弄没 —— 那正是「先删目标再复制」会踩的坑。
        before = sorted(os.listdir(TESTDIR))
        print("    [⌥拖动 0→2] %s" % app.cmd("drag row 0 2 alt"))
        results.append(report("⌥拖动不起框选", "0", wait_sel("0", timeout=0.8)))
        time.sleep(0.5)
        results.append(report("⌥拖回本目录文件还在", ",".join(before),
                              ",".join(sorted(os.listdir(TESTDIR)))))

        # 合成的 ⌥ 拖动收不了尾：松手那一半只进了 App 自己的事件队列，窗口服务器
        # 那条拖动会话因此一直开着，屏幕上会留下一个跨整屏的拖动影像窗口（实测
        # CGWindowList 里是 layer=500、尺寸等于整块屏幕）。它接管鼠标，之后每一次
        # 点击都被它吃掉 —— 表现出来就是「单击选不中、双击不换目录」，后面每条断言
        # 连着挂，看上去像是一堆功能坏了。发一个 Esc（53）把它取消掉，界面立刻恢复。
        app.key(53)
        time.sleep(0.6)
        app.cmd("click row 0 1")
        results.append(report("Esc 后列表恢复可点", "0", wait_sel("0", timeout=2.0)))

    # 9c) 「拖进窗口 = 压缩」这条语义用合成拖动证不了 —— 拖动的收尾到不了窗口
    # 服务器，drop 就不会触发（见上面那段）。所以直接调落点处理入口，它走的仍是
    # 真实链路：面板 → onFilesDropped → 主窗口的 handleDrop。
    if go(TESTDIR):
        n0 = len(app.windows())
        # 不等回包：它会卡在模态对话框上，直到对话框被关掉才返回。
        app.send("drop " + os.path.join(TESTDIR, "zzz.txt"))
        time.sleep(1.2)
        results.append(report("拖入窗口弹压缩对话框", "1",
                              "1" if len(app.windows()) > n0 else "0"))
        app.key(53)                                  # Esc 关掉对话框
        time.sleep(0.8)
        results.append(report("窗口数复原", str(n0), str(len(app.windows()))))
        # 对话框关掉之后 drop 那条命令才回包。这条回包必须读掉，否则会和后面每条
        # 命令的回包错位一格 —— 用带超时的读，卡住时报出来而不是挂在这里。
        reply = "（没有回包）"
        if select.select([app.p.stdout], [], [], 3.0)[0]:
            reply = app.p.stdout.readline().strip()
        results.append(report("关掉对话框后回包", "ok dropped=1", reply))

    # 10) 双击归档进入（7-Zip 的主用途）
    app.cmd("setdots 0")
    if go(TESTDIR):
        names = app.rows()
        archive = next((n for n in names if n.endswith(".7z")), None)
        if archive:
            print("    [双击归档进入] click=%s" % app.dblclick(names.index(archive)))
            got = wait_path(TESTDIR + "/arch.7z")
            results.append(report("双击归档进入", TESTDIR + "/arch.7z", got,
                                  extra=focus_note() + app.stderr_tail()))
            names = app.rows()
            print("归档内列表：%s" % names)
            results.append(report("归档里能看到 subdir", "1", "1" if "subdir" in names else "0"))
        else:
            print("%-24s fixture 里没有 .7z  FAIL" % "双击归档进入")
            results.append(False)

    # 11) 双击文件只打开它、不该换目录。
    # 放最后：它会把系统默认编辑器拉起来抢焦点，后面就没法再合成点击了。
    app.cmd("setdots 0")
    dbl("双击文件不换目录", "leaf.txt", TESTDIR + "/subdir/deep", start=TESTDIR + "/subdir/deep")

    app.quit()
    print()
    ok = sum(1 for r in results if r)
    print("通过 %d/%d" % (ok, len(results)))
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
