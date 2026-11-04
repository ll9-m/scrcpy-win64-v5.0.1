# 项目文件与目录说明（scrcpy-win64-v5.0.1）

> 生成时间：2026-11-04
> 扫描范围：`D:\env\projects\scrcpy-win64-v5.0.1` 全量内容（含隐藏文件）
> 说明性质：仅做静态梳理，未修改任何代码或配置

---

## 一、项目定位

这是一个 **scrcpy 5.0.1 的 Windows 64 位预编译发行包**，并在其基础上叠加了一套**本地自制的无线投屏启动脚本**。

- 上游项目：scrcpy（Genymobile），GitHub <https://github.com/Genymobile/scrcpy>
- 许可证：Apache License 2.0
- 依赖版本（由 `scrcpy.exe --version` 实测）：

| 依赖 | 编译版本 | 链接版本 |
|---|---|---|
| SDL | 3.4.18 | 3.4.18 |
| libavcodec | 63.1.102 | 63.1.102 |
| libavformat | 63.1.102 | 63.1.102 |
| libavutil | 61.1.102 | 61.1.102 |
| libusb | — | 1.0.30 |

- ADB 版本：`Android Debug Bridge 1.0.41 / 37.0.1-15733141`

**关键特征：**

1. **没有源码、没有构建系统**。不存在 `.java` / `.c` / `CMakeLists.txt` / `meson.build` / `package.json` 等，本项目不是"开发工程"，而是"运行时部署目录"。
2. **没有版本控制**。目录下不存在 `.git`。
3. **完全扁平**。所有文件直接位于根目录，**没有任何子目录**。
4. **改动痕迹集中**。上游文件时间戳统一为 `2025-10-08 14:27`；而 `mirror.bat`、`pair.bat`、`mirror-wait.bat`、`phone.txt` 的时间戳为 `2026-11-04`，说明这四个文件是本地新增 / 二次开发的产物，其余为原封不动的官方发行文件。

---

## 二、目录结构总览

```
scrcpy-win64-v5.0.1/                 ← 项目根目录（唯一目录，同时是运行时工作目录）
├── scrcpy.exe                       ← 主程序
├── scrcpy-server                    ← 推送到手机的设备端服务（JAR，无扩展名）
├── adb.exe                          ← Android 调试桥
├── AdbWinApi.dll                    ← ADB Windows API 转发库
├── AdbWinUsbApi.dll                 ← ADB USB 传输库
├── SDL3.dll                         ← 窗口 / 输入 / 音频 抽象层
├── avcodec-63.dll                   ← FFmpeg 编解码
├── avformat-63.dll                  ← FFmpeg 容器 / 流解析
├── avutil-61.dll                    ← FFmpeg 公共工具
├── swresample-7.dll                 ← FFmpeg 音频重采样
├── libusb-1.0.dll                   ← USB 设备访问
├── mirror.bat                       ← 【本地】一键无线投屏（核心脚本）
├── pair.bat                         ← 【本地】无线调试配对 + 首次连接
├── mirror-wait.bat                  ← 【本地】带重试等待的投屏启动器
├── phone.txt                        ← 【本地】已保存的手机无线地址
├── open_a_terminal_here.bat         ← 官方：在此处打开终端
├── scrcpy-noconsole.vbs             ← 官方：无控制台窗口启动
├── LICENSE.txt                      ← Apache 2.0 许可证
├── scrcpy.png                       ← 程序图标
└── disconnected.png                 ← 断开连接占位图
```

**文件统计：** 共 20 个文件，0 个子目录，总体积约 **25.6 MB**（其中 DLL/EXE 占 24.9 MB，脚本与配置合计不足 6 KB）。

---

## 三、按功能分层的角色划分

| 层级 | 文件 | 说明 |
|---|---|---|
| **入口层** | `mirror.bat`、`pair.bat`、`mirror-wait.bat`、`open_a_terminal_here.bat`、`scrcpy-noconsole.vbs` | 用户实际双击 / 调用的对象 |
| **主程序层** | `scrcpy.exe`、`scrcpy-server` | 客户端主机程序 + 设备端代理 |
| **设备通信层** | `adb.exe`、`AdbWinApi.dll`、`AdbWinUsbApi.dll`、`libusb-1.0.dll` | 建立 PC↔手机 通道 |
| **媒体处理层** | `avcodec-63.dll`、`avformat-63.dll`、`avutil-61.dll`、`swresample-7.dll` | 解码 H.264/H.265 视频流、处理音频 |
| **呈现层** | `SDL3.dll` | 开窗、渲染、键鼠 / 触控事件映射 |
| **状态层** | `phone.txt` | 跨次运行持久化的设备地址 |
| **元数据层** | `LICENSE.txt`、`scrcpy.png`、`disconnected.png` | 许可与图形资源 |

