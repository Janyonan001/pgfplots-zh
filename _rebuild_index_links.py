# -*- coding: utf-8 -*-
"""
通用手册重编译流水线：引擎 -> makeindex -> 引擎 -> 引擎，收敛交叉引用与索引页码。
- 目录自动定位到脚本所在位置；编译器 / makeindex / gnuplot 优先从 PATH 查找，找不到再回退常见安装路径。
- 换文档时只需修改下方「可配置项」，无需改动下面的流程代码。
"""
import subprocess, os, sys, io, time, re, shutil

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

# ===================== 可配置项（换文档只改这里） =====================
MAIN_TEX         = "pgfplots.tex"        # 主文档文件名（相对脚本目录）
JOBNAME          = "pgfplots"            # 任务名（与主文档同名，不含扩展名）
INDEX_STYLE      = "_gind_fix.ist"       # makeindex 样式文件；不需要样式可置 None
EXTRA_TEXINPUTS  = [".", "./acrotex/", "./acrotex-js/", "./plotdata/"]  # 额外宏包/数据子目录
ENGINE           = "lualatex"             # 引擎: lualatex / xelatex / pdflatex
SHELL_ESCAPE     = True                   # 需调用 gnuplot / 外部命令时为 True
TIMEOUT          = 1800                   # 单步超时（秒）
# 编译器回退目录（PATH 找不到时按顺序查找；留空列表则只认 PATH）
TL_BIN_FALLBACK      = [r"C:\texlive\2026\bin\windows"]
GNUPLOT_BIN_FALLBACK = [r"D:\Program Files\gnuplot\bin"]
# =====================================================================

DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(DIR)


def resolve(exe_name, fallback_dirs):
    """优先从 PATH 查找可执行文件；找不到再到回退目录里找（Windows 自动补 .exe）。"""
    found = shutil.which(exe_name)
    if found:
        return found
    exe = exe_name + (".exe" if os.name == "nt" else "")
    for d in fallback_dirs:
        cand = os.path.join(d, exe)
        if os.path.isfile(cand):
            return cand
    return exe_name  # 最后退回原名，交给系统报错


# gnuplot 目录注入子进程 PATH（若存在）
for d in GNUPLOT_BIN_FALLBACK:
    if os.path.isdir(d):
        os.environ["PATH"] = d + os.pathsep + os.environ.get("PATH", "")

# 额外宏包 / 数据目录加入 TeX 搜索路径
os.environ["TEXINPUTS"] = ";".join(EXTRA_TEXINPUTS) + ";" + os.environ.get("TEXINPUTS", "")

ENGINE_EXE = resolve(ENGINE, TL_BIN_FALLBACK)
MAKEINDEX  = resolve("makeindex", TL_BIN_FALLBACK)

latex_base = [ENGINE_EXE]
if SHELL_ESCAPE:
    latex_base.append("-shell-escape")
latex_base += ["-interaction=nonstopmode", MAIN_TEX]


def run(name, cmd):
    print(f">>> [{time.strftime('%H:%M:%S')}] 开始 {name}", flush=True)
    t0 = time.time()
    try:
        r = subprocess.run(cmd, cwd=DIR, capture_output=True, timeout=TIMEOUT,
                            text=True, encoding="utf-8", errors="replace",
                            env=os.environ.copy())
        dt = int(time.time() - t0)
        print(f">>> [{time.strftime('%H:%M:%S')}] {name} 完成 退出码={r.returncode} 耗时={dt}s", flush=True)
        return r.returncode
    except subprocess.TimeoutExpired:
        print(f">>> {name} 超时 {TIMEOUT}s", flush=True)
        return -1


# pass 1: 嵌入新 .ind，刷新 aux/idx
run("engine-pass1", latex_base)
# 用最新 .idx 重建 .ind（带超链接包裹）
if INDEX_STYLE:
    run("makeindex", [MAKEINDEX, "-s", INDEX_STYLE, JOBNAME])
else:
    run("makeindex", [MAKEINDEX, JOBNAME])
# pass 2/3: 稳定交叉引用与索引页码
run("engine-pass2", latex_base)
run("engine-pass3", latex_base)

# 检查结果
pdf = JOBNAME + ".pdf"
if os.path.exists(pdf):
    print(f"\n{pdf} 大小: {os.path.getsize(pdf)}", flush=True)

log = JOBNAME + ".log"
if os.path.exists(log):
    with open(log, encoding="utf-8", errors="replace") as f:
        text = f.read()
    fatal = re.findall(r"^! .+", text, re.M)
    print("致命错误行数:", len(fatal))
    for x in fatal[:10]:
        print("  !", x[:160])
