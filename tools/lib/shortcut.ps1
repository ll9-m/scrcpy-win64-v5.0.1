# 由 tools\创建快捷方式.bat 调用
# 生成 bin\scrcpy.ico（把 PNG 直接包进 ICO 容器，Vista 以上支持），
# 再在桌面建一个指向 启动.bat 的快捷方式。

$ErrorActionPreference = 'Stop'

$toolsDir = $PSScriptRoot                      # tools\lib
$root = Split-Path -Parent (Split-Path -Parent $toolsDir)
$png = Join-Path $root 'bin\scrcpy.png'
$ico = Join-Path $root 'bin\scrcpy.ico'
$entry = Join-Path $root '启动.bat'

if (-not (Test-Path -LiteralPath $entry)) { throw "找不到入口脚本：$entry" }
if (-not (Test-Path -LiteralPath $png))   { throw "找不到图标源文件：$png" }

# ---- 1. PNG -> ICO ----
$data = [System.IO.File]::ReadAllBytes($png)
$w = [System.Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($data, 16))
$h = [System.Net.IPAddress]::NetworkToHostOrder([BitConverter]::ToInt32($data, 20))
if ($w -le 0 -or $h -le 0 -or $w -gt 256 -or $h -gt 256) {
    throw "图标尺寸不受支持：${w}x${h}（ICO 内嵌 PNG 要求不大于 256x256）"
}

$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)
$dimW = if ($w -ge 256) { 0 } else { $w }
$dimH = if ($h -ge 256) { 0 } else { $h }
$bw.Write([UInt16]0)                      # reserved
$bw.Write([UInt16]1)                      # 1 = icon
$bw.Write([UInt16]1)                      # 一个图像
$bw.Write([Byte]$dimW)
$bw.Write([Byte]$dimH)
$bw.Write([Byte]0)                        # 调色板数量
$bw.Write([Byte]0)                        # reserved
$bw.Write([UInt16]1)                      # color planes
$bw.Write([UInt16]32)                     # bits per pixel
$bw.Write([UInt32]$data.Length)           # 图像字节数
$bw.Write([UInt32]22)                     # 图像数据偏移
$bw.Write($data)
$bw.Flush()
[System.IO.File]::WriteAllBytes($ico, $ms.ToArray())
$bw.Dispose()
$ms.Dispose()
Write-Host ("[+] 已生成图标：{0}（{1}x{2}）" -f $ico, $w, $h)

# ---- 2. 桌面快捷方式 ----
$desktop = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desktop '投屏.lnk'

$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($lnkPath)
$lnk.TargetPath       = $entry
$lnk.WorkingDirectory = $root
$lnk.IconLocation     = "$ico,0"
$lnk.Description      = 'scrcpy 无线投屏（配对 / 投屏 / 设置）'
$lnk.WindowStyle      = 1
$lnk.Save()

Write-Host ("[+] 已创建快捷方式：{0}" -f $lnkPath)
Write-Host "    目标：$entry"
