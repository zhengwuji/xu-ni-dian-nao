#!/usr/bin/env bash
# 生成 Release 的更新日志。
#
# 取值优先级：
#   1. CHANGELOG.md 里对应版本的小节（如果存在，推荐日常维护它）
#   2. 上一个 tag 到当前提交的 git log（排除 merge / 纯文档提交），自动分类
#
# 输出到 stdout，由 workflow 写进 release-body。

set -euo pipefail

DESKTOP="${DESKTOP:-xfce}"
SIGNED="${SIGNED:-false}"
VERSION=$(grep -E '^version:' pubspec.yaml | head -1 | sed -E 's/^version:[[:space:]]*//' | tr -d '\r')
NAME="${VERSION%%+*}"
BUILD="${VERSION##*+}"
SHORT_SHA=$(git rev-parse --short HEAD)
DATE=$(date -u '+%Y-%m-%d %H:%M UTC')

# ---------- 变更条目 ----------
CHANGES=""
if [ -f CHANGELOG.md ]; then
  # 抓取 "## [1.1.0]" 或 "## 1.1.0" 到下一个 "## " 之间的内容
  CHANGES=$(awk -v ver="$NAME" '
    /^##[[:space:]]/ {
      if (found) exit
      line=$0
      gsub(/[\[\]]/, "", line)
      if (index(line, ver) > 0) { found=1; next }
    }
    found { print }
  ' CHANGELOG.md | sed '/^[[:space:]]*$/d')
fi

if [ -z "$CHANGES" ]; then
  # 回退：git log。找最近的一个 tag，没有就用最近 30 个提交
  LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
  if [ -n "$LAST_TAG" ]; then
    RANGE="${LAST_TAG}..HEAD"
    RANGE_DESC="自 \`${LAST_TAG}\` 以来的改动"
  else
    RANGE="HEAD~30..HEAD"
    RANGE_DESC="最近 30 个提交"
  fi

  RAW=$(git log "$RANGE" --no-merges --pretty=format:'%s' 2>/dev/null || git log -30 --no-merges --pretty=format:'%s')

  # 分类规则同时兼容两种风格：
  #   约定式提交 —— "feat: xxx" / "fix(scope): xxx"
  #   自然语言标题 —— "Add xxx" / "Fix xxx" / "Update xxx"（上游历史大量使用这种）
  classify() {
    local pattern="$1"
    printf '%s\n' "$RAW" | grep -iE "$pattern" | sed -E 's/^[[:space:]]*//; s/^/- /' || true
  }

  FEAT=$(classify '^(feat|feature)(\(.+\))?[:：]|^add(ed)?[[:space:]]|^(新增|增加|添加)')
  FIX=$(classify '^(fix|bugfix|hotfix)(\(.+\))?[:：]|^fix(es|ed)?[[:space:]]|^(修复|修正|解决)')
  PERF=$(classify '^perf(\(.+\))?[:：]|^(optimize|improve|speed)[[:space:]]|^(优化|性能)')
  REFACTOR=$(classify '^refactor(\(.+\))?[:：]|^(rewrite|migrate|cleanup)[[:space:]]|^(重构|整理)')
  DOCS=$(classify '^docs?(\(.+\))?[:：]|^(update|readme)[[:space:]]*(readme|doc|docs)|^(文档)')
  # 其它：排除上面已归类的，再排除纯维护类提交
  OTHER=$(printf '%s\n' "$RAW" \
    | grep -viE '^(feat|feature|fix|bugfix|hotfix|perf|refactor|docs?)(\(.+\))?[:：]' \
    | grep -viE '^(add(ed)?|fix(es|ed)?|optimize|improve|speed|rewrite|migrate|cleanup)[[:space:]]' \
    | grep -viE '^(chore|ci|build|test|style|bump|version|release)([[:space:]:：(]|$)' \
    | grep -viE '^[0-9.]+$|^(draft|wip)$' \
    | sed -E 's/^[[:space:]]*//; s/^/- /' || true)

  CHANGES=""
  [ -n "$FEAT" ]     && CHANGES="${CHANGES}### ✨ 新功能
${FEAT}

"
  [ -n "$FIX" ]      && CHANGES="${CHANGES}### 🐛 修复
${FIX}

"
  [ -n "$PERF" ]     && CHANGES="${CHANGES}### ⚡ 性能
${PERF}

"
  [ -n "$REFACTOR" ] && CHANGES="${CHANGES}### ♻️ 重构
${REFACTOR}

"
  [ -n "$DOCS" ]     && CHANGES="${CHANGES}### 📝 文档
${DOCS}

"
  [ -n "$OTHER" ]    && CHANGES="${CHANGES}### 🔧 其它
${OTHER}

"
  [ -z "$CHANGES" ]  && CHANGES="_本次提交未使用约定式提交信息（feat: / fix: …），无法自动分类，详见下方提交记录。_"
  CHANGES="基于 ${RANGE_DESC}：

${CHANGES}"
fi

# ---------- 签名说明 ----------
if [ "$SIGNED" = "true" ]; then
  SIGN_NOTE="✅ **正式签名**：可以**直接覆盖安装**更新，不需要卸载，容器数据会保留。"
  INSTALL_STEP_4="以后每个版本都可以在旧版基础上直接覆盖安装（**不要卸载**，卸载会清空容器里的数据）。"
else
  SIGN_NOTE="> ⚠️ **本次构建使用 debug 签名，无法覆盖安装已有版本。**  
> 请配置仓库 Secrets（\`KEYSTORE_BASE64\` / \`KEYSTORE_PASSWORD\` / \`KEY_ALIAS\` / \`KEY_PASSWORD\`）后重新构建。"
  INSTALL_STEP_4="本次是 debug 签名，安装前需先卸载旧版本（会丢容器数据）。配置正式签名后即可直接覆盖更新。"
fi

APK_NAME="tiny-computer-${DESKTOP}-${NAME}.apk"
SHA=$(sha256sum "artifacts/$APK_NAME" 2>/dev/null | cut -d' ' -f1 || echo "（见 SHA256SUMS）")
SIZE=$(du -h "artifacts/$APK_NAME" 2>/dev/null | cut -f1 || echo "?")

cat <<EOF
# 小小电脑 ${NAME} · ${DESKTOP} 桌面

从 \`${SHORT_SHA}\` 自动构建 · ${DATE}

## 本次更新

${CHANGES}
## 下载

| 文件 | 说明 |
| --- | --- |
| \`${APK_NAME}\` | 主程序（arm64-v8a，${SIZE}） |
| \`${APK_NAME}.sha256\` | APK 校验和 |
| \`symbols-*.tar.gz\` | 混淆符号表，用于符号化线上崩溃 |

- **SHA-256**：\`${SHA}\`
- 构建号：\`${BUILD}\`
- 目标架构：arm64-v8a（Android 9 / API 28 及以上）

## 安装说明

1. 下载 \`${APK_NAME}\` 安装；
2. 首次启动会解包内置 rootfs（约数分钟，请保持屏幕常亮并留足 3GB 空间）；
3. 无需先装 Termux 或 Linux，APK 自带全部组件；
4. ${INSTALL_STEP_4}

${SIGN_NOTE}

## 源码

- 本仓库：https://github.com/${GITHUB_REPOSITORY}
- 上游项目：https://github.com/Cateners/tiny_container （GPL-3.0）
EOF
