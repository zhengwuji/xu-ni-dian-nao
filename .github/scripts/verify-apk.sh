#!/usr/bin/env bash
# 校验 APK 的覆盖安装安全性。
#
# Android 只按「签名证书 + 包名 + versionCode」判断能否直接覆盖安装，本脚本把这三项
# 都查出来做对比，避免出现“新版本装不上去、必须卸载重装”的情况（卸载会丢容器数据）。
#
# 用法:
#   ./verify-apk.sh new.apk                    # 只打印新包的签名指纹/包名/版本
#   ./verify-apk.sh new.apk old.apk            # 对比两个包，判断能否覆盖安装
#
# 需要 build-tools 里的 aapt2 / apksigner。CI 上由 android-actions/setup-android 提供。

set -euo pipefail

# ---------- 找工具 ----------
find_tool() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
  local found=""
  if [ -d "$sdk/build-tools" ]; then
    found=$(find "$sdk/build-tools" -maxdepth 2 -type f -name "$name" 2>/dev/null | sort -V | tail -1)
  fi
  if [ -z "$found" ] && [ -d "$sdk/cmdline-tools" ]; then
    found=$(find "$sdk/cmdline-tools" -type f -name "$name" 2>/dev/null | head -1)
  fi
  [ -n "$found" ] && { echo "$found"; return 0; }
  return 1
}

AAPT2_BIN=$(find_tool aapt2 || true)
APKSIGNER_BIN=$(find_tool apksigner || true)

if [ -z "$APKSIGNER_BIN" ]; then
  echo "错误：找不到 apksigner，无法校验签名。" >&2
  echo "  ANDROID_HOME=${ANDROID_HOME:-<未设置>}" >&2
  echo "  请安装 Android SDK build-tools（CI 里用 android-actions/setup-android）。" >&2
  exit 1
fi

echo "使用 apksigner: $APKSIGNER_BIN"
if [ -n "$AAPT2_BIN" ]; then
  echo "使用 aapt2    : $AAPT2_BIN"
else
  echo "⚠️  找不到 aapt2，将跳过包名 / versionCode 检查"
fi
echo

