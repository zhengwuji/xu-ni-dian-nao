# 更新日志

本项目是 [Cateners/tiny_container](https://github.com/Cateners/tiny_container)（小小电脑 / Tiny Computer）的一个分支，
在此之上做稳定性与工程化改进。版本号沿用上游的格式 `<主版本>+<构建号>`。

> **怎么用**：每次发版前在下面加一节 `## <版本号>`，CI 会自动把该节内容取出来作为 Release 的更新日志。
> 如果没写，CI 会退回去用 git commit 记录（约定式提交 `feat:` / `fix:` 会被自动分类）。

---

## 1.1.2

> 稳定性与工程化增强版本：优化 CI 依赖缓存、修复 Wine 符号字体映射与脚本退出码、精简 Android 构建。
> **支持覆盖安装**，与 1.1.1 签名保持一致，容器数据完整保留。

### ⚡ 构建与 CI 缓存优化
- GitHub Actions 增加上游原料缓存（`actions/cache@v4`），自动缓存 rootfs、jniLibs 与 patch 包，大幅提升后续构建速度并规避外部下载波动。
- Android 打包添加 `androidResources.noCompress`，防止 aapt2 对已压缩的 rootfs 分片及归档重复压缩，显著缩短 APK 组包耗时。
- `android/app/build.gradle` 卫生优化：关闭 debug 编译阶段的代码混淆（`minifyEnabled false`），禁用未使用的 `aidl` 与 `dataBinding` 特性。

### 🐛 修复 Wine 图标与特殊符号变方块乱码
- `extra/cross/chn_fonts.reg`：剔除对 `Marlett`、`Wingdings`、`Webdings`、`Segoe MDL2 Assets` 等 13 种符号/图标字体的中文字体强制映射，修复 Wine 桌面窗口按钮（最小化/最大化/关闭）及应用特殊图标显示为方块/乱码的问题。

### 🛡️ 脚本健壮化与系统安全加固
- `extra/cross/install-hangover*`：启用 `set -euo pipefail`，修复下载镜像全部失败分支裸 `exit` 导致返回码为 0（误报成功）的问题，保证安装异常能被正确捕获与上报。
- `AndroidManifest.xml`：添加 `android:allowBackup="false"`，防止应用与容器私有数据通过 ADB 备份导出泄漏；收敛内部页面 `Signal9Activity` 的 `android:exported="false"`。

---

### 🐛 首启安装不再中途“假成功”
- 安装脚本加 `set -e`，每一步都检查退出码。以前任何一步失败都会被下一句覆盖，
  界面照样显示“安装完成”，用户拿到的是一个半残的容器。
- rootfs 分片逐个做 SHA-256 校验（构建时产出 `assets/xa.sha256`），
  下载损坏的包会在解包前就报错，而不是解出坏掉的文件系统。
- 解包改到 `containers/0.staging` 再原子替换，失败自动回滚，
  不会再留下“装了一半”的容器目录。
- 复制分片支持断点续跑：已复制且大小正确的分片会跳过，
  失败重试不用再重灌一遍 GB 级数据。
- 加空间预检：装机前先算“分片 × 3 + 512MB”，空间不够就提前给可读提示。

### 🐛 修复 Android 13+ 上网络相关程序被误杀
- `getifaddrs_bridge` 客户端原来在 socket 连接失败时直接 `exit(1)`。
  这个库是用 `LD_PRELOAD` 覆盖 `getifaddrs` 的，于是“桥没跑起来”会变成
  “容器内所有调用 `getifaddrs` 的程序被杀死”（ssh / curl / 浏览器 / 桌面组件都受影响）。
  现在失败会回退到 libc 的真实实现，桥不可用只是退化为原生行为。
- 服务端加 `SIGPIPE` 忽略、`flock` 单实例锁、父进程退出自动收尸、
  socket 权限收紧到 `0600`、每条连接 2 秒收发超时，不再残留孤儿进程。
- 协议加上长度帧头，收发改为循环读写；IPv6 / AF_PACKET 地址不再被截成 16 字节。

### 🐛 修复系统文件管理器打开容器目录崩溃
- `TinyDocumentsProvider.queryDocument` 会把内部 file 变量覆盖成 `null`，
  随后 `file.isDirectory()` 直接 NPE。用系统文件管理器浏览容器目录时必崩。
- 补上取消信号支持与排序：容器 rootfs 里 `/usr/share` 这类目录有上万个条目，
  以前会把 Binder 线程占死且无法取消。
- 修复搜索大小写（搜 "Documents" 以前搜不到 "documents"）、
  子目录判断的前缀边界、缩略图返回整个原文件等问题。

### 🔧 构建工程化
- 新增 GitHub Actions：推送到 `main` 自动编译 APK 并发布到 Releases，
  自动生成更新日志（读本文件，缺失时回退到 commit 记录）。
- `build.ps1` 重写：去掉硬编码路径、失败时返回非零退出码、
  每套桌面环境使用独立符号目录（以前会互相覆盖，已发布版本的崩溃栈无法符号化）、
  构建前校验输入（缺 jniLibs / 分片直接中止，不再产出“装得上但一启动就崩”的包）。
- 新增 Linux/CI 版 `build.sh`，与 `build.ps1` 使用同一套分片与校验规则。

---

## 1.1.1

> 本版本首次提供自动构建：推送到 `main` 后由 GitHub Actions 编译 APK 并发布到 Releases。
> **可以覆盖安装**（使用固定的发布签名），容器数据会保留。

### 🐛 首启安装不再中途“假成功”
- 安装脚本加 `set -e`，每一步都检查退出码。以前任何一步失败都会被下一句覆盖，
  界面照样显示“安装完成”，用户拿到的是一个半残的容器。
- rootfs 分片逐个做 SHA-256 校验（构建时产出 `assets/xa.sha256`），
  下载损坏的包会在解包前就报错，而不是解出坏掉的文件系统。
- 解包改到 `containers/0.staging` 再原子替换，失败自动回滚，
  不会再留下“装了一半”的容器目录。
- 复制分片支持断点续跑：已复制且大小正确的分片会跳过，
  失败重试不用再重灌一遍 GB 级数据。
- 加空间预检：装机前先算“分片 × 3 + 512MB”，空间不够就提前给可读提示。

### 🐛 修复 Android 13+ 上网络相关程序被误杀
- `getifaddrs_bridge` 客户端原来在 socket 连接失败时直接 `exit(1)`。
  这个库是用 `LD_PRELOAD` 覆盖 `getifaddrs` 的，于是“桥没跑起来”会变成
  “容器内所有调用 `getifaddrs` 的程序被杀死”（ssh / curl / 浏览器 / 桌面组件都受影响）。
  现在失败会回退到 libc 的真实实现，桥不可用只是退化为原生行为。
- 服务端加 `SIGPIPE` 忽略、`flock` 单实例锁、父进程退出自动收尸、
  socket 权限收紧到 `0600`、每条连接 2 秒收发超时，不再残留孤儿进程。
- 协议加上长度帧头，收发改为循环读写；IPv6 / AF_PACKET 地址不再被截成 16 字节。

### 🐛 修复系统文件管理器打开容器目录崩溃
- `TinyDocumentsProvider.queryDocument` 会把内部 file 变量覆盖成 `null`，
  随后 `file.isDirectory()` 直接 NPE。用系统文件管理器浏览容器目录时必崩。
- 补上取消信号支持与排序：容器 rootfs 里 `/usr/share` 这类目录有上万个条目，
  以前会把 Binder 线程占死且无法取消。
- 修复搜索大小写（搜 "Documents" 以前搜不到 "documents"）、
  子目录判断的前缀边界、缩略图返回整个原文件等问题。

### 🔧 构建工程化
- 新增 GitHub Actions：推送到 `main` 自动编译 APK 并发布到 Releases，
  自动生成更新日志（读本文件，缺失时回退到 commit 记录）。
- 构建产物使用**固定发布签名**，支持从旧版本直接覆盖安装。
- `build.ps1` 重写：去掉硬编码路径、失败时返回非零退出码、
  每套桌面环境使用独立符号目录（以前会互相覆盖，已发布版本的崩溃栈无法符号化）、
  构建前校验输入（缺 jniLibs / 分片直接中止，不再产出“装得上但一启动就崩”的包）。
- 新增 Linux/CI 版 `build.sh`，与 `build.ps1` 使用同一套分片与校验规则。

---

## 1.1.0

以下为上游 `Cateners/tiny_container` 该版本的内容，本分支同步。

- 新增麦克风转发支持（`AudioStream.kt` + `native-socket.cpp`）
- 移除“伪装 UOS”开关及其挂载逻辑
- 改用 `AssetManifest` API 读取 `assets/xa*` 列表
- 更新 hangover / CAJViewer / QQ / WPS 的安装指令
- 依赖升级：AGP 8.9.1、Gradle 8.11.1、Kotlin 2.1.0 等
