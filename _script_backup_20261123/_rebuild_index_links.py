# -*- coding: utf-8 -*-
# 仅修复索引页码超链接：刷新 .ind 后重编译主文档（lualatex），复用已缓存外部图。
import subprocess, os, sys, io, time, re
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

DIR = r"D:\pgfplots\pgfplots"
LUALATEX = r"C:\texlive\2026\bin\windows\lualatex.exe"
MAKEINDEX = r"C:\texlive\2026\bin\windows\makeindex.exe"
# gnuplot 6.0.5 安装在该目录，但安装程序未把它登记进系统/用户 PATH，这里注入到子进程 PATH。
GNUPLOT_BIN = r"D:\Program Files\gnuplot\bin"
os.chdir(DIR)
os.environ["PATH"] = GNUPLOT_BIN + os.pathsep + os.environ.get("PATH", "")
os.environ["TEXINPUTS"] = "./;./acrotex/;./acrotex-js/;./plotdata/;" + os.environ.get("TEXINPUTS", "")

def run(name, cmd, timeout=1800):
    print(f">>> [{time.strftime('%H:%M:%S')}] 开始 {name}", flush=True)
    t0 = time.time()
    try:
        r = subprocess.run(cmd, cwd=DIR, capture_output=True, timeout=timeout,
                           text=True, encoding="utf-8", errors="replace", env=os.environ.copy())
        dt = int(time.time()-t0)
        print(f">>> [{time.strftime('%H:%M:%S')}] {name} 完成 退出码={r.returncode} 耗时={dt}s", flush=True)
        return r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        print(f">>> {name} 超时 {timeout}s", flush=True)
        return -1, "", "timeout"

# 本机已安装 gnuplot 6.0.5（路径见 GNUPLOT_BIN），开启 -shell-escape：
# pgfplots 仅在缓存表缺失/过期时才现场调用 gnuplot 重算，已有匹配的缓存表与外部化图 PDF 仍直接复用。
# 注意：\write18 经 cmd 派生，子进程 PATH 需能解析到 System32 与 gnuplot（正常终端默认满足）。
LATEX = [LUALATEX, "-shell-escape", "-interaction=nonstopmode", "pgfplots.tex"]

# pass 1: 嵌入新 .ind，刷新 aux/idx
run("lualatex-pass1", LATEX)
# 用最新 .idx 重建 .ind（带超链接包裹）
run("makeindex", [MAKEINDEX, "-s", "_gind_fix.ist", "pgfplots"])
# pass 2/3: 稳定交叉引用与索引页码
run("lualatex-pass2", LATEX)
run("lualatex-pass3", LATEX)

if os.path.exists("pgfplots.pdf"):
    print(f"\npgfplots.pdf 大小: {os.path.getsize('pgfplots.pdf')}", flush=True)

# 检查日志致命错误
with open("pgfplots.log", encoding="utf-8", errors="replace") as f:
    log = f.read()
fatal = re.findall(r"^! .+", log, re.M)
print("致命错误行数:", len(fatal))
for x in fatal[:10]:
    print("  !", x[:160])
