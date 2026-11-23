# 仅修复索引页码超链接：刷新 .ind 后重编译主文档（lualatex），复用已缓存外部图。
# 用法: pwsh -File _rebuild_index_links.ps1   （Windows PowerShell 5.1 / PowerShell 7 均可）
$ErrorActionPreference = 'Continue'

$DIR       = 'D:\pgfplots\pgfplots'
$LUALATEX  = 'C:\texlive\2026\bin\windows\lualatex.exe'
$MAKEINDEX = 'C:\texlive\2026\bin\windows\makeindex.exe'
# gnuplot 6.0.5 安装在该目录，但安装程序未把它登记进系统/用户 PATH，这里注入到子进程 PATH。
$GNUPLOT_BIN = 'D:\Program Files\gnuplot\bin'
Set-Location $DIR

# 把 gnuplot 加入子进程 PATH
$env:PATH = "$GNUPLOT_BIN;$env:PATH"

# AcroTeX 宏包在项目子目录（insdljs/eforms 等不在 TeX Live 发行版中），需加入搜索路径
$env:TEXINPUTS = "./;./acrotex/;./acrotex-js/;./plotdata/;" + $env:TEXINPUTS

function Invoke-Step {
    param(
        [string]   $Name,
        [string]   $Exe,
        [string[]] $Arguments
    )

    Write-Host ">>> [$(Get-Date -Format HH:mm:ss)] 开始 $Name"
    $t0 = Get-Date

    $out = Join-Path $DIR "_out_$Name.txt"
    $err = Join-Path $DIR "_err_$Name.txt"

    # 直接调用外部程序，标准输出/错误分别落到临时文件，用 $LASTEXITCODE 取退出码
    # （比 Start-Process 的 ExitCode 在 5.1/7 下都更可靠）。
    & $Exe @Arguments 1> $out 2> $err
    $code = $LASTEXITCODE

    $dt   = [int]((Get-Date) - $t0).TotalSeconds
    Write-Host ">>> [$(Get-Date -Format HH:mm:ss)] $Name 完成 退出码=$code 耗时=${dt}s"

    Remove-Item $out, $err -Force -ErrorAction SilentlyContinue
    return $code
}

# 本机已安装 gnuplot 6.0.5（路径见 $GNUPLOT_BIN），开启 -shell-escape：
# pgfplots 仅在缓存表缺失/过期时才现场调用 gnuplot 重算，已有匹配的缓存表与外部化图 PDF 仍直接复用。
# 注意：\write18 经 cmd 派生，子进程 PATH 需能解析到 System32 与 gnuplot（正常终端默认满足）。
$latexArgs = @('-shell-escape', '-interaction=nonstopmode', 'pgfplots.tex')

# pass 1: 嵌入新 .ind，刷新 aux/idx
Invoke-Step 'lualatex-pass1' $LUALATEX $latexArgs
# 用最新 .idx 重建 .ind（带超链接包裹）
Invoke-Step 'makeindex' $MAKEINDEX @('-s', '_gind_fix.ist', 'pgfplots')
# pass 2/3: 稳定交叉引用与索引页码
Invoke-Step 'lualatex-pass2' $LUALATEX $latexArgs
Invoke-Step 'lualatex-pass3' $LUALATEX $latexArgs

# 检查结果
if (Test-Path 'pgfplots.pdf') {
    $size = (Get-Item 'pgfplots.pdf').Length
    Write-Host "`npgfplots.pdf 大小: $size"
}

# 检查日志致命错误（行首以 "! " 开头）
if (Test-Path 'pgfplots.log') {
    $log   = Get-Content 'pgfplots.log' -Raw -Encoding UTF8
    $fatal = [regex]::Matches($log, '(?m)^! .+')
    Write-Host "致命错误行数: $($fatal.Count)"
    $fatal | Select-Object -First 10 | ForEach-Object {
        $line = $_.Value
        if ($line.Length -gt 160) { $line = $line.Substring(0, 160) }
        Write-Host "  ! $line"
    }
}
