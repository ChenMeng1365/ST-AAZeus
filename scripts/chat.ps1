# ST-AAZeus 命令行对话 — PowerShell 脚本（5.1 兼容，文件须保持 UTF-8 BOM）
# 用法:
#   chat-zeus.cmd                      交互式多轮对话（默认）
#   chat-zeus.cmd "你的问题"           单发直问直答
#   chat-zeus.cmd -NoThink "问题"      关闭思考模式（更快出正文）
#   chat-zeus.cmd -Port 8802           指定服务端口（多模型并行时）
#   chat-zeus.cmd -BaseUrl http://127.0.0.1:8801   显式指定服务地址（默认自动解析 WSL IP）
# 交互命令: /think 开|关|空切换   /clear 清空上下文   /system <设定>   /exit 退出
param(
    [string]$Question = "",
    [string]$Port = "8801",
    [string]$BaseUrl = "",
    [switch]$NoThink,
    [int]$MaxTokens = 1024,
    [double]$Temperature = 1.0
)

$ErrorActionPreference = "Stop"
# 本机系统代理会劫持到 WSL 的回环/直连请求，显式禁用
[System.Net.WebRequest]::DefaultWebProxy = $null
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

# ---- 解析服务地址: 显式 -BaseUrl > WSL IP（127.0.0.1 转发被代理劫持时用 IP 直连） ----
if (-not $BaseUrl) {
    $ip = "127.0.0.1"
    try {
        # 经 cmd 隔离 stderr 重定向：PS5.1 下 wsl 的代理警告走 stderr，
        # 直接 2>$null 会触发 NativeCommandError（$ErrorActionPreference=Stop 时）
        $out = (cmd /c "wsl -e hostname -I 2>nul" | Select-Object -First 1)
        if ($out) { $ip = $out.ToString().Trim().Split(" ")[0] }
    } catch {}
    $BaseUrl = "http://${ip}:${Port}"
}

function Get-IsHealthy {
    try {
        $h = Invoke-RestMethod -Uri "$BaseUrl/health" -TimeoutSec 3
        return ($h.status -eq "ok")
    } catch { return $false }
}

if (-not (Get-IsHealthy)) {
    Write-Host "[错误] 模型服务未运行 ($BaseUrl)" -ForegroundColor Red
    Write-Host "       先启动: start-zeus.cmd    (WSL 内等价: bash scripts/start.sh <model-id> -d)"
    exit 1
}

# ---- 当前模型名（美化显示） ----
$modelName = "(unknown)"
try {
    $props = Invoke-RestMethod -Uri "$BaseUrl/props" -TimeoutSec 3
    if ($props.model_path) { $modelName = Split-Path ($props.model_path -replace '/', '\') -Leaf }
} catch {}

# ---- 对话状态 ----
$script:History = @()
$script:Think = (-not $NoThink)

function Send-Chat {
    param([string]$UserText)
    $msgs = @($script:History)
    $msgs += @{ role = "user"; content = $UserText }

    $payload = [ordered]@{
        messages    = $msgs
        max_tokens  = $MaxTokens
        temperature = $Temperature
        top_p       = 0.95
        stream      = $false
    }
    if (-not $script:Think) { $payload.chat_template_kwargs = @{ enable_thinking = $false } }

    $json = ConvertTo-Json -InputObject $payload -Depth 6
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)

    $sw = [Diagnostics.Stopwatch]::StartNew()
    $resp = Invoke-RestMethod -Uri "$BaseUrl/v1/chat/completions" -Method Post `
        -ContentType "application/json; charset=utf-8" -Body $bytes -TimeoutSec 600
    $sw.Stop()

    $msg = $resp.choices[0].message
    if ($msg.reasoning_content) {
        Write-Host ""
        Write-Host "--- 思考过程 ---" -ForegroundColor DarkGray
        Write-Host $msg.reasoning_content -ForegroundColor DarkGray
        Write-Host "--- 回答 ---" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host $msg.content
    if (-not $msg.content -and -not $msg.reasoning_content) {
        Write-Host "(模型未返回内容)" -ForegroundColor Yellow
    }

    # 速度统计（llama-server 非流式响应自带 timings）
    $tps = ""
    try { if ($resp.timings.predicted_per_second) { $tps = "  {0:N0} tok/s" -f [double]$resp.timings.predicted_per_second } } catch {}
    Write-Host ""
    Write-Host ("[{0}s{1}]" -f $sw.Elapsed.TotalSeconds.ToString("0.0"), $tps) -ForegroundColor DarkCyan

    # 追加到多轮历史（assistant 只记正文，不记思考过程）
    $script:History += @{ role = "user"; content = $UserText }
    $script:History += @{ role = "assistant"; content = [string]$msg.content }
}

# ---- 单发模式 ----
if ($Question -ne "") {
    Send-Chat -UserText $Question
    exit 0
}

# ---- 交互模式 ----
Write-Host ""
Write-Host "ST-AAZeus 命令行对话" -ForegroundColor Cyan
Write-Host "  模型: $modelName"
Write-Host "  服务: $BaseUrl"
Write-Host "  命令: /think 开|关(切换思考模式)  /clear(清空上下文)  /system <设定>  /exit(退出)"
Write-Host ""

# 管道输入支持：powershell 宿主会吞掉重定向的 stdin 并作为 $input 管道输入暴露，
# 脚本内 Console.In/Read-Host 均读不到，故重定向时改读 $input 队列
$script:QueuedLines = $null
$script:Qi = 0
if ([Console]::IsInputRedirected) {
    $raw = @($input | ForEach-Object { [string]$_ })
    if ($raw.Count -gt 0) { $script:QueuedLines = ($raw -join "`n") -split "`r?`n" }
}
function Read-NextInput {
    if ($null -eq $script:QueuedLines) { return Read-Host "你" }
    if ($script:Qi -ge $script:QueuedLines.Count) { return $null }   # EOF
    $l = $script:QueuedLines[$script:Qi]; $script:Qi++
    Write-Host "你: $l" -ForegroundColor Cyan
    return $l
}
while ($true) {
    $line = Read-NextInput
    if ($null -eq $line) { break }
    if ($line -eq "") { continue }
    if ($line -match '^/(exit|quit|bye)$') { break }
    if ($line -eq "/clear") {
        $script:History = @()
        Write-Host "已清空对话上下文" -ForegroundColor Green
        continue
    }
    if ($line -match '^/think(\s+(on|off|开|关))?$') {
        $arg = $Matches[2]
        if ($arg -in @("on", "开")) { $script:Think = $true }
        elseif ($arg -in @("off", "关")) { $script:Think = $false }
        else { $script:Think = -not $script:Think }
        Write-Host ("思考模式: {0}" -f $(if ($script:Think) { "开" } else { "关" })) -ForegroundColor Green
        continue
    }
    if ($line -match '^/system\s+(.+)$') {
        $script:History += @{ role = "system"; content = $Matches[1] }
        Write-Host "已追加 system 设定" -ForegroundColor Green
        continue
    }
    if ($line -eq "/help") {
        Write-Host "命令: /think 开|关  /clear  /system <设定>  /exit" -ForegroundColor Green
        continue
    }
    try {
        Send-Chat -UserText $line
    } catch {
        Write-Host "[错误] 本次发送失败: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "       服务可能已停止，重新启动: start-zeus.cmd" -ForegroundColor Red
        if (-not (Get-IsHealthy)) { break }
    }
}
Write-Host "再见。" -ForegroundColor Cyan
