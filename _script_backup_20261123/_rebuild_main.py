# -*- coding: utf-8 -*-
# 主文档完整重编译（按编译方法.txt顺序）
import subprocess, os, sys, io, time
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

os.chdir('D:\\pgfplots\\pgfplots')
XELATEX = 'C:\\texlive\\2026\\bin\\windows\\xelatex.exe'
MAKEINDEX = 'C:\\texlive\\2026\\bin\\windows\\makeindex.exe'
BIBTEX = 'C:\\texlive\\2026\\bin\\windows\\bibtex.exe'

steps = [
    ('xelatex-1', [XELATEX, '-shell-escape', '-interaction=nonstopmode', 'pgfplots.tex'], 1800),
    ('makeindex', [MAKEINDEX, 'pgfplots'], 120),
    ('xelatex-2', [XELATEX, '-shell-escape', '-interaction=nonstopmode', 'pgfplots.tex'], 1800),
    ('bibtex', [BIBTEX, 'pgfplots'], 120),
    ('xelatex-3', [XELATEX, '-shell-escape', '-interaction=nonstopmode', 'pgfplots.tex'], 1800),
    ('xelatex-4', [XELATEX, '-shell-escape', '-interaction=nonstopmode', 'pgfplots.tex'], 1800),
]

for name, cmd, timeout in steps:
    print(f'>>> 开始: {name}', flush=True)
    t0 = time.time()
    try:
        r = subprocess.run(cmd, cwd='D:\\pgfplots\\pgfplots', capture_output=True,
                           timeout=timeout, text=True, encoding='utf-8', errors='replace')
        print(f'>>> {name} 完成 (退出码 {r.returncode}, {int(time.time()-t0)}s)', flush=True)
    except subprocess.TimeoutExpired:
        print(f'>>> {name} 超时', flush=True)

# 检查结果
if os.path.exists('pgfplots.pdf'):
    print(f'\npgfplots.pdf 大小: {os.path.getsize("pgfplots.pdf")}', flush=True)