---

## 四、逐文件详细说明

### 4.1 核心可执行程序

#### `scrcpy.exe` — 主程序（766,717 B / 749 KB）

- **用途**：整个项目的运行主体，Windows 客户端。
- **主要职责**：
  1. 通过 ADB 与手机建立连接，把 `scrcpy-server` 推送到设备并拉起；
  2. 协商视频 / 音频编码参数（分辨率、帧率、码率、编码器）；
  3. 接收设备端回传的 H.264/H.265 裸流，交给 FFmpeg 解码；
  4. 用 SDL3 渲染画面，并把本机键盘、鼠标、剪贴板事件反向注入手机。
- **项目角色**：**唯一真正的业务程序**，其余脚本和 DLL 都是为它服务或由它加载。

#### `scrcpy-server` — 设备端服务（733,930 B / 717 KB）

- **用途**：运行在 Android 手机上的 Java 服务端进程（实测文件头为 `PK\x03\x04`，是 JAR 包，只是刻意去掉了 `.jar` 扩展名）。
- **主要职责**：
  1. 调用 Android `MediaCodec` 硬件编码屏幕内容，输出视频流；
  2. 采集音频（Android 11+ 支持内录）；
  3. 通过本地 socket 接收客户端传来的控制指令并注入触摸 / 按键事件。
- **项目角色**：**服务端半边天**。每次启动时由 `scrcpy.exe` 临时推送到 `/data/local/tmp/` 下执行，运行结束即释放，不常驻手机。
- **注意**：此文件版本必须与 `scrcpy.exe` 严格匹配，不可单独替换。

### 4.2 设备通信层（ADB 与 USB）

| 文件 | 大小 | 用途与职责 | 项目角色 |
|---|---|---|---|
| `adb.exe` | 8,273,560 B (7.9 MB) | Android Debug Bridge 命令行工具。负责设备发现、TCP/IP 连接、无线配对（`adb pair`）、mDNS 服务发现（`adb mdns services`）、端口转发、shell 命令下发、文件推送。版本 1.0.41 / 37.0.1 | **全部脚本的通信底座**。`pair.bat` 与 `mirror.bat` 的每一条命令都依赖它 |
| `AdbWinApi.dll` | 108,184 B | ADB 的 Windows 平台抽象层，封装 Win32 句柄、事件、进程操作 | `adb.exe` 的必需依赖，缺失则 adb 无法启动 |
| `AdbWinUsbApi.dll` | 73,368 B | ADB 的 Windows USB 传输实现，负责 USB 端点读写与驱动交互 | 仅在有线 USB 连接时需要；纯无线场景不参与 |
| `libusb-1.0.dll` | 227,005 B | 跨平台 USB 库，供 `scrcpy.exe` 直接访问 USB 设备（绕过 adb 的 USB 直连模式） | 支撑 `--otg` 等 USB 直连能力；常规投屏不加载 |

**分层关系**：`pair.bat` / `mirror.bat` → `adb.exe` → `AdbWinApi.dll` + `AdbWinUsbApi.dll` → 手机。

### 4.3 媒体与呈现层（DLL）

