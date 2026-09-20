# build.ps1 的来历

`build.ps1` 的最初版本是直接让 AI 生成后落盘的，作者把当时的 prompt 原文留在了脚本末尾。
2026-09-20 重写脚本时把这段 prompt 挪到这里保存（脚本本身不再混杂历史对话）：

---

既然是开源，我认为应该把 prompt 开源出来才算，毕竟这个脚本更像编译后的产物，而不是源代码本身。

帮我写一个自动化脚本，做以下几件事：

1. 脚本所在目录是项目的根目录，脚本应该运行在 windows 电脑上，接收一个参数，这个参数的值会是 xfce、lxqt 或 gxde。
2. 在 `C:\Users\<你的用户名>\Downloads` 文件夹有 debian-xfce.tar.xz、debian-lxqt.tar.xz 和 debian-gxde.tar.xz，需要根据之前的参数对应选择，然后分成 98MB 的小份，命名为 `xa*`（就像 Linux 上的 `split -b 98M debian.tar.xz`），放到项目的 assets 文件夹。注意这个文件夹可能有之前残留的 `xa*` 文件，需要先彻底删除这些 `xa*` 文件。
3. 然后在当前目录运行 `flutter build apk --target-platform android-arm64 --split-per-abi --obfuscate --split-debug-info=tiny_computer/sdi` 编译。
4. 在 `build\app\outputs\flutter-apk` 文件夹会有 app-arm64-v8a-release.apk 和 app-arm64-v8a-release.apk.sha1 两个文件，需要重命名为 tiny-computer-xfce.apk 和 tiny-computer-xfce.apk.sha1（以 xfce 为例，具体名称根据参数来定）。

直接写成一个 ps1 脚本行吗。

请再添加一些功能：首先可以传入多个选项，比如传入 xfce lxqt 就可以自动进行这两个构建；其次需要一个新参数允许在生成的 apk 名字加入后缀，比如添加 targetSdk35 后缀，就会生成 tiny-computer-xfce-targetSdk35.apk 和 tiny-computer-xfce-targetSdk35.apk.sha1。

`xa*` 文件的命名不对。要按照 `split` 命令默认的那样，命名为 xaa、xab、xac… 另外我确定分割后的文件数量不多，不会超过 xaz。

---

## 2026-09-20 的改动要点

- 分片命名不再依赖“不会超过 xaz”这个口头假设，改为 `xaa…xaz, xba…`，超出命名空间直接抛错。
- 生成 `assets/xa.sha256`，App 首启解包前会用 `busybox sha256sum -c` 校验。
- 构建失败以非零退出码结束，可被 CI 正确识别。
- 每套桌面环境使用独立的 `--split-debug-info` 目录，避免符号表互相覆盖。
- 源码目录改为 `-SourceDir` / `$env:TC_ROOTFS_DIR` / `~/Downloads` 三级回退。
