#requires -version 5.1
<#
    pair-qr.ps1 - pair an Android 11+ phone by scanning a QR code.

    Protocol (AOSP docs/dev/adb_wifi.md):
      the QR code carries   WIFI:T:ADB;S:<instance>;P:<code>;;
      the phone reads it, starts a pairing server and advertises
      _adb-tls-pairing._tcp with that instance name;
      we discover it over mDNS, run `adb pair`, then `adb connect`.

    Exit codes:
      0  paired (or already connected)
      1  environment problem (adb or qr lib missing)
      2  timed out
      3  mDNS not usable on this machine
#>
[CmdletBinding()]
param(
    [int]$PairTimeoutSec = 120,
    [int]$ConnectTimeoutSec = 25,
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'

$ScriptDir = $PSScriptRoot
$Root      = Split-Path -Parent $ScriptDir
$Adb       = Join-Path $Root 'bin\adb.exe'
$ConfigDir = Join-Path $Root 'config'
$PhoneFile = Join-Path $ConfigDir 'phone.txt'
$QrLib     = Join-Path $ScriptDir 'lib\qr.js'
$MirrorBat = Join-Path $Root 'mirror.bat'

function Step { param([string]$m) Write-Host "[*] $m" -ForegroundColor Cyan }
function Ok   { param([string]$m) Write-Host "[+] $m" -ForegroundColor Green }
function Warn { param([string]$m) Write-Host "[!] $m" -ForegroundColor Yellow }
function Fail { param([string]$m) Write-Host "[x] $m" -ForegroundColor Red }
function Say  {
    param([string]$m)
    # Write-Host "" does not always emit a line break depending on the host,
    # so print a space for intentionally blank lines.
    if ([string]::IsNullOrEmpty($m)) { Write-Host ' ' } else { Write-Host $m }
}

function Invoke-Adb {
    param([string[]]$Arguments)
    # adb writes ordinary progress text to stderr; with $ErrorActionPreference
    # set to Stop that would abort the script, so relax it just for the call.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $Adb @Arguments 2>&1
        return (($out | ForEach-Object { "$_" }) -join "`n")
    } finally {
        $ErrorActionPreference = $previous
    }
}

# Parses `adb mdns services`. The column layout differs between adb versions
# and instance names may contain spaces, so take the last token of the line
# and validate it as IPv4:port instead of trusting token positions.
function Get-AdbServices {
    $raw = Invoke-Adb @('mdns', 'services')
    $result = @()
    foreach ($line in ($raw -split "`r?`n")) {
        if ($line -notmatch '_adb-tls-(pairing|connect)\._tcp') { continue }
        $tokens = @($line.Trim() -split '\s+')
        if ($tokens.Count -lt 2) { continue }
        $addr = $tokens[$tokens.Count - 1]
        if ($addr -notmatch '^\d{1,3}(\.\d{1,3}){3}:\d+$') { continue }
        $kind = if ($line -match '_adb-tls-pairing') { 'pairing' } else { 'connect' }
        $result += [pscustomobject]@{ Name = $tokens[0]; Address = $addr; Kind = $kind }
    }
    return $result
}

function Get-NetworkDevices {
    $out = @()
    foreach ($line in ((Invoke-Adb @('devices')) -split "`r?`n")) {
        if ($line -match '^(\S+)\s+device\b') {
            $serial = $Matches[1]
            if ($serial -match '^\d{1,3}(\.\d{1,3}){3}:\d+$') { $out += $serial }
        }
    }
    return $out
}

# ---------------------------------------------------------------- preflight

if (-not (Test-Path -LiteralPath $Adb)) {
    Fail "找不到 adb：$Adb"
    exit 1
}
if (-not (Test-Path -LiteralPath $QrLib)) {
    Fail "二维码生成库缺失：$QrLib"
    exit 1
}

Step '启动 adb 服务...'
$null = Invoke-Adb @('start-server')
Start-Sleep -Milliseconds 900

$mdns = Invoke-Adb @('mdns', 'check')
if ($mdns -notmatch 'mdns daemon version') {
    Fail '本机的 adb mDNS 不可用，扫码配对需要它。'
    Say  '  常见原因：VPN 或虚拟网卡占用、防火墙拦截 UDP 5353、adb 版本过旧。'
    Say  '  可以先关闭 VPN 再试，或直接改用手输 6 位配对码。'
    exit 3
}

# The single most common failure is "phone and PC are not actually on the same
# network", so print the local addresses before anything else.
$locals = @()
try {
    $locals = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*' } |
        ForEach-Object { "$($_.IPAddress)/$($_.PrefixLength)" })
} catch { }
if ($locals.Count -gt 0) {
    Say "本机地址：$($locals -join '  ')"
    Say '  手机要和上面某个地址处于同一网段，扫码才可能成功。'
    Say ''
}

$existing = @(Get-NetworkDevices)
if ($existing.Count -gt 0) {
    Ok "已经连接：$($existing[0])"
    Say '无需重新配对，直接运行 mirror.bat 即可。'
    Say '（若要配对新手机，先在手机或电脑上断开当前连接。）'
    exit 0
}

