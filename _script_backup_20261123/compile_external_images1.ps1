# 批量生成 pgfplots 手册外部化图片（模拟 make 行为）
# 用法: pwsh -File compile_external_images.ps1
$ErrorActionPreference = 'Continue'
Set-Location 'D:\pgfplots\pgfplots'

# 从 makefile 提取所有编译命令（以tab开头的xelatex命令行）
$makefile = Get-Content 'pgfplots.makefile'
$commands = $makefile | Where-Object { $_ -match 'xelatex -halt-on-error' } | ForEach-Object { $_.Trim() }

Write-Host "共 $($commands.Count) 张图待生成"

$maxConcurrent = 5
$queue = [System.Collections.Queue]::new()
$commands | ForEach-Object { $queue.Enqueue($_) }

$jobs = @()
$startTime = Get-Date
$done = 0
$failed = 0
$failList = @()

while ($queue.Count -gt 0 -or $jobs.Count -gt 0) {
    # 填满并发槽
    while ($queue.Count -gt 0 -and $jobs.Count -lt $maxConcurrent) {
        $cmd = $queue.Dequeue()
        # 提取 jobname 用于判断完成
        if ($cmd -match '-jobname "([^"]+)"') {
            $jobname = $Matches[1]
        } else {
            $jobname = "unknown_$([guid]::NewGuid().ToString('N').Substring(0,8))"
        }
        $p = Start-Process -FilePath 'C:\texlive\2026\bin\windows\xelatex.exe' `
            -ArgumentList @('-halt-on-error','-interaction=batchmode',"-jobname `"$jobname`"",'"\def\tikzexternalrealjob{pgfplots}\input{pgfplots}"') `
            -WorkingDirectory 'D:\pgfplots\pgfplots' `
            -RedirectStandardError "D:\pgfplots\pgfplots\_err_$([guid]::NewGuid().ToString('N').Substring(0,6)).txt" `
            -RedirectStandardOutput "D:\pgfplots\pgfplots\_out_$([guid]::NewGuid().ToString('N').Substring(0,6)).txt" `
            -PassThru -WindowStyle Hidden
        $jobs += [PSCustomObject]@{ Proc = $p; JobName = $jobname }
    }
    # 检查完成
    $jobs = @($jobs | Where-Object {
        if ($_.Proc.HasExited) {
            $pdfPath = "D:\pgfplots\pgfplots\$($_.JobName).pdf"
            if (Test-Path $pdfPath) {
                $done++
            } else {
                $failed++
                $failList += $_.JobName
            }
            $false
        } else { $true }
    })
    Start-Sleep -Milliseconds 500
}

$elapsed = (Get-Date) - $startTime
Write-Host "完成: 成功 $done, 失败 $failed, 耗时 $([math]::Round($elapsed.TotalMinutes,1)) 分钟"
if ($failList.Count -gt 0) {
    Write-Host "失败列表:"
    $failList | ForEach-Object { Write-Host "  $_" }
}
