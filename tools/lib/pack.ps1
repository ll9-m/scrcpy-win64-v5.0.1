# 由 tools\打包.bat 调用
# 用白名单方式收集文件（不复制即排除），压成 dist\scrcpy-portable-<版本>-<日期>.zip

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$toolsDir = $PSScriptRoot
$root = Split-Path -Parent (Split-Path -Parent $toolsDir)
$dist = Join-Path $root 'dist'

$ver = '5.0.1'
if ((Split-Path -Leaf $root) -match 'v(\d+(?:\.\d+)+)') { $ver = $Matches[1] }
$stamp = Get-Date -Format 'yyyyMMdd'
$zipName = "scrcpy-portable-$ver-$stamp.zip"

if (-not (Test-Path -LiteralPath $dist)) {
    New-Item -ItemType Directory -Path $dist | Out-Null
}
$zip = Join-Path $dist $zipName
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }

$tmp = Join-Path $env:TEMP ("scrcpy-pack-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null

try {
    # 根目录只带脚本和文档，不带 .git / .workbuddy / logs / dist
    Get-ChildItem -LiteralPath $root -File |
        Where-Object { $_.Extension -in '.bat', '.vbs', '.md' } |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $tmp }

    foreach ($d in @('bin', 'docs', 'tools')) {
        Copy-Item -LiteralPath (Join-Path $root $d) -Destination (Join-Path $tmp $d) -Recurse
    }

    # config 只带格式示例，个人地址和设备设置都不带
    $cfg = Join-Path $tmp 'config'
    New-Item -ItemType Directory -Path $cfg | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'config\phone.txt.example') -Destination $cfg

    Write-Host "[*] 正在压缩..."
    Compress-Archive -Path (Join-Path $tmp '*') -DestinationPath $zip -CompressionLevel Optimal
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$sizeMb = [math]::Round((Get-Item -LiteralPath $zip).Length / 1MB, 1)
Write-Host ""
Write-Host "[+] 打包完成：$zip"
Write-Host "    大小：$sizeMb MB"
Write-Host ""
Write-Host "    已排除：.git  .workbuddy  logs  dist  config\phone.txt  config\devices"