| 文件 | 大小 | 用途与职责 | 项目角色 |
|---|---|---|---|
| `SDL3.dll` | 5,384,859 B (5.1 MB) | Simple DirectMedia Layer 3。提供窗口创建、GPU/软件渲染、纹理上传、键鼠与手柄事件、音频输出、剪贴板 | **画面与交互的承载者**；也是 `--always-on-top`、全屏、缩放等窗口行为的实现基础 |
| `avcodec-63.dll` | 8,685,568 B (8.3 MB) | FFmpeg 编解码库。把手机传来的 H.264/H.265 码流解码为原始 YUV/RGB 帧 | 体积最大的文件，**视频解码核心** |
| `avformat-63.dll` | 743,424 B | FFmpeg 容器与流格式解析，处理流封装、时间戳、`--record` 录制时的封装输出 | 流解析与录制支持 |
| `avutil-61.dll` | 1,047,552 B | FFmpeg 公共工具库：内存、数学、像素格式、帧缓冲管理 | `avcodec` / `avformat` / `swresample` 的公共依赖 |
| `swresample-7.dll` | 139,776 B | FFmpeg 音频重采样与声道转换，把设备音频转成本机声卡可播放的格式 | 仅在启用音频转发（`--audio`）时实际生效 |

> 版本号后缀（63 / 61 / 7）对应 FFmpeg 的大版本 ABI，**不可跨版本混用**；四个库必须来自同一发行包。

### 4.4 本地自制脚本（本次项目的实质性增量）

这四个文件是相对官方发行包**新增或改造**的部分，也是后续最可能需要改动的地方。

#### `mirror.bat` — 一键无线投屏（2,389 B）

- **用途**：核心启动脚本，自动找到手机并开窗投屏，用户无需记参数。
- **主要职责**（按执行顺序）：
  1. **环境自愈**：`cd /d "%~dp0"` 锁定工作目录；优先使用同目录的 `adb.exe` / `scrcpy.exe`，不存在则回退到系统 `PATH`。
  2. **设备发现（`:discover` 段）**：遍历 `adb devices` 输出，分三类处理——
     - 带 `:` 的序列号 → 视为网络设备，立即采用（无线优先）；
     - 无 `:` 的 `device` → 记为 USB 备选；
     - `unauthorized` / `offline` → 打标记，供后续给出针对性提示。
  3. **回退链**：`USB 设备` → `phone.txt` 中保存的地址`（adb connect）` → `adb mdns services` 中查找 `_adb-tls-connect._tcp` 记录。
  4. **等待模式**：传入 `--wait` 时进入轮询（`ping -n 16` 约 15 秒一轮），并在首次遇到未授权 / 离线时打印一次提示，而不是直接退出。
  5. **失败处理**：非等待模式下打印三条排查建议，等 5 秒后 `adb kill-server` 清理残留进程，返回退出码 1。
  6. **启动（`:run` 段）**：以固定参数拉起 scrcpy——
     ```bat
     scrcpy -s <SERIAL> --max-size=1280 --max-fps=60 --keep-active --always-on-top
     ```
     含义：限制最长边 1280 px（省带宽、保流畅）、上限 60 fps、保持手机不休眠、窗口置顶。
  7. **收尾**：scrcpy 退出后 `adb kill-server`，避免 adb 后台进程残留。
- **项目角色**：**用户入口 + 连接编排器**。整个项目的"控制流"都在这里。

#### `pair.bat` — 无线调试配对（2,454 B）

- **用途**：解决 Android 11+ "无线调试"首次连接必须配对的问题。
- **主要职责**：
  1. 提示用户输入**配对对话框**里的 `IP:port` 与 6 位配对码；
  2. 执行 `adb pair <IP:port> <code>`，失败时给出针对性诊断（尤其是"误用主界面端口导致 protocol fault"这一常见坑）；
  3. 配对成功后等待 3 秒，用 `adb mdns services` 自动嗅探 `_adb-tls-connect._tcp` 的真实连接端口并自动 `adb connect`；
  4. 自动连接失败则回退为手动输入主界面 `IP:port`；
  5. 成功后把地址写入 `phone.txt`，并询问是否立即调用 `mirror.bat` 开始投屏。
- **项目角色**：**首次使用的一次性引导器**，同时是 `phone.txt` 的**唯一生产者**（写入方）。

#### `mirror-wait.bat` — 带等待的启动器（80 B）

- **内容**：`start "scrcpy" cmd /c "mirror.bat --wait"`
- **用途**：不阻塞当前窗口，新开一个命令行窗口运行 `mirror.bat --wait`，即"一直等到手机出现为止"。
- **项目角色**：**便利封装**。适合"先开脚本、后开手机无线调试"的使用习惯。

#### `phone.txt` — 设备地址缓存（20 B）

