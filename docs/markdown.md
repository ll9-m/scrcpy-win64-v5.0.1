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
├── pair.bat                    ① 配对入口（扫码 / 手输）
├── mirror.bat                  ② 投屏入口
├── mirror-wait.bat             ③ 等待式投屏入口
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
│   └── disconnected.png
├── config/
│   ├── phone.txt               上次连接成功的地址（不入库）
│   └── phone.txt.example       格式示例
├── docs/
│   ├── markdown.md             本文档
│   └── LICENSE.txt             Apache 2.0
└── scripts/
    ├── pair-qr.ps1             扫码配对编排
    └── lib/
        ├── qr.js               QR 编码器（v4 / 纠错 M）
        ├── qr.test.js          编码器往返测试
        └── html.test.js        页面渲染测试
```

统计：根目录 5 个脚本 + 1 个文档，`bin/` 13 个，`config/` 2 个，`docs/` 2 个，`scripts/` 4 个，合计 27 个受版本控制的文件，约 25.6 MB（其中 24.9 MB 是二进制）。

---

## 三、按层划分角色

| 层级 | 文件 | 职责 |
|---|---|---|
| **入口层** | `pair.bat`、`mirror.bat`、`mirror-wait.bat`、`open_a_terminal_here.bat`、`scrcpy-noconsole.vbs` | 用户双击的对象，负责参数与流程编排 |
| **编排层** | `scripts/pair-qr.ps1` | 扫码配对的完整状态机 |
| **算法层** | `scripts/lib/qr.js` | 二维码编码 |
| **主程序层** | `bin/scrcpy.exe`、`bin/scrcpy-server` | 客户端主机程序 + 设备端代理 |
| **通信层** | `bin/adb.exe`、`AdbWinApi.dll`、`AdbWinUsbApi.dll`、`libusb-1.0.dll` | 建立 PC ↔ 手机 通道 |
| **媒体层** | `avcodec-63.dll`、`avformat-63.dll`、`avutil-61.dll`、`swresample-7.dll` | 解码 H.264/H.265、处理音频 |
| **呈现层** | `SDL3.dll` | 开窗、渲染、键鼠事件映射 |
| **状态层** | `config/phone.txt` | 跨次运行持久化设备地址 |

---

## 四、逐文件说明

### 4.1 入口脚本（根目录）

#### `pair.bat` — 配对入口

- **用途**：一次性的设备配对引导，扫码为主、手输为辅。
- **流程**：
  1. 定位 `bin\adb.exe`，缺失则回退 PATH 并告警，两者都没有就报错退出；
  2. 打印模式菜单：**回车走扫码**（调用 `scripts\pair-qr.ps1`），**输入 `M` 走手输**；
  3. 扫码返回非 0（超时 / mDNS 不可用）时自动降级到 6 位码流程，不会让人卡死；
  4. 手输流程：`adb pair <IP:端口> <6位码>` → 等 3 秒 → 用 mDNS 嗅探真实连接端口 → `adb connect`；
  5. 成功后写入 `config\phone.txt`，并询问是否立刻投屏。
- **项目角色**：**`phone.txt` 的写入方之一**（另一处是 `mirror.bat` 的连接回调）。

#### `mirror.bat` — 投屏入口

- **用途**：日常一键投屏。
- **设备发现顺序**（四级回退）：
  1. `adb devices` 中带 `:` 的网络设备（跳过 `emulator-*`）；
  2. 普通 USB 设备；
  3. `config\phone.txt` 里保存的地址（**校验必须是 `IPv4:端口`**，防止 BOM / 空行污染）；
  4. `adb mdns services` 中的 `_adb-tls-connect._tcp`。
- **启动参数**：`--max-size=1280 --max-fps=60 --keep-active --always-on-top`（目前硬编码）。
- **`--wait`**：进入轮询模式，每约 15 秒重试一次，供 `mirror-wait.bat` 使用。
- **项目角色**：**主流程编排器**，整个项目的控制流都在这里。

#### `mirror-wait.bat` — 等待式启动

- **内容**：新开窗口执行 `mirror.bat --wait`。
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

读取方（`mirror.bat`）会用正则 `^[0-9.]+\.[0-9]+:[0-9]+$` 校验，不合法就当作不存在，继续走 mDNS —— 所以手工编辑坏了也不会导致连接失败，只是失去这项加速。

### 4.4 脚本（`scripts/`）

#### `pair-qr.ps1` — 扫码配对编排

- **协议依据**（AOSP `docs/dev/adb_wifi.md`）：二维码内容为
  `WIFI:T:ADB;S:<服务实例名>;P:<配对码>;;`
  手机扫到 `T:ADB` 后，会以 `S` 指定的实例名广播 `_adb-tls-pairing._tcp`；主机发现后执行 `adb pair`，配对成功手机会再广播 `_adb-tls-connect._tcp` 供连接。
- **执行序**：
  1. **预检**：启动 adb server → `adb mdns check` 必须含 `mdns daemon version`，否则直接退出（码 3），不让人干等；
  2. **短路**：已有网络设备在线时直接提示"无需配对"退出（码 0）；
  3. **生成**：随机 `scrcpy-<8位hex>` 服务名 + 6 位配对码，用字符串拼接组装 payload 并做格式自检；
  4. **渲染**：把 `lib/qr.js` 内联进本地 HTML，写明浅色主题、白底、4 模块静区、410px 画布，用默认浏览器打开；
  5. **配对**：轮询 `adb mdns services`，优先匹配自己请求的实例名；每个地址**只尝试一次**，以输出含 `Successfully paired` 判定；失败地址永不再试（配对通道一次性，重试只会 `protocol fault`）；
  6. **连接**：**重新发现** `_adb-tls-connect._tcp`（配对端口 ≠ 连接端口），优先同 IP 的条目，以 `adb devices` 状态为 `device` 为准；
  7. **落盘**：写入 `config\phone.txt`，询问是否立刻投屏。
- **退出码**：`0` 成功 / 已连接，`1` 环境问题，`2` 超时，`3` mDNS 不可用。

#### `lib/qr.js` — 二维码编码器

- 固定 **版本 4、纠错等级 M**（33×33，100 码字 = 2 块 × (32 数据 + 18 纠错)）。
- 固定版本的好处：不需要版本 / 容量表，而这正是手写编码器最易出错的地方。
- 实现包含 GF(256) 运算、Reed-Solomon 生成多项式、交织、8 种掩码 + 罚分择优、BCH(15,5) 格式信息。
- **不联网、不依赖第三方库**，纯文本随包携带。

#### `lib/qr.test.js` / `lib/html.test.js` — 自测

- `qr.test.js`：从矩阵**反向解码**出原文并比对；校验两份格式信息一致且 BCH 有效；对每个 RS 块在 α⁰..α¹⁷ 上求值必须全零；断言数据区 807 位（800 数据 + 7 剩余）。
- `html.test.js`：注入 DOM 桩**真实执行页面渲染脚本**，比对 SVG 矩形与已验证矩阵是否逐位一致。

### 4.5 文档与配置

| 文件 | 说明 |
|---|---|
| `README.md` | 快速上手、常见问题 |
| `docs/markdown.md` | 本文档 |
| `docs/LICENSE.txt` | Apache 2.0 全文 |
| `.gitignore` | 忽略 `phone.txt`、`logs/`、`*.log`、`*.zip`、`.workbuddy/` |
| `.gitattributes` | `.bat`/`.vbs`/`.ps1` 锁 CRLF；exe/dll/png/`scrcpy-server` 标为二进制 |

---

## 五、运行时链路

### 投屏

```
mirror.bat
  └─ adb devices ──► 网络设备 / USB 设备
       ├─ 无 → config\phone.txt（校验后 adb connect）
       └─ 无 → adb mdns services → _adb-tls-connect._tcp
            └─ scrcpy.exe -s <serial> --max-size=1280 ...
                 ├─ 推送 scrcpy-server 到手机并启动
                 ├─ FFmpeg 解码 ◄── 手机 MediaCodec 编码
                 └─ SDL3 渲染 + 反向注入键鼠
