# 项目结构与文件说明

> 更新时间：2026-11-04
> 扫描范围：`D:\env\projects\scrcpy-win64-v5.0.1`
> 本文档描述当前目录布局，脚本行为请以实际代码为准

---

## 一、项目定位

这是 **scrcpy 5.0.1 的 Windows 64 位预编译包**，并在其之上叠加了一套**本地自制的无线连接与投屏脚本**。

- 上游项目：scrcpy（Genymobile），<https://github.com/Genymobile/scrcpy>
- 许可证：Apache License 2.0（见 `docs/LICENSE.txt`）
- 运行时依赖（`bin\scrcpy.exe --version` 实测）：

| 依赖 | 编译版本 | 链接版本 |
|---|---|---|
| SDL | 3.4.18 | 3.4.18 |
| libavcodec | 63.1.102 | 63.1.102 |
| libavformat | 63.1.102 | 63.1.102 |
| libavutil | 61.1.102 | 61.1.102 |
| libusb | — | 1.0.30 |

- ADB 版本：`1.0.41 / 37.0.1-15733141`

**三个基本特征：**

1. **没有源码、没有构建系统**。不存在 `.java` / `.c` / `CMakeLists.txt` / `package.json`，这不是开发工程，而是运行时部署目录。
2. **绿色免安装**。不用注册表、不写 `%APPDATA%`，整个文件夹复制到任何位置都能跑。
3. **目录分区而非功能重构**。`bin/` 之外的一切都是脚本，功能只由脚本决定。

---

## 二、目录结构

```
scrcpy-win64-v5.0.1/
├── .gitattributes              换行与二进制属性
├── .gitignore                  忽略运行时状态与产物
├── README.md                   快速上手
├── 启动.bat                    ① 统一入口（菜单：配对/投屏/等待/设置）
├── 配对.bat                    ② 配对入口（输入地址 + 6 位码）
├── 设置.bat                    ③ 投屏设置（按手机序列号保存）
├── 投屏.bat                    ④ 投屏入口
├── 等待投屏.bat                ⑤ 等待式投屏入口
├── open_a_terminal_here.bat    官方：在此处打开命令行
├── scrcpy-noconsole.vbs        官方：无控制台窗口启动
├── bin/                        程序本体（13 个文件）
│   ├── scrcpy.exe
│   ├── scrcpy-server
│   ├── adb.exe
│   ├── AdbWinApi.dll
│   ├── AdbWinUsbApi.dll
│   ├── SDL3.dll
│   ├── avcodec-63.dll
│   ├── avformat-63.dll
│   ├── avutil-61.dll
│   ├── swresample-7.dll
│   ├── libusb-1.0.dll
│   ├── scrcpy.png
│   ├── scrcpy.ico              由 scrcpy.png 生成，供快捷方式使用
│   └── disconnected.png
├── config/
│   ├── phone.txt               上次连接成功的地址（不入库）
│   └── phone.txt.example       格式示例
├── tools/
│   ├── 打包.bat                生成 dist\scrcpy-portable-*.zip
│   ├── 创建快捷方式.bat        桌面「投屏」图标
│   └── lib/
│       ├── pack.ps1            白名单收集 + 压缩
│       └── shortcut.ps1        PNG→ICO + 建 .lnk
├── logs/                       按天记录运行日志（自动生成，不入库）
└── docs/
    ├── markdown.md             本文档
    └── LICENSE.txt             Apache 2.0
```

统计：根目录 10 个（7 个脚本 + README + 两个 git 配置），`bin/` 14 个（含生成的 ico），`config/` 1 个示例，`docs/` 2 个，`tools/` 4 个，合计 29 个受版本控制的文件，约 25.6 MB（其中 24.9 MB 是二进制）。

---

## 三、按层划分角色

| 层级 | 文件 | 职责 |
|---|---|---|
| **入口层** | `启动.bat`、`配对.bat`、`设置.bat`、`投屏.bat`、`等待投屏.bat`、`open_a_terminal_here.bat`、`scrcpy-noconsole.vbs` | 用户双击的对象，负责参数与流程编排 |
| **工具层** | `tools\打包.bat`、`tools\创建快捷方式.bat`、`tools\lib\*.ps1` | 发布与部署用，不参与日常投屏 |
| **主程序层** | `bin/scrcpy.exe`、`bin/scrcpy-server` | 客户端主机程序 + 设备端代理 |
| **通信层** | `bin/adb.exe`、`AdbWinApi.dll`、`AdbWinUsbApi.dll`、`libusb-1.0.dll` | 建立 PC ↔ 手机 通道 |
| **媒体层** | `avcodec-63.dll`、`avformat-63.dll`、`avutil-61.dll`、`swresample-7.dll` | 解码 H.264/H.265、处理音频 |
| **呈现层** | `SDL3.dll` | 开窗、渲染、键鼠事件映射 |
| **状态层** | `config/phone.txt` | 跨次运行持久化设备地址 |