- **内容**：`10.66.209.39:33751`（当前记录的无线调试连接地址）
- **用途**：持久化上一次成功连接的 `IP:port`，让 `mirror.bat` 在 mDNS 失效（如路由器禁用组播）时仍能直连。
- **项目角色**：**状态文件 / 缓存**。由 `pair.bat` 和 `mirror.bat` 的 `:connect` 段写入，由 `mirror.bat` 读取。
- **注意**：无线调试端口每次重开通常会变化，此文件可能过期——脚本已用 mDNS 作为后备来兜底。

### 4.5 官方附带的辅助文件

| 文件 | 大小 | 用途与职责 | 项目角色 |
|---|---|---|---|
| `open_a_terminal_here.bat` | 5 B | 内容仅 `@cmd`，双击即在当前目录打开命令提示符 | 官方便利脚本，方便手动敲 scrcpy 参数 |
| `scrcpy-noconsole.vbs` | 212 B | VBScript，用 `WScript.Shell.Run(..., 0, false)` 以隐藏窗口方式启动 `scrcpy.exe`，并把收到的参数原样转义转发 | 消除黑色控制台窗口，纯 GUI 体验 |
| `LICENSE.txt` | 11,387 B | Apache License 2.0 全文 | 法律合规文件，分发时必须保留 |
| `scrcpy.png` | 6,530 B | scrcpy 官方图标（用于快捷方式、任务栏识别） | 品牌 / 图形资源 |
| `disconnected.png` | 4,703 B | 设备断开时显示的占位图 | 运行时 UI 资源，由 `scrcpy.exe` 内嵌引用 |

---

## 五、运行时调用链路

```
                    ┌──────────────────────────────────────────┐
   用户双击 ───────► │ pair.bat        （首次：配对 + 连接）      │
                    │ mirror.bat      （日常：直接投屏）        │
                    │ mirror-wait.bat （日常：等待手机出现）    │
                    └───────────────┬──────────────────────────┘
                                    │
                     ┌──────────────┴───────────────┐
                     ▼                              ▼
             读 / 写 phone.txt              调用 adb.exe
             （地址缓存）                          │
                                    ┌────────────┴────────────┐
                                    ▼                         ▼
                            adb devices / connect      adb pair / mdns
                                    │
                                    ▼
                            scrcpy.exe ──推送──► scrcpy-server（手机端执行）
                                    │
                    ┌───────────────┼────────────────┐
                    ▼               ▼                ▼
              SDL3.dll      avcodec/avformat     libusb-1.0.dll
             （窗口渲染）    （视频解码）          （USB 直连，可选）
```

**一次完整投屏的时序：**

1. 脚本解析 `adb devices` / `phone.txt` / mDNS，确定目标序列号；
2. 若无连接，`adb connect <IP:port>` 建立 TCP 通道；
3. `scrcpy.exe` 把 `scrcpy-server` 推送到手机并启动；
4. 服务端用 MediaCodec 编码屏幕 → 客户端 FFmpeg 解码 → SDL3 渲染；
5. 用户键鼠事件经反向通道注入手机；
6. 退出时 `adb kill-server` 清理。

---

## 六、目录层面的说明

