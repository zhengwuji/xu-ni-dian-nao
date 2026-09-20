# 小小电脑 · xu-ni-dian-nao

**在你的安卓手机上装一台完整的 Linux 电脑。** 不用 root、不用刷机、不用先装 Termux——
装一个 APK，等几分钟初始化，就能得到一个带桌面环境的 Debian 系统，
在上面装 QQ、微信、WPS、Krita、火狐，跑 Wine 玩 Windows 程序。

本项目是开源项目 [Cateners/tiny_container](https://github.com/Cateners/tiny_container)
（小小电脑 / Tiny Computer，GPL-3.0）的**稳定性加固版**：功能与上游一致，
重点修掉首启安装、网络桥接、文件管理器崩溃等问题，并加上**全自动构建与发布**。

> 每次推送到 `main`，GitHub Actions 会自动编译 APK 并发布到
> [Releases](../../releases)，附带自动生成的更新日志。

---

## 目录

- [它是什么](#它是什么)
- [下载安装](#下载安装)
- [关于覆盖安装（重要）](#关于覆盖安装重要)
- [第一次启动](#第一次启动)
- [功能总览](#功能总览)
- [使用教程](#使用教程)
  - [1. 三种图形界面模式](#1-三种图形界面模式)
  - [2. 终端与快捷指令](#2-终端与快捷指令)
  - [3. 安装常用软件](#3-安装常用软件)
  - [4. 文件和安卓互传](#4-文件和安卓互传)
  - [5. 图形加速（VirGL / Turnip / DRI3）](#5-图形加速virgl--turnip--dri3)
  - [6. 运行 Windows 程序（Wine）](#6-运行-windows-程序wine)
  - [7. 麦克风与音频](#7-麦克风与音频)
  - [8. 高分辨率屏幕（HiDPI）](#8-高分辨率屏幕hidpi)
- [常见问题](#常见问题)
- [自动构建说明](#自动构建说明)
- [本地构建](#本地构建)
- [本仓库相对上游的改动](#本仓库相对上游的改动)
- [许可](#许可)

---

## 它是什么

| | |
| --- | --- |
| 系统 | Debian 13 (Trixie)，XFCE / LXQt / GXDE 桌面可选 |
| 运行方式 | proot 容器（**不需要 root**，不需要解锁 BL） |
| 图形界面 | Termux:X11（推荐）/ VNC，两种都内置 |
| 目标架构 | arm64-v8a |
| 系统要求 | Android 9（API 28）及以上 |

内置了完整的 Debian rootfs，**安装包自带全部组件**，不需要先装 Termux，
也不会和 Termux 冲突（两者可以共存）。

---

## 下载安装

到 **[Releases](../../releases)** 页面下载最新的 APK：

| 文件 | 说明 |
| --- | --- |
| `tiny-computer-xfce-<版本>.apk` | **推荐**，XFCE 桌面，像 Windows 的经典布局 |
| `tiny-computer-lxqt-<版本>.apk` | LXQt 桌面，更轻量，老机器可选 |
| `tiny-computer-gxde-<版本>.apk` | GXDE 桌面，国产桌面环境 |
| `*.apk.sha256` | APK 校验和，可用 `sha256sum -c` 验证 |
| `symbols-*.tar.gz` | 混淆符号表，用于符号化崩溃日志 |

**安装前请确认**：

- 手机是 **arm64** 架构（现在的手机基本都是）；
- 系统是 Android 9 以上；
- 至少留出 **3GB 可用空间**（rootfs 解包后占用较大）。

---

## 关于覆盖安装（重要）

本仓库每个版本都用**同一个固定发布密钥**签名，所以：

> ✅ **以后每个新版本都可以直接在旧版上覆盖安装，不需要卸载，容器里的数据全部保留。**

**唯一的例外**：如果你手机上装的是从**上游**下载的版本（比如 `小小电脑_1.0.100.apk`），
那它的签名是上游作者的密钥，本仓库没有这个私钥，所以**第一次**需要卸载后重装。

> ⚠️ 卸载会清空容器内的所有数据。第一次从上游版切换到本版之前，
> 记得先把容器里需要的东西通过共享文件夹拷出来。

从本仓库的任意版本开始，之后就一直可以覆盖更新了。

### 怎么验证签名一致

```bash
# 需要 apksigner（Android SDK build-tools 自带）
apksigner verify --print-certs tiny-computer-xfce-1.1.1.apk
```

两次输出的 `Signer #1 certificate SHA-256 digest` 相同，才能覆盖安装。
本仓库的 CI 在每次发布前都会自动做这个对比，不一致会直接报错中止发布。

---

## 第一次启动

1. **安装并打开**，会看到初始化界面；
2. 首次启动会做三件事（合计约 **3～10 分钟**，取决于手机性能）：
   - 复制引导包（proot、busybox、pulseaudio 等）；
   - 复制并校验 rootfs 分片；
   - 解包系统到容器目录。
3. **期间请保持屏幕常亮、不要切后台**——这是本版重点加固的地方，
   但中断仍可能导致安装重来（不会半残，会安全回滚）；
4. 完成后自动进入终端界面，点右下角 **▶** 进入图形桌面。

> 💡 如果空间不足或分片损坏，本版会**在开始前/解包前就明确报错**，
> 而不是像以前那样装到一半失败、界面却显示"安装完成"。

---

## 功能总览

### 桌面与显示

- **XFCE / LXQt / GXDE** 三种桌面环境
- **Termux:X11** 与 **AVNC (VNC)** 双图形后端，可随时切换
- **AVNC 分辨率自适应**：按当前手机屏幕自动调整远程桌面分辨率
- **AVNC 缩放因子**：0.25× ～ 4× 无级调节，适配不同 DPI
- **手动指定分辨率**：最高支持 7680×7680
- **HiDPI 支持**：高分辨率屏幕上放大 UI（可自定义环境变量）
- **屏幕常亮**：跑长任务时不息屏

### 性能与图形加速

- **VirGL**：通过 `virgl_test_server` 做 OpenGL 加速（实验性）
- **Turnip + Zink**：高通 Adreno GPU 的 Vulkan 驱动，跑 OpenGL 程序更快（实验性）
- **DRI3**：配合 Turnip 使用，进一步降低图形开销（实验性）

### 兼容性

- **Wine / Hangover**：在容器里跑 Windows 程序，含一键安装脚本
- **DXVK 开关**：把 Direct3D 调用转成 Vulkan，游戏兼容性更好
- **伪装 UOS**：让部分只认国产系统的软件（如微信）正常启动

### 输入与音频

- **完整终端**：xterm 内核，支持 Ctrl / Alt / Shift 粘滞键
- **终端小键盘**：Esc、Tab、方向键、PgUp/PgDn、Home/End、F1–F12
- **PulseAudio 音频转发**：容器内的声音输出到手机
- **麦克风支持**：把手机麦克风转发进容器（实验性）

### 文件互通

- **共享文件夹**：手机存储挂载到容器的 `/mnt/sdcard` 与 `~/公共`
- **系统文件管理器接入**：用安卓自带的「文件」应用直接浏览容器内部文件
  （基于 SAF DocumentsProvider，本版修复了打开即崩的问题）
- **剪切板互通**：终端与容器共享剪切板
- **存储权限一键申请**：普通存储权限 + 全部文件访问权限

### 其它

- **快捷指令**：常用操作做成一键按钮，可自己增删改
- **归档分享**：把当前容器配置导出分享给别人
- **日文环境切换**：一键生成 `ja_JP.UTF-8` locale
- **多语言**：简体中文 / 繁体中文 / 英文（跟随系统）

---

## 使用教程

### 1. 三种图形界面模式

打开 App 后是**终端界面**，点右下角 **▶** 进入图形桌面。用哪种模式在
**控制面板 → 显示设置** 里切换（切换后需要重启 App）：

| 模式 | 优点 | 缺点 | 适用 |
| --- | --- | --- | --- |
| **Termux:X11** | 延迟最低、支持 DRI3 加速、体验最接近原生 | 兼容性略差，个别老设备黑屏 | **推荐**，现代手机首选 |
| **AVNC (VNC)** | 兼容性最好，浏览器也能连 | 延迟略高 | 老设备 / X11 黑屏时 |
| **浏览器 (WebView)** | 无需额外 App，可在电脑浏览器打开 | 体验最一般 | 临时用 / 投屏演示 |

**推荐配置**（新手机）：

1. 显示设置 → 打开「默认使用 Termux:X11」；
2. 若手机是高通骁龙，再打开「启用 Turnip+Zink」和「启用 DRI3」；
3. 重启 App，点 ▶ 进入桌面。

**如果画面太大/太小**：显示设置 → 「AVNC 缩放因子」拖动调节，
或者关掉「AVNC 按屏幕调整分辨率」后手动填分辨率。

### 2. 终端与快捷指令

终端默认是**只读**的（防止误触）。要输入命令：

- **控制面板 → 全局设置 → 允许终端输入**，打开它。

然后你会看到：

- 顶部 **Ctrl / Alt / Shift** 三个粘滞键按钮——点一下再按字母就是组合键，
  例如 `Ctrl` → `C` 就是中断当前命令；
- 下方一排**小键盘**：方向键、Tab、F 键等手机键盘上没有的键；
- **快捷指令区**：点一下直接执行，长按可以**编辑或删除**，
  最后一个「+」是新增，长按它可以**恢复默认指令**。

内置的 26 条快捷指令包含：检查更新升级、查看系统信息、安装/卸载
Krita、Kdenlive、Octave、WPS、CAJViewer、亿图图示、QQ、微信、钉钉，
启用回收站、清理缓存、关机等。

> 💡 快捷指令本质就是往终端里发一串命令，所以你可以把任何常用操作做成按钮。

### 3. 安装常用软件

**方法一：用快捷指令（推荐给新手）**

控制面板里直接点「安装微信」「安装 QQ」等按钮，会自动下载并安装，
并在容器终端里显示进度。

**方法二：自己在终端里装**

```bash
sudo apt update
sudo apt install -y firefox-esr          # 火狐浏览器
sudo apt install -y libreoffice          # LibreOffice
sudo apt install -y gimp                 # GIMP 图像处理
sudo apt install -y vlc                  # VLC 播放器
```

`apt` 已经配好了国内镜像，速度通常不错。注意容器内默认用户是 `tiny`，
`sudo` 免密码。

**已内置的**：`firefox-esr`、`xfce4` 桌面、中文输入法、常用字体、
`neofetch`、`cmatrix` 等。

### 4. 文件和安卓互传

**方式 A：共享文件夹（最简单）**

| 容器内路径 | 对应安卓位置 |
| --- | --- |
| `~/公共` | 手机内部存储根目录 |
| `~/下载` | `Download` |
| `~/图片`、`~/视频`、`~/音乐`、`~/文档`、`~/照片` | 对应的系统目录 |
| `/mnt/sdcard` | `/storage/emulated/0` |

在容器里把文件放进 `~/公共`，手机文件管理器里就能看到，反之亦然。

**方式 B：用系统文件管理器直接浏览容器**

安卓自带的「文件」App 侧栏里会出现**小小电脑**这一项，
点进去能直接浏览容器内的所有文件（读写都支持）。

> 如果看不到，去 **控制面板 → 文件访问** 点一下「申请所有文件访问权限」。

**方式 C：在手机与容器之间拖文件**

用支持 SAF 的文件管理器（如「质感文件」），可以直接在手机侧和容器侧之间复制粘贴。

### 5. 图形加速（VirGL / Turnip / DRI3）

默认是软件渲染，能跑但 3D 性能一般。加速方案在
**控制面板 → 图形加速** 里（都是实验性功能，需要重启 App）：

| 开关 | 作用 | 前提 |
| --- | --- | --- |
| **启用 VirGL** | 用 virglrenderer 做 OpenGL 转发 | 通用，兼容性较好 |
| **启用 Turnip+Zink** | 用高通 Adreno 的 Vulkan 驱动跑 OpenGL | **仅高通骁龙**，且要配 Termux:X11 |
| **启用 DRI3** | 进一步降低合成开销 | 必须同时开 Turnip + Termux:X11 |

**建议顺序**：先试 VirGL，不行再试 Turnip+Zink；
两个都开了还是卡，就关掉全部加速用软件渲染（最稳）。

VirGL 服务器参数和环境变量可以在同一页面的输入框里自定义。

### 6. 运行 Windows 程序（Wine）

**控制面板 → Windows 应用支持**：

1. 点「安装 Hangover 稳定版（10.14）」——会自动下载并安装 Wine；
2. 安装完成后，下面会出现一排 Wine 指令按钮：

   - **Wine 配置**：打开 `winecfg`
   - **修复方块字**：修复中文显示成方块的问题
   - **开始菜单文件夹**：打开 Wine 的开始菜单目录
   - **开启 / 关闭 DXVK**：Direct3D → Vulkan 转换
   - **我的电脑 / 记事本 / 扫雷 / 注册表 / 控制面板 / 文件管理器 /
     任务管理器 / IE 浏览器**
   - **强制关闭 Wine**：卡死时用

3. 装完 Windows 程序后，用「我的电脑」找到 `.exe` 双击运行。

> ⚠️ 注意：x86 程序需要 Hangover 的 box64 转换，**性能有限**，
> 适合小工具和 2D 程序，3D 游戏基本跑不动。

### 7. 麦克风与音频

**声音输出**是默认开启的（PulseAudio 转发），
容器里播放音乐、看视频都有声音。

**麦克风输入**（实验性）：**控制面板 → 麦克风支持 → 打开「开始推流」**，
第一次会申请麦克风权限。开启后容器里会多出一个「Android Virtual Mic」输入设备。

> 如果容器里的应用检测不到麦克风，检查它是否选了
> 「Tiny Microphone Input」，或者重启那个应用。

**端口冲突**：如果和别的软件抢端口，可以在
**全局设置 → PulseAudio 端口** 里改（默认 4718）。

### 8. 高分辨率屏幕（HiDPI）

在 2K / 4K 屏手机上，桌面 UI 会显得特别小。打开
**控制面板 → 显示设置 → 启用 HiDPI 支持**，默认会让 UI 放大 2 倍。

想自己调，就在同一页面的「HiDPI 环境变量」里改，默认值是：

```
GDK_SCALE=2 QT_FONT_DPI=192
```

改完需要重启 App 生效。

---

## 常见问题

**Q：第一次启动卡在"正在复制容器系统"很久？**
正常，rootfs 解包要好几分钟。本版会校验每个分片并在解包前给空间预检，
如果真是空间不足或文件损坏，会明确报错而不是一直转圈。

**Q：装完打开黑屏？**
换图形后端试试：显示设置里关掉 Termux:X11，改用 AVNC。
上游也建议过：如果 XFCE 版黑屏，可以换成 LXQt 版。

**Q：提示 `INSTALL_FAILED_UPDATE_INCOMPATIBLE` 装不上？**
签名不一致。见上面的[关于覆盖安装](#关于覆盖安装重要)。
如果你之前装的是上游版，需要先卸载。

**Q：容器里 `sudo` 报错？**
多用户 / 分身场景下 sudo 有问题，这是已知问题。

**Q：怎么把容器配置分享给别人？**
用归档功能导出当前容器，对方在 App 里用导入按钮加载。

**Q：更新版本会丢数据吗？**
从本仓库的版本开始，覆盖安装**不会**丢数据。只有卸载才会。

**Q：能装 Docker / systemd / GNOME 吗？**
不能。proot 环境不支持，作者也明确不做这些。

**Q：支持 chroot 吗？**
不支持，proot 是故意选的设计。

**Q：手机需要 root 吗？**
不需要。

---

## 自动构建说明

推送到 `main` 分支会自动触发 `.github/workflows/build-release.yml`：

```
推送到 main
   │
   ├─ 1. 准备构建输入
   │     └─ 仓库里没有 assets/xa* 时，自动从上游 Release
   │        下载 debian-xfce.tar.xz / jniLibs.zip / patch.tar.gz
   │        并按 98MB 切成 xa* 分片，生成 assets/xa.sha256
   │
   ├─ 2. 配置签名（从 Secrets 还原 keystore）
   │
   ├─ 3. flutter analyze + flutter test（失败不阻断发布）
   │
   ├─ 4. flutter build apk --release（arm64，混淆 + 符号表归档）
   │
   ├─ 5. 校验签名 / 包名 / versionCode
   │     └─ 自动下载上一个 Release 的 APK 做对比，
   │        签名不一致或 versionCode 回退就报错中止
   │
   ├─ 6. 生成更新日志（读 CHANGELOG.md，没有就用 commit 记录分类）
   │
   └─ 7. 创建 GitHub Release 并上传 APK / 校验和 / 符号表
```

也可以在 **Actions → Build & Release APK → Run workflow** 手动触发，
可选桌面环境、自定义 tag、是否标记为预发布。

### 需要配置的 Secrets

仓库 → Settings → Secrets and variables → Actions：

| Secret | 说明 |
| --- | --- |
| `KEYSTORE_BASE64` | keystore 的 base64：`base64 -w0 keys/release.jks` |
| `KEYSTORE_PASSWORD` | keystore 口令 |
| `KEY_ALIAS` | 密钥别名 |
| `KEY_PASSWORD` | 密钥口令 |

没配置也能出包，但会用 debug 签名，**装不了已有版本**，日志里会打警告。

> 🔐 keystore 丢了就再也没法给已发布版本做覆盖更新，请务必备份。

### 发版流程

1. 改代码并提交（建议用 `feat:` / `fix:` / `perf:` / `docs:` 前缀）；
2. 改 `pubspec.yaml` 的版本号：`<版本>+<构建号>`，
   **构建号必须递增**（它就是 `versionCode`，不递增无法覆盖安装）；
3. 在 `CHANGELOG.md` 加一节同名标题，写清楚改了什么；
4. 推送到 `main`，剩下的交给 CI。

---

## 本地构建

需要 **Flutter ≥ 3.38.4** 和 **Android SDK**（JDK 17）。

```bash
# 1. 准备构建输入
#    a) 从 Releases 下载 jniLibs.zip，解压到 android/app/src/main/jniLibs/arm64-v8a
#    b) 下载 patch.tar.gz 放到 assets/
#    c) 下载 debian-xfce.tar.xz 放到 ~/Downloads/
#       （或自己按 extra/build-tiny-rootfs.md 制作）

# 2. 一键构建（自动切分 rootfs、生成校验清单、编译）
./build.sh xfce

# 连续构建多个桌面环境
./build.sh xfce lxqt gxde

# 只切分和生成哈希，不编译
SKIP_BUILD=1 ./build.sh xfce

# 指定 rootfs 目录
SOURCE_DIR=/path/to/rootfs ./build.sh xfce
```

Windows 上等价：

```powershell
.\build.ps1 xfce -SourceDir D:\Downloads
.\build.ps1 xfce lxqt -SkipBuild
```

两个脚本都会：

1. 把 rootfs 切成 98MB 分片 `xaa`…`xaz`；
2. 生成 `assets/xa.sha256` 校验清单；
3. 校验构建输入（缺 jniLibs / 分片直接中止）；
4. 编译并输出 APK + SHA-256。

> ⚠️ **分片命名有硬约束**：App 端用 `cat xa*` 拼接，
> 依赖字典序等于拆分顺序，所以分片数**不能超过 26**。
> 两个脚本都会在超过 26 片时直接报错。

---

## 本仓库相对上游的改动

完整清单见 [CHANGELOG.md](CHANGELOG.md)，核心是四块：

### 1. 首启安装不再"假成功"

- 安装脚本加 `set -e`，每一步都检查退出码。以前任何一步失败都会被下一句覆盖，
  界面照样显示"安装完成"，用户拿到半残容器；
- rootfs 分片逐个 SHA-256 校验，损坏的包**在解包前**就报错；
- 解包到 `containers/0.staging` 再**原子替换**，失败自动回滚；
- 支持**断点续跑**：已复制且大小正确的分片会跳过，失败重试不用重灌 GB 级数据；
- 加**空间预检**（分片 × 3 + 512MB）。

### 2. 修复 Android 13+ 上网络相关程序被误杀

`getifaddrs_bridge` 客户端原来在 socket 连接失败时直接 `exit(1)`，
而这个库是用 `LD_PRELOAD` 覆盖 `getifaddrs` 的——于是"桥没跑起来"
会变成"容器内所有调用 `getifaddrs` 的程序被杀死"（ssh / curl / 浏览器 /
桌面组件全受影响）。现在失败会**回退到 libc 的真实实现**。

服务端也加了 `SIGPIPE` 忽略、`flock` 单实例锁、`PR_SET_PDEATHSIG`、
socket 权限 `0600`、连接超时；协议加上长度帧头，IPv6 / AF_PACKET
地址不再被截成 16 字节。

### 3. 修复系统文件管理器打开容器目录崩溃

`TinyDocumentsProvider.queryDocument` 会把内部 file 变量覆盖成 `null`，
随后 `file.isDirectory()` 直接 NPE——用系统文件管理器浏览容器目录**必崩**。
另补上取消信号支持、排序、搜索大小写、路径校验、缩略图尺寸限制。

### 4. 构建工程化

- 新增 GitHub Actions 自动构建发布；
- `build.ps1` 重写：去掉硬编码路径、失败返回非零退出码、
  每套桌面环境独立符号目录（原先互相覆盖导致崩溃栈无法符号化）、
  构建前校验输入；
- 新增 Linux/CI 版 `build.sh`，与 `build.ps1` 同一套规则。

---

## 许可

GPL-3.0，与上游一致。详见 [COPYING](COPYING)。

上游项目：[Cateners/tiny_container](https://github.com/Cateners/tiny_container)

感谢 Termux 社区、[tmoe](https://github.com/2moe/tmoe)、
[AVNC](https://github.com/gujjwal00/avnc)、
[Termux:X11](https://github.com/termux/termux-x11) 等项目的开源工作。