---

## 四、逐文件说明

### 4.1 入口脚本（根目录）

#### `启动.bat` — 统一入口

- **用途**：一个菜单把配对、投屏、等待投屏、设置串起来，也是桌面快捷方式的目标。
- **动作**：`1` 配对、`2` 投屏、`3` 等待投屏、`4` 设置、`0` 退出。
- **命令行直达**：`启动.bat pair` / `mirror` / `wait` / `settings`，跳过菜单。
- **实现**：本身不做事，`call` 对应的脚本，所以每个功能的代码仍留在各自文件里，改一处不影响其它。
  连续 5 次空输入会退出，避免输入流异常时空转。

#### `配对.bat` — 配对入口

- **用途**：一次性的设备配对引导，只走配对码一条路径。
- **流程**：
  1. 定位 `bin\adb.exe`，缺失则回退 PATH，两者都没有就报错退出；
  2. 提示填入手机「配对」弹窗里的 `IP:端口` 与 6 位配对码，执行 `adb pair`；
  3. 配对成功后等 3 秒，用 `adb mdns services` 嗅探 `_adb-tls-connect._tcp` 的连接端口并 `adb connect`；
  4. 嗅探不到（校园网常见）则提示手动输入「无线调试」主界面上的 `IP:端口`；
  5. 成功后写入 `config\phone.txt`，并询问是否立刻投屏。
- **项目角色**：**`phone.txt` 的写入方之一**（另一处是 `投屏.bat` 的连接回调）。
- **为什么没有扫码**：扫码配对依赖手机通过 mDNS 组播公布配对端口，而校园网 / 公共 Wi-Fi 普遍过滤组播，手机端会一直转圈等不到连接。配对码走点对点 TCP，不受影响，因此只保留这条路径。

#### `设置.bat` — 投屏设置

- **用途**：交互式菜单，逐项开关投屏行为，按 `0` 保存。
- **设备识别**：以 `ro.serialno` 作为配置文件名（这台机器上是 `b385b2bb`），所以换 Wi-Fi、换 IP 后设置仍然属于同一台手机；多台在线时先让你选。
- **可配项**：关屏投屏、虚拟副屏、剪贴板同步、分辨率上限、帧率上限、视频码率、窗口形态、保持亮屏、副屏启动应用。
- **副屏为什么要配应用**：`--new-display` 只是新建一块**空**虚拟屏，上面没有桌面也没有任何界面，不配 `--start-app` 就是纯黑。填包名（`com.android.settings`）或关键字（`?bilibili`，`?` 为模糊匹配）即可。
- **保存位置**：`config\devices\<序列号>.bat`，内容是若干 `set "OPT_*=..."`，可以直接手改（保持 GBK 编码）。
- **两个踩过的坑**（改这段代码前务必知道）：
  1. 取设备信息必须用 `exec-out getprop`，不能用 `shell getprop`——`adb shell` 会分配终端并抢走控制台输入缓冲，导致之后的 `set /p` 读不到按键；
  2. 不能用 `for /f` 去捕获这个输出——带引号的 exe 路径再加 `-s "地址"` 会被 cmd 拆坏引号，取回空值。改成先重定向到临时文件，再 `set /p` 读。

#### `投屏.bat` — 投屏入口

- **用途**：日常一键投屏。
- **设备发现顺序**：
  1. `adb devices` 中所有在线设备（跳过 `emulator-*`，并过滤掉同一台手机的 mDNS 实例名 `*._adb-tls-connect._tcp`，否则同一台会被算成两台）；
  2. 多于一台时弹菜单让你选，`--wait` 模式下直接取第一台不打断流程；
  3. 没有设备则试 `config\phone.txt` 里的地址（**校验必须是 `IPv4:端口`**，防止 BOM / 空行污染）；
  4. 再试 `adb mdns services` 中的 `_adb-tls-connect._tcp`。
- **启动参数**：不再硬编码，来自 `config\devices\<序列号>.bat`；该文件不存在时用默认值（1280 / 60fps / 8M / 置顶 / 保持亮屏）。
- **`--wait`**：进入轮询模式，每约 15 秒重试一次，供 `等待投屏.bat` 使用。
- **项目角色**：**主流程编排器**，整个项目的控制流都在这里。

#### `等待投屏.bat` — 等待式启动

- **内容**：新开窗口执行 `投屏.bat --wait`。
- **用途**：适合"先开脚本，再去手机开无线调试"的习惯。

#### `open_a_terminal_here.bat` — 开终端（官方）