| 目录 | 性质 | 职责与角色 |
|---|---|---|
| `scrcpy-win64-v5.0.1\`（根目录） | 唯一的物理目录 | **同时承担三重身份**：① 程序安装目录（EXE/DLL 同级，Windows 按 exe 所在目录搜索依赖 DLL）；② 运行时工作目录（脚本用 `cd /d "%~dp0"` 强制锁定，保证相对路径可靠）；③ 配置存储位置（`phone.txt` 与之同级） |

**没有子目录**这一事实本身值得注意，它带来两个直接后果：

- **优点**：绿色免安装，整个目录可整体复制 / 迁移 / 打包，不写注册表、不依赖 `%APPDATA%`。
- **约束**：所有新增资源（日志、截图、录屏、配置）若直接落在根目录会与程序文件混杂；后续若要扩展，建议新建 `logs/`、`recordings/`、`config/` 等子目录并同步修改脚本。

---

## 七、文件清单速查表

| # | 文件名 | 类型 | 大小 | 修改时间 | 来源 | 一句话角色 |
|---|---|---|---|---|---|---|
| 1 | `scrcpy.exe` | 可执行 | 749 KB | 2025-10-08 | 官方 | 主程序，投屏与控制的实现者 |
| 2 | `scrcpy-server` | JAR（无扩展名） | 717 KB | 2025-10-08 | 官方 | 手机端编码与注入服务 |
| 3 | `adb.exe` | 可执行 | 7.9 MB | 2025-10-08 | 官方 | 设备通信底座 |
| 4 | `AdbWinApi.dll` | 动态库 | 106 KB | 2025-10-08 | 官方 | ADB 的 Win32 抽象层 |
| 5 | `AdbWinUsbApi.dll` | 动态库 | 72 KB | 2025-10-08 | 官方 | ADB 的 USB 传输实现 |
| 6 | `SDL3.dll` | 动态库 | 5.1 MB | 2025-10-08 | 官方 | 窗口、渲染、输入、音频 |
| 7 | `avcodec-63.dll` | 动态库 | 8.3 MB | 2025-10-08 | 官方 | 视频解码核心 |
| 8 | `avformat-63.dll` | 动态库 | 726 KB | 2025-10-08 | 官方 | 流解析与录制封装 |
| 9 | `avutil-61.dll` | 动态库 | 1.0 MB | 2025-10-08 | 官方 | FFmpeg 公共工具 |
| 10 | `swresample-7.dll` | 动态库 | 137 KB | 2025-10-08 | 官方 | 音频重采样 |
| 11 | `libusb-1.0.dll` | 动态库 | 222 KB | 2025-10-08 | 官方 | USB 设备直连 |
| 12 | `mirror.bat` | 脚本 | 2.3 KB | 2026-11-04 | **本地** | 一键投屏主控脚本 |
| 13 | `pair.bat` | 脚本 | 2.4 KB | 2026-11-04 | **本地** | 无线配对与首次连接 |
| 14 | `mirror-wait.bat` | 脚本 | 80 B | 2026-11-04 | **本地** | 新窗口等待式启动 |
| 15 | `phone.txt` | 配置 | 20 B | 2026-11-04 | **本地** | 上次成功的无线地址 |
| 16 | `open_a_terminal_here.bat` | 脚本 | 5 B | 2025-10-08 | 官方 | 在当前目录开终端 |
| 17 | `scrcpy-noconsole.vbs` | 脚本 | 212 B | 2025-10-08 | 官方 | 无控制台窗口启动 |
| 18 | `LICENSE.txt` | 文本 | 11 KB | 2025-10-08 | 官方 | Apache 2.0 许可证 |
| 19 | `scrcpy.png` | 图片 | 6.4 KB | 2025-10-08 | 官方 | 程序图标 |
| 20 | `disconnected.png` | 图片 | 4.6 KB | 2025-10-08 | 官方 | 断开连接占位图 |

---

## 八、当前状态与可扩展点（仅观察，不做改动）

**观察结论：**

1. 项目可正常运行 —— `scrcpy.exe --version` 与 `adb.exe version` 均能正常输出版本，DLL 依赖完整，无缺失。
2. 本地脚本已成型：`pair.bat` 负责配对、`phone.txt` 缓存地址、`mirror.bat` 负责连接与启动，三者形成完整的"配对 → 记忆 → 复用"闭环。
3. `mirror.bat` 中 scrcpy 参数为硬编码（`1280 / 60fps / keep-active / always-on-top`），没有外部配置入口，也没有错误日志落盘。

**天然的可扩展位置（供后续需求参考）：**

| 位置 | 现状 | 可扩展方向 |
|---|---|---|
| `mirror.bat` 第 85–88 行 | 投屏参数写死在命令行 | 抽成 `config.bat` 或命令行开关（分辨率、帧率、码率、是否录音、是否录制） |
| `mirror.bat` 失败分支 | 仅 `echo` 提示到屏幕 | 追加写入 `logs\`，便于事后排查 |
| `phone.txt` | 单一地址、纯文本 | 支持多设备（一行一个，带别名 / 序列号） |
| 根目录 | 全部文件混放 | 新增 `logs\`、`recordings\`、`config\` 子目录 |
| 启动方式 | 仅 `.bat`（会留黑窗） | 结合 `scrcpy-noconsole.vbs` 思路做静默启动 |

---

*本文档为静态分析产物，未对项目做任何代码修改。等待后续具体需求。*
