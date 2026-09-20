# xu-ni-dian-nao · 小小电脑（自动构建版）

在 Android 手机上跑 Debian 桌面环境的 App，基于开源项目
[Cateners/tiny_container](https://github.com/Cateners/tiny_container)（小小电脑 / Tiny Computer，GPL-3.0）。

本仓库的定位是**稳定性加固版**：功能与上游一致，重点修掉首启安装、网络桥接、
文件管理器崩溃等问题，并加上全自动构建与发布。

---

## 下载安装

到 [Releases](../../releases) 下载最新的 `tiny-computer-xfce-*.apk` 安装即可。

- 自带 rootfs，**不需要**先装 Termux，也不需要 root。
- 首次启动会解包系统（约几分钟，请保持屏幕常亮，预留 **3GB 以上空间**）。
- 目标架构 arm64-v8a，Android 9（API 28）及以上。

### 关于「覆盖安装」

本仓库的每个版本都用**同一个固定发布密钥**签名，所以之后每个新版本都可以
**直接在旧版上覆盖安装，不需要卸载，容器里的数据会保留**。

只有一次例外：如果你手机上装的是从**上游**下载的版本（或 1.0.100 之类的旧包），
它的签名是上游作者的密钥，本仓库没有这个私钥，因此**第一次**需要卸载后重装——
之后就永久可以覆盖更新了。

> ⚠️ 卸载会清空容器内的所有数据。第一次切换请先备份容器里需要的东西。

---

## 自动构建

推送到 `main` 或手动触发 workflow 后，GitHub Actions 会：

1. 下载并准备构建输入（jniLibs、patch.tar.gz、rootfs 分片）；
2. 编译 arm64 release APK；
3. 校验签名 / 包名 / versionCode，确认新包可以覆盖旧包；
4. 自动生成更新日志（读 `CHANGELOG.md`，没写就回退到 commit 记录）；
5. 创建 GitHub Release 并上传 APK、校验和、符号表。

也可以在 Actions 页面手动触发（`workflow_dispatch`），可选桌面环境
（`xfce` / `lxqt` / `gxde`）、自定义 tag、是否标记为预发布。

### 让它支持「覆盖安装」需要配置签名

仓库 → Settings → Secrets and variables → Actions，添加 4 个 Secret：

| Secret | 说明 |
| --- | --- |
| `KEYSTORE_BASE64` | keystore 文件的 base64：`base64 -w0 keys/release.jks` |
| `KEYSTORE_PASSWORD` | keystore 口令 |
| `KEY_ALIAS` | 密钥别名（如 `upload`） |
| `KEY_PASSWORD` | 密钥口令 |

**没有配置时** CI 仍能出包，但用的是 debug 签名，装不了已有版本，日志里会打警告。

> 🔐 `keys/`、`*.jks`、`android/keystore.properties` 都已在 `.gitignore` 里，
> 不会误提交。keystore 一旦丢失，就再也无法给已发布的版本做覆盖更新了，请务必备份。

---

## 发版流程

1. 改代码；
2. 改 `pubspec.yaml` 的版本号（`<版本>+<构建号>`，**构建号必须递增**，否则无法覆盖安装）；
3. 在 `CHANGELOG.md` 加一节同名标题，写清楚这次改了什么；
4. 推送到 `main` —— CI 自动编译、自动发布、自动把这一节内容写进 Release 说明。

提交信息建议用约定式提交（`feat:` / `fix:` / `perf:` / `docs:`），
这样即使忘了写 CHANGELOG，自动生成的日志也能正确分类。

---

## 本地构建

需要 Flutter（`>=3.38.4`）与 Android SDK。

```bash
# 1. 准备输入：把 jniLibs.zip 解压到 android/app/src/main/jniLibs/arm64-v8a
#    把 patch.tar.gz 放到 assets/，rootfs 切成 98MB 分片也放 assets/
cp /path/to/debian-xfce.tar.xz ~/Downloads/
./build.sh xfce

# Windows 上等价：
#   .\build.ps1 xfce -SourceDir D:\Downloads
```

`build.sh` / `build.ps1` 都会：切分 rootfs → 生成 `assets/xa.sha256` 校验清单 →
校验构建输入 → 编译 → 输出 APK 与 SHA-256。

只想切分和算哈希、不编译：`SKIP_BUILD=1 ./build.sh xfce`。

---

## 本仓库相对上游的改动

见 [CHANGELOG.md](CHANGELOG.md)，主要四块：

- **首启安装**：退出码检查、分片 SHA-256 校验、原子替换、断点续跑、空间预检；
- **网络桥接**（`getifaddrs_bridge`）：客户端不再 `exit(1)` 杀进程，
  服务端加单实例锁、SIGPIPE 保护、权限与超时；
- **文件管理器**（`TinyDocumentsProvider`）：修复 `queryDocument` 必 NPE，
  补取消信号、排序、路径校验；
- **构建**：自动 CI 发布、构建输入闸门、固定的分片与校验规则。

---

## 许可

GPL-3.0（与上游一致），见 [COPYING](COPYING)。