```

### 扫码配对

```
pair.bat ──► pair-qr.ps1
               ├─ adb mdns check（不可用则直接退出）
               ├─ 生成 WIFI:T:ADB;S:<名>;P:<码>;; → HTML → 浏览器
               ├─ 手机扫码 → 广播 _adb-tls-pairing._tcp
               ├─ 发现 → adb pair <IP:配对端口> <码>
               ├─ 手机再广播 _adb-tls-connect._tcp
               ├─ adb connect <IP:连接端口>
               └─ 写 config\phone.txt
```

---

## 六、三条硬约束（改动前必读）

1. **`scrcpy.exe` 按自身所在目录找图标和服务端**。二进制内含 `SCRCPY_ICON_DIR`、`SCRCPY_SERVER_PATH`、`Using icon (portable)`、`GetModuleFileNameW`。因此 `scrcpy-server` 必须与 exe 同目录；入口脚本已显式设置这两个环境变量，**不要依赖当前工作目录**。
2. **`scrcpy-server` 不能换成别的版本**，它与 `scrcpy.exe` 的协议必须匹配。
3. **配对端口 ≠ 连接端口**。`adb pair` 用的端口在配对完成后即失效，连接必须重新发现 `_adb-tls-connect._tcp` 的端口。

另外两条工程约定：

- **`.bat` 内只用 ASCII**。cmd 按 OEM 代码页逐字节读脚本，写入 UTF-8 中文会乱码，`chcp 65001` 又会破坏后续解析。中文提示只放在 `.ps1` 里。
- **`.ps1` 必须存为 UTF-8 with BOM**。PowerShell 5.1 对无 BOM 的文件按 ANSI 解析，中文会变乱码。

---

## 七、版本历史

| 提交 | 内容 |
|---|---|
| `chore: import ... baseline` | 原始 20 个文件原样入库 |
| `refactor: split into bin/, config/, docs/` | 目录分区 + 路径适配 + 图标 / 服务端环境变量固定 |
| `fix: harden device discovery ...` | 设备地址校验、`phone.txt` 格式校验、跳过模拟器、adb 兜底告警、不再误杀共享 adb server |
| `feat: pair by scanning a QR code` | 扫码配对全流程 + 自研 QR 编码器 + 自测脚本 |

---

## 八、待办（下一步方向）

| 优先级 | 内容 |
|---|---|
| 高 | 投屏参数外置到 `config/settings.bat`（分辨率、帧率、码率、录制、音频） |
| 高 | 关键步骤写 `logs/`，失败时保留 adb 原始输出 |
| 中 | `config/devices.txt` 支持多设备（别名 + 地址） |
| 中 | `tools/package.ps1` 一键生成干净 zip；`tools/shortcut.ps1` 生成带图标的桌面快捷方式 |
