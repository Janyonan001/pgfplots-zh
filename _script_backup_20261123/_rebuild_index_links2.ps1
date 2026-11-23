# 通用手册重编译流水线：引擎 -> makeindex -> 引擎 -> 引擎。
# 目录自动定位到脚本所在位置；编译器 / makeindex / gnuplot 优先 PATH 查找，找不到再回退常见路径。
# 用法: pwsh -File _rebuild_index_links.ps1   （Windows PowerShell 5.1 / PowerShell 7 均可）
$ErrorActionPreference = 'Continue'

# ===================== 可配置项（换文档只改这里） =====================
$MainTex         = 'pgfplots.tex'
$JobName         = 'pgfplots'
$IndexStyle      = '_gind_fix.ist'   # 不需要索引样式可置 $null
$ExtraTexInputs  = @('.', './acrotex/', './acrotex-js/', './plotdata/')
$Engine          = 'lualatex'        # lualatex / xelatex / pdflatex
$ShellEscape     = $true
$TimeoutSec      = 1800
$TlBinFallback   = @('C:\texlive\2026\bin\windows')
$GnuplotFallback = @('D:\Program Files\gnuplot\bin')
# =====================================================================

$DIR = $PSScriptRoot
if (-not $DIR) { $DIR = Split-Path -Parent $MyInvocation.MyCommand.Path }
Set-Location $DIR

function Resolve-Command {
    param([string]$Name, [string[]]$FallbackDirs)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $exe = if ($env:OS -eq 'Windows_NT') { "$Name.exe" } else { $Name }
    foreach ($d in $FallbackDirs) {
        $cand = Join-Path $d $exe
        if (Test-Path $cand) { return $cand }
    }
    return $Name
}

# gnuplot 目录注入子进程 PATH（若存在）
foreach ($d in $GnuplotFallback) {
    if (Test-Path $d) { $env:PATH = "$d;$env:PATH" }
}
# 额外宏包 / 数据目录加入 TeX 搜索路径
$env:TEXINPUTS = ($ExtraTexInputs -join ';') + ';' + $env:TEXINPUTS

$EngineExe = Resolve-Command $Engine $TlBinFallback
$Makeindex = Resolve-Command 'makeindex' $TlBinFallback

$latexArgs = @()
if ($ShellEscape) { $latexArgs += '-shell-escape' }
$latexArgs += @('-interaction=nonstopmode', $MainTex)

function Invoke-Step {
    param([string]$Name, [string]$Exe, [string[]]$Arguments)

    Write-Host ">>> [$(Get-Date -Format HH:mm:ss)] 开始 $Name"
    $t0 = Get-Date

    $out = Join-Path $DIR "_out_$Name.txt"
    $err = Join-Path $DIR "_err_$Name.txt"

    # 直接调用外部程序，标准输出/错误分别落到临时文件，用 $LASTEXITCODE 取退出码。
    & $Exe @Arguments 1> $out 2> $err
    $code = $LASTEXITCODE

    $dt = [int]((Get-Date) - $t0).TotalSeconds
    Write-Host ">>> [$(Get-Date -Format HH:mm:ss)] $Name 完成 退出码=$code 耗时=${dt}s"

    Remove-Item $out, $err -Force -ErrorAction SilentlyContinue
    return $code
}

# pass 1: 嵌入新 .ind，刷新 aux/idx
Invoke-Step 'engine-pass1' $EngineExe $latexArgs
# 用最新 .idx 重建 .ind（带超链接包裹）
if ($IndexStyle) {
    Invoke-Step 'makeindex' $Makeindex @('-s', $IndexStyle, $JobName)
} else {
    Invoke-Step 'makeindex' $Makeindex @($JobName)
}
# pass 2/3: 稳定交叉引用与索引页码
Invoke-Step 'engine-pass2' $EngineExe $latexArgs
Invoke-Step 'engine-pass3' $EngineExe $latexArgs

# 检查结果
$pdf = Join-Path $DIR "$JobName.pdf"
if (Test-Path $pdf) {
    Write-Host "`n$JobName.pdf 大小: $((Get-Item $pdf).Length)"
}

$log = Join-Path $DIR "$JobName.log"
if (Test-Path $log) {
    $logText = Get-Content $log -Raw -Encoding UTF8
    $fatal = [regex]::Matches($logText, '(?m)^! .+')
    Write-Host "致命错误行数: $($fatal.Count)"
    $fatal | Select-Object -First 10 | ForEach-Object {
        $line = $_.Value
        if ($line.Length -gt 160) { $line = $line.Substring(0, 160) }
        Write-Host "  ! $line"
    }
}
