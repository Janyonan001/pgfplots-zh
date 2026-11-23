# 通用手册重编译流水线：引擎 -> bibtex -> makeindex -> 引擎 -> 引擎。
# 目录自动定位到脚本所在位置；编译器 / makeindex / gnuplot 优先 PATH 查找，找不到再回退常见路径。
# 用法:
#   右键“使用 PowerShell 运行”，或
#   pwsh -File _rebuild_index_links.ps1            （结束后暂停留窗，便于查看结果/报错）
#   pwsh -File _rebuild_index_links.ps1 -NoPause  （自动化调用，结束即退出）
param([switch]$NoPause)

$ErrorActionPreference = 'Continue'

# 控制台 UTF-8，避免中文输出乱码；重定向 / 无控制台时静默跳过
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# 仅对当前进程放宽执行策略（不改系统 / 用户设置），防止右键被策略拦截
try { Set-ExecutionPolicy -Scope Process Bypass -Force } catch {}

# ===================== 可配置项（换文档只改这里） =====================
$MainTex         = 'pgfplots.tex'
$JobName         = 'pgfplots'
$IndexStyle      = '_gind_fix.ist'   # 不需要索引样式可置 $null
$UseBibtex       = $true             # 第一遍后运行 bibtex 生成 .bbl；无参考文献的文档置 $false
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

function Stop-AndWait {
    param([int]$ExitCode = 0)
    # 交互模式（右键双击）结束后留窗；自动化 -NoPause 或非交互会话直接退出
    if (-not $NoPause -and [Environment]::UserInteractive) {
        Write-Host ''
        Read-Host '编译结束，按回车键关闭窗口'
    }
    exit $ExitCode
}

# 捕获终止性错误：打印原因并留窗，避免右键一闪而过看不到报错
trap {
    Write-Host "`n[错误] $($_.Exception.Message)" -ForegroundColor Red
    Stop-AndWait 1
}

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
$Bibtex    = Resolve-Command 'bibtex' $TlBinFallback

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
# bibtex: 依据 .aux/.bib 生成 .bbl（新增或改动参考文献后必须跑一次）
if ($UseBibtex) {
    Invoke-Step 'bibtex' $Bibtex @($JobName)
}
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

Stop-AndWait 0