# ---------- 取信息 ----------
# aapt2 dump badging 首行形如：
#   package: name='com.fct.tiny' versionCode='20260920' versionName='1.1.1' ...
# 注意要用带引号的精确匹配，否则 name= 会先匹配到 platformBuildVersionName。
read_info() {
  local apk="$1"
  local key="$2"
  local pkg="" code="" name="" dig="" dn=""

  if [ -n "$AAPT2_BIN" ]; then
    local badging
    badging=$("$AAPT2_BIN" dump badging "$apk" 2>/dev/null | sed -n 's/^package: //p' | head -1 || true)
    pkg=$(printf '%s' "$badging"  | grep -o "name='[^']*'"        | head -1 | cut -d"'" -f2 || true)
    code=$(printf '%s' "$badging" | grep -o "versionCode='[^']*'" | head -1 | cut -d"'" -f2 || true)
    name=$(printf '%s' "$badging" | grep -o "versionName='[^']*'" | head -1 | cut -d"'" -f2 || true)
  fi

  # apksigner verify --print-certs 输出：
  #   Signer #1 certificate DN: CN=...
  #   Signer #1 certificate SHA-256 digest: abcd...
  #
  # 注意：不要用 2>/dev/null 吞掉 stderr。build-tools 的 apksigner 在遇到
  # minSdk 相关问题时只会往 stderr 报错，吞掉之后表现为"取不到签名"，很难排查。
  local certs rc
  set +e
  certs=$("$APKSIGNER_BIN" verify --print-certs "$apk" 2>&1)
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    echo "警告：apksigner verify 返回 $rc，输出如下：" >&2
    printf '%s\n' "$certs" >&2
  fi

  # 兼容不同的措辞（Signer #1... / Signer #1 certificate ...）
  dn=$(printf '%s' "$certs"  | sed -n 's/^Signer #1 certificate DN: //p'                         | head -1 || true)
  dig=$(printf '%s' "$certs" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p'              | head -1 || true)
  # 兜底：某些版本把 digest 写成小写或带别的前缀
  if [ -z "$dig" ]; then
    dig=$(printf '%s' "$certs" | grep -i 'signer #1.*sha-256 digest:' | head -1 | sed 's/.*digest:[[:space:]]*//' | tr -d '\r' || true)
  fi
  if [ -z "$dn" ]; then
    dn=$(printf '%s' "$certs" | grep -i 'signer #1.*certificate DN:' | head -1 | sed 's/.*DN:[[:space:]]*//' | tr -d '\r' || true)
  fi

  eval "${key}_PKG=\$pkg"
  eval "${key}_CODE=\$code"
  eval "${key}_NAME=\$name"
  eval "${key}_DIGEST=\$dig"
  eval "${key}_DN=\$dn"
}

NEW_PKG="" ; NEW_CODE="" ; NEW_NAME="" ; NEW_DIGEST="" ; NEW_DN=""
read_info "$1" NEW

echo "================ APK 信息 ================"
printf '文件        : %s\n' "$1"
printf '包名        : %s\n' "${NEW_PKG:-未知}"
printf 'versionCode : %s\n' "${NEW_CODE:-未知}"
printf 'versionName : %s\n' "${NEW_NAME:-未知}"
printf '签名SHA256  : %s\n' "${NEW_DIGEST:-（取不到）}"
printf '签名DN      : %s\n' "${NEW_DN:-（取不到）}"

if [ -z "$NEW_DIGEST" ]; then
  echo
  echo "错误：无法读取 APK 签名信息，校验未通过。" >&2
  exit 1
fi

if printf '%s' "$NEW_DN" | grep -qi 'CN=Android Debug'; then
  echo
  echo "⚠️  这是 debug 签名。debug 签名的包【无法】覆盖安装正式签名的包，"
  echo "    不同机器产生的 debug 签名之间也互不兼容。请配置发布签名。"
  echo "signed=false" >> "${GITHUB_OUTPUT:-/dev/null}"
else
  echo "signed=true" >> "${GITHUB_OUTPUT:-/dev/null}"
fi

if [ $# -lt 2 ] || [ -z "${2:-}" ]; then
  echo "=========================================="
  exit 0
fi

OLD_PKG="" ; OLD_CODE="" ; OLD_NAME="" ; OLD_DIGEST="" ; OLD_DN=""
read_info "$2" OLD

echo
echo "================ 覆盖安装判定 ================"
printf '旧包          : %s\n' "$2"
printf '旧包包名      : %s\n' "${OLD_PKG:-未知}"
printf '旧versionCode : %s\n' "${OLD_CODE:-未知}"
printf '旧包签名SHA256: %s\n' "${OLD_DIGEST:-（取不到）}"
echo

FAIL=0
if [ -z "$OLD_DIGEST" ]; then
  echo "⚠️  旧包签名读取失败，跳过签名一致性比较"
elif [ "$NEW_DIGEST" != "$OLD_DIGEST" ]; then
  echo "❌ 签名不一致 —— 无法覆盖安装！"
  echo "   新包：$NEW_DIGEST"
  echo "   旧包：$OLD_DIGEST"
  echo "   必须使用同一个 keystore 签名，否则用户只能卸载后重装（会丢容器数据）。"
  FAIL=1
else
  echo "✅ 签名一致：$NEW_DIGEST"
fi

if [ -n "$NEW_PKG" ] && [ -n "$OLD_PKG" ]; then
  if [ "$NEW_PKG" = "$OLD_PKG" ]; then
    echo "✅ 包名一致：$NEW_PKG"
  else
    echo "❌ 包名不同：$NEW_PKG vs $OLD_PKG —— 会被装成两个 App"
    FAIL=1
  fi
fi

if [ -n "$NEW_CODE" ] && [ -n "$OLD_CODE" ]; then
  if [ "$NEW_CODE" -gt "$OLD_CODE" ] 2>/dev/null; then
    echo "✅ versionCode 递增：$OLD_CODE → $NEW_CODE"
  elif [ "$NEW_CODE" -eq "$OLD_CODE" ] 2>/dev/null; then
    echo "⚠️  versionCode 相同（$NEW_CODE）：可以覆盖安装，但部分安装器会拒绝，建议递增"
  else
    echo "❌ versionCode 回退：$OLD_CODE → $NEW_CODE —— 系统会判定为降级安装并拒绝"
    FAIL=1
  fi
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "结论：✅ 可以直接覆盖安装，无需卸载。"
else
  echo "结论：❌ 不能直接覆盖安装。"
  exit 1
fi