- 内容仅 `@cmd`，双击即在当前目录打开命令行。

#### `scrcpy-noconsole.vbs` — 无窗口启动（官方改造）

- 用 `WScript.Shell.Run(..., 0, false)` 隐藏窗口启动 `bin\scrcpy.exe`，参数原样转义转发。
- **已改造**：原版直接执行 `cmd /c scrcpy.exe`，依赖 exe 在当前目录；分区后改为按脚本自身路径拼出 `bin\scrcpy.exe`，并把工作目录设为包根目录。

### 4.2 程序本体（`bin/`）

| 文件 | 大小 | 职责 |
|---|---|---|
| `scrcpy.exe` | 749 KB | 主程序：推送服务端、协商编码、接收码流、渲染、注入事件 |
| `scrcpy-server` | 717 KB | 手机端 JAR（刻意无扩展名），用 MediaCodec 编码屏幕并回传；版本必须与 exe 严格匹配 |
| `adb.exe` | 7.9 MB | 设备发现、无线配对、mDNS 查询、端口转发、文件推送 |
| `AdbWinApi.dll` | 106 KB | ADB 的 Win32 抽象层，缺失则 adb 无法启动 |
| `AdbWinUsbApi.dll` | 72 KB | ADB 的 USB 传输实现，纯无线场景不参与 |
| `SDL3.dll` | 5.1 MB | 窗口、渲染、输入、音频、剪贴板 |
| `avcodec-63.dll` | 8.3 MB | 视频解码核心 |
| `avformat-63.dll` | 726 KB | 流解析与录制封装 |
| `avutil-61.dll` | 1.0 MB | FFmpeg 公共工具 |
| `swresample-7.dll` | 137 KB | 音频重采样，仅开音频时生效 |
| `libusb-1.0.dll` | 222 KB | USB 直连（`--otg` 等），常规投屏不加载 |
| `scrcpy.png` | 6.4 KB | 窗口 / 任务栏图标 |
| `disconnected.png` | 4.6 KB | 断开连接时的占位画面 |

> FFmpeg 四个库的版本后缀（63 / 61 / 7）对应 ABI，**必须来自同一发行包，不可混用**。

### 4.3 状态（`config/`）

| 文件 | 说明 |
|---|---|
| `phone.txt` | 单行 `IP:端口`，每次连接成功后被重写；已加入 `.gitignore` |
| `phone.txt.example` | 格式示例，供参考 |
| `devices\<序列号>.bat` | **每台手机一份投屏设置**，由 `设置.bat` 生成，`投屏.bat` 读取 |

`phone.txt` 只是"上次连得上的地址"，会随 IP 变化；`devices\` 下的设置以 `ro.serialno` 命名，**换网络、换 IP 都还是同一份**，多台手机各存各的，不会互相覆盖。

读取方（`投屏.bat`）会用正则 `^[0-9.]+\.[0-9]+:[0-9]+$` 校验 `phone.txt`，不合法就当作不存在，继续走 mDNS —— 所以手工编辑坏了也不会导致连接失败，只是失去这项加速。

### 4.4 文档与配置

| 文件 | 说明 |
|---|---|
| `README.md` | 快速上手、常见问题 |
| `docs/markdown.md` | 本文档 |
| `docs/LICENSE.txt` | Apache 2.0 全文 |
| `.gitignore` | 忽略 `phone.txt`、`devices/`、`logs/`、`dist/`、`*.zip`、`.workbuddy/` |
| `.gitattributes` | `.bat`/`.vbs`/`.ps1` 锁 CRLF；exe/dll/png/`scrcpy-server` 标为二进制 |

### 4.5 工具（`tools/`）

| 文件 | 说明 |
|---|---|
| `打包.bat` → `lib/pack.ps1` | 白名单收集文件后压成 `dist\scrcpy-portable-<版本>-<日期>.zip`（约 11 MB） |
| `创建快捷方式.bat` → `lib/shortcut.ps1` | 生成 `bin\scrcpy.ico`，并在桌面建指向 `启动.bat` 的快捷方式 |

两个关键实现细节：

- **为什么用白名单而不是黑名单**：打包是"不复制即排除"，所以 `.git`、`.workbuddy`、`logs`、
  `dist`、`config\phone.txt`、`config\devices\` 天生不会进包，不会因为新增目录而漏掉。
- **为什么 PNG 不能直接当图标**：快捷方式的 `IconLocation` 只认 `.ico`（或 exe/dll 里的资源）。
  `shortcut.ps1` 直接把 256×256 的 PNG 字节包进 ICO 容器（22 字节头 + 原 PNG，Vista 起支持），
  不依赖 `System.Drawing`。

### 4.6 日志（`logs/`）

按天一个文件（`2026-11-05.log`），由 `投屏.bat` 和 `配对.bat` 写入，只保留最近 40 个。

- **格式**：`[时:分:秒] 消息`，日期由文件名体现
- **记什么**：设备发现结果、选中的设备、每次 `adb connect` / `adb pair` 的**原始输出**、
  最终 scrcpy 命令行、退出码
- **实现**：`投屏.bat` / `配对.bat` 内置 `:init_log` 与 `:log` 两个子程序；
  时间用 `%time%`，日期只在启动时算一次——**不要每行都调 PowerShell 取时间**，那会让脚本明显变慢

---

## 五、运行时链路

### 投屏

```
投屏.bat
  ├─ adb devices ──► 在线设备（去重、跳过模拟器）
  │    └─ 多台 → 选择一台
  ├─ 无 → config\phone.txt（校验后 adb connect）
  ├─ 无 → adb mdns services → _adb-tls-connect._tcp
  └─ 取 ro.serialno → 读 config\devices\<序列号>.bat
       └─ scrcpy.exe -s <serial> <按设置拼出的参数>
            ├─ 推送 scrcpy-server 到手机并启动
            ├─ FFmpeg 解码 ◄── 手机 MediaCodec 编码
            └─ SDL3 渲染 + 反向注入键鼠