# ---------------------------------------------------------------- generate

$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$buf = New-Object byte[] 4
$rng.GetBytes($buf)
$svc  = 'scrcpy-' + (($buf | ForEach-Object { $_.ToString('x2') }) -join '')
$code = (Get-Random -Minimum 100000 -Maximum 999999).ToString()
# Built by concatenation: "S:$svc" inside a double quoted string is too easy to
# confuse with a PowerShell scope qualifier, and a single wrong separator makes
# the QR code silently useless.
$payload = 'WIFI:T:ADB;S:' + $svc + ';P:' + $code + ';;'
if ($payload -notmatch '^WIFI:T:ADB;S:[^;]+;P:\d{6};;$') {
    Fail "内部错误：配对串格式不正确 -> $payload"
    exit 1
}

$baseline = @{}
foreach ($s in @(Get-AdbServices)) {
    if ($s.Kind -eq 'pairing') { $baseline[$s.Address] = $true }
}

$lib = Get-Content -LiteralPath $QrLib -Raw -Encoding UTF8
$template = @'
<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="color-scheme" content="light">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>scrcpy 扫码配对</title>
<style>
  html, body { margin: 0; height: 100%; background: #ffffff; color: #111827; color-scheme: light; }
  body { display: flex; align-items: center; justify-content: center;
         font-family: "Segoe UI", "Microsoft YaHei", system-ui, sans-serif; }
  .card { text-align: center; padding: 28px 36px; }
  h1 { font-size: 20px; font-weight: 600; margin: 0 0 8px; }
  .sub { font-size: 13px; line-height: 1.8; color: #4b5563; margin: 0 0 22px; }
  #qr { display: inline-block; padding: 16px; border: 1px solid #e5e7eb; border-radius: 12px; background: #fff; }
  #qr svg { display: block; }
  .code { margin-top: 18px; font-size: 14px; color: #374151; }
  .code b { font-size: 26px; letter-spacing: 6px; color: #111827; margin-left: 8px; }
  .foot { margin-top: 16px; font-size: 12px; color: #9ca3af; }
</style>
</head>
<body>
<div class="card">
  <h1>用手机扫描二维码完成配对</h1>
  <p class="sub">设置 → 开发者选项 → 无线调试 → <b>使用二维码配对设备</b><br>
     手机与本机需在同一 Wi-Fi，且该网络未开启客户端隔离</p>
  <div id="qr"></div>
  <div class="code">配对码<b>__CODE__</b></div>
  <p class="foot">服务名 __SVC__ · 关闭本页面后二维码即失效</p>
</div>
<script>__QR_LIB__</script>
<script>
(function () {
  var qr = QRCodeGen.make("__PAYLOAD__");
  var quiet = 4;
  var total = qr.size + quiet * 2;
  var px = total * 10;
  var rects = [];
  for (var r = 0; r < qr.size; r++) {
    for (var c = 0; c < qr.size; c++) {
      if (qr.modules[r][c]) {
        rects.push('<rect x="' + (c + quiet) + '" y="' + (r + quiet) + '" width="1" height="1"/>');
      }
    }
  }
  document.getElementById('qr').innerHTML =
    '<svg xmlns="http://www.w3.org/2000/svg" width="' + px + '" height="' + px + '"' +
    ' viewBox="0 0 ' + total + ' ' + total + '" shape-rendering="crispEdges">' +
    '<rect width="' + total + '" height="' + total + '" fill="#ffffff"/>' +
    '<g fill="#000000">' + rects.join('') + '</g></svg>';
})();
</script>
</body>
</html>
'@

$html = $template.Replace('__QR_LIB__', $lib).Replace('__PAYLOAD__', $payload).Replace('__CODE__', $code).Replace('__SVC__', $svc)

$htmlPath = Join-Path $env:TEMP ("scrcpy-pair-{0}.html" -f $PID)
[System.IO.File]::WriteAllText($htmlPath, $html, (New-Object System.Text.UTF8Encoding($false)))

if ($NoBrowser) {
    Say "二维码页面：$htmlPath"
} else {
    Start-Process -FilePath $htmlPath
}
Say ''
Step "已打开二维码页面，请用手机扫描（最多等待 $PairTimeoutSec 秒）..."
Say '    手机上如果找不到"使用二维码配对设备"，按 Ctrl+C 退出后改用手输配对码。'
Say ''

# ---------------------------------------------------------------- pair

$tried = @{}
$paired = $null
$started = Get-Date
$deadline = $started.AddSeconds($PairTimeoutSec)
$servicesSeen = 0
$isolatedHinted = $false
$nextReport = $started.AddSeconds(15)

while (-not $paired -and (Get-Date) -lt $deadline) {
    $all = @(Get-AdbServices)
    $servicesSeen += $all.Count
    $pending = @($all | Where-Object { $_.Kind -eq 'pairing' -and -not $tried.ContainsKey($_.Address) })

    # Prefer the instance we asked the phone to advertise, then anything new.
    $ordered = @()
    $ordered += @($pending | Where-Object { $_.Name -like "*$svc*" })
    $ordered += @($pending | Where-Object { $_.Name -notlike "*$svc*" -and -not $baseline.ContainsKey($_.Address) })

    foreach ($candidate in $ordered) {
        if ($tried.ContainsKey($candidate.Address)) { continue }
        $tried[$candidate.Address] = $true

        Step "发现配对服务 $($candidate.Name)，正在配对 $($candidate.Address) ..."
        $out = Invoke-Adb @('pair', $candidate.Address, $code)

        if ($out -match 'Successfully paired|already paired') {
            $paired = $candidate
            break
        }
        $first = ($out -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
        Warn "该地址配对失败：$first"
    }

    if ($paired) { break }

    $elapsed = [int]((Get-Date) - $started).TotalSeconds

   # Nothing at all showed up: far more likely a network problem than a QR problem.
    if (-not $isolatedHinted -and $elapsed -ge 20 -and $servicesSeen -eq 0) {
        Say ''
        Warn '20 秒内没有发现任何 mDNS 广播。'
        Say  '  手机的配对广播到不了本机，常见原因：'
        Say  '    - 校园网 / 企业网 / 公共 Wi-Fi 开启了客户端隔离（最常见）'
        Say  '    - 手机和电脑不在同一网段，对比上面打印的本机地址'
        Say  '    - Windows 把该网络识别为"公用"，防火墙拦掉了入站'
        Say  '  可以先改用手机热点，或直接插 USB 线投屏（无需配对）。'
        Say  '  脚本仍会继续等待；按 Ctrl+C 可以退出后改用手输配对码。'
        Say ''
        $isolatedHinted = $true
    }

    if ((Get-Date) -ge $nextReport) {
        Say "    ... 已等待 $elapsed 秒，累计发现 $servicesSeen 个 mDNS 服务"
        $nextReport = (Get-Date).AddSeconds(15)
    }

    # If multicast is being dropped, no amount of extra waiting will help.
    if ($servicesSeen -eq 0 -and $elapsed -ge 45) {
        Say ''
        Warn '45 秒内始终没有任何广播，继续等待也不会有结果，先退出。'
        break
    }

    Start-Sleep -Milliseconds 1200
}

if (-not $paired) {
    Say ''
    Fail '配对没有完成。'
    if ($servicesSeen -eq 0) {
        Say '  全程没有发现任何 mDNS 广播 —— 这是网络问题，不是二维码问题。'
        Say '  1. 校园网 / 公共 Wi-Fi 常开客户端隔离，设备之间互相看不见'
        Say '  2. 让电脑连手机热点（或手机连电脑热点），通常立刻就能用'
        Say '  3. 也可以直接插 USB 线，运行 mirror.bat 即可投屏，完全不需要配对'
    } else {
        Say '  发现过广播但没配对成功，多半是配对码或时序问题。'
        Say '  1. 手机上的二维码页面必须一直开着，关掉即失效'
        Say '  2. 重新运行本脚本，生成新的二维码再扫一次'
        Say '  3. 或改用手输 6 位配对码'
    }
    exit 2
}

Say ''
Ok '配对成功。'

# ---------------------------------------------------------------- connect

$pairIp = $paired.Address.Split(':')[0]
$target = $null
$deadline = (Get-Date).AddSeconds($ConnectTimeoutSec)

while (-not $target -and (Get-Date) -lt $deadline) {
    # The pairing port and the connection port are different; never reuse it.
    $conn = @(@(Get-AdbServices) | Where-Object { $_.Kind -eq 'connect' })
    $sameIp = @($conn | Where-Object { $_.Address.Split(':')[0] -eq $pairIp })

    $candidate = $null
    if ($sameIp.Count -gt 0) { $candidate = $sameIp[0].Address }
    elseif ($conn.Count -gt 0) { $candidate = $conn[0].Address }

    if ($candidate) {
        Step "连接 $candidate ..."
        $null = Invoke-Adb @('connect', $candidate)
        $escaped = [regex]::Escape($candidate)
        if ((Invoke-Adb @('devices')) -match "(?m)^\s*$escaped\s+device\b") {
            $target = $candidate
        }
    }
    if (-not $target) { Start-Sleep -Milliseconds 1200 }
}

# adb 37 may auto-connect on its own once pairing succeeded.
if (-not $target) {
    $auto = @(Get-NetworkDevices)
    if ($auto.Count -gt 0) { $target = $auto[0] }
}

if (-not $target) {
    Say ''
    Fail '配对成功，但没能建立数据连接。'
    Say '  打开手机的"无线调试"主界面，把上面显示的 IP:port 用 pair.bat 的手输流程连一次。'
    exit 2
}

Say ''
Ok "已连接：$target"

if (-not (Test-Path -LiteralPath $ConfigDir)) {
    $null = New-Item -ItemType Directory -Path $ConfigDir -Force
}
[System.IO.File]::WriteAllText($PhoneFile, "$target`r`n", (New-Object System.Text.ASCIIEncoding))
Say "已保存到 config\phone.txt"

Say ''
$answer = Read-Host '现在开始投屏吗？[Y/N]'
if ($answer -match '^\s*[Yy]') {
    Start-Process -FilePath $MirrorBat
}

exit 0