```

### 配对

```
配对.bat
  ├─ 输入手机「配对」弹窗的 IP:端口 + 6 位码
  ├─ adb pair <IP:配对端口> <码>
  ├─ adb mdns services → _adb-tls-connect._tcp（找不到则手输主界面 IP:端口）
  ├─ adb connect <IP:连接端口>
  └─ 写 config\phone.txt
```

---

## 六、三条硬约束（改动前必读）

1. **`scrcpy.exe` 按自身所在目录找图标和服务端**。二进制内含 `SCRCPY_ICON_DIR`、`SCRCPY_SERVER_PATH`、`Using icon (portable)`、`GetModuleFileNameW`。因此 `scrcpy-server` 必须与 exe 同目录；入口脚本已显式设置这两个环境变量，**不要依赖当前工作目录**。
2. **`scrcpy-server` 不能换成别的版本**，它与 `scrcpy.exe` 的协议必须匹配。
3. **配对端口 ≠ 连接端口**。`adb pair` 用的端口在配对完成后即失效，连接必须换成「无线调试」主界面上的端口（脚本会先用 mDNS 自动找，找不到就让你手输）。

工程约定：

- **`.bat` 必须存成 GBK（代码页 936）并用 CRLF 换行**。cmd 按当前代码页逐字节解码脚本，UTF-8 中文会变成乱码；每个脚本第二行都有 `chcp 936` 兜底，保证从任何终端启动都能正确解析中文文件名与中文提示。代价是只能在装了中文代码页的 Windows 上运行。

---

## 七、版本历史

| 提交 | 内容 |
|---|---|
| `chore: import ... baseline` | 原始 20 个文件原样入库 |
| `refactor: split into bin/, config/, docs/` | 目录分区 + 路径适配 + 图标 / 服务端环境变量固定 |
| `fix: harden device discovery ...` | 设备地址校验、`phone.txt` 格式校验、跳过模拟器、adb 兜底告警、不再误杀共享 adb server |
| `feat: pair by scanning a QR code` | 扫码配对全流程 + 自研 QR 编码器 + 自测脚本（**后已移除**，见下） |
| `docs: add README ...` | 补充快速上手与排错文档 |
| `fix: make the pairing menu explicit ...` | 菜单接受 `2`；mDNS 被拦时 20 秒告警、45 秒提前退出 |
| `refactor: rename the entry scripts to Chinese` | 三个入口改中文名，控制台输出全部中文化 |
| `refactor: drop QR pairing` | **删除扫码链路**：校园网 / 公共 Wi-Fi 过滤 mDNS 组播，扫码必然失败；退回纯配对码方式 |
| `feat: per-device mirror settings` | 新增 `设置.bat`，关屏 / 副屏 / 剪贴板 / 画质 / 窗口 / 保活可配，按序列号存 `config\devices\`；`投屏.bat` 读设置组装参数，并支持多设备选择 |
| `fix: virtual display shows black` | 副屏默认空屏，补 `--start-app` 配置项（设置第 9 项） |
| `feat: unified launcher, logs and tools` | 新增 `启动.bat` 统一入口；`投屏/配对` 写入 `logs/`；`tools\` 提供打包与桌面快捷方式 |

---

## 八、待办（下一步方向）

| 优先级 | 内容 |
|---|---|
| 中 | 插一次 USB 后 `adb tcpip 5555`，把无线端口固定下来，省掉每次查端口 |
| 中 | `config/devices.txt` 支持多设备（别名 + 地址），而不是只能靠序列号
