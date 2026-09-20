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
# 需要 build-tools 里的 aapt2 / apksigner。CI 上由 Android SDK 提供。

set -euo pipefail

AAPT2="${AAPT2:-aapt2}"
APKSIGNER="${APKSIGNER:-apksigner}"

pick_tool() {
  # 优先用 PATH，其次在 Android SDK 里找最新版本
  command -v "$1" >/dev/null 2>&1 && { command -v "$1"; return; }
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
  local found
  found=$(find "$sdk/build-tools" -maxdepth 2 -type f -name "$1" 2>/dev/null | sort -V | tail -1)
  [ -n "$found" ] && { echo "$found"; return; }
  echo ""
}

AAPT2_BIN=$(pick_tool aapt2)
APKSIGNER_BIN=$(pick_tool apksigner)

if [ -z "$APKSIGNER_BIN" ]; then
  echo "警告：找不到 apksigner，跳过签名校验（CI 上应安装 Android SDK build-tools）" >&2
  exit 0
fi

get_info() {
  local apk="$1"
  local pkg="" code="" name=""

  if [ -n "$AAPT2_BIN" ]; then
    # aapt2 dump badging 的输出形如：
    #   package: name='com.fct.tiny' versionCode='20260205' versionName='1.1.0'
    local badging
    badging=$("$AAPT2_BIN" dump badging "$apk" 2>/dev/null | head -1 || true)
    pkg=$(printf '%s' "$badging"  | sed -n "s/.*name='\([^']*\)'.*/\1/p")
    code=$(printf '%s' "$badging" | sed -n "s/.*versionCode='\([^']*\)'.*/\1/p")
    name=$(printf '%s' "$badging" | sed -n "s/.*versionName='\([^']*\)'.*/\1/p")
  fi

  # apksigner 输出里的 “Signer #1 certificate SHA-256 digest:”
  local digest
  digest=$("$APKSIGNER_BIN" verify --print-certs "$apk" 2>/dev/null \
            | sed -n 's/.*Signer #1 certificate SHA-256 digest: //p' | head -1 || true)

  # 是否 debug 证书（Android debug key 的 DN 固定）
  local dn
  dn=$("$APKSIGNER_BIN" verify --print-certs "$apk" 2>/dev/null \
        | sed -n 's/.*Signer #1 certificate DN: //p' | head -1 || true)

  echo "$pkg|$code|$name|$digest|$dn"
}

IFS='|' read -r P1 C1 N1 D1 DN1 <<< "$(get_info "$1")"
APK1="$1"

echo "================ APK 信息 ================"
printf '文件      : %s\n' "$APK1"
printf '包名      : %s\n' "${P1:-未知}"
printf 'versionCode: %s\n' "${C1:-未知}"
printf 'versionName: %s\n' "${N1:-未知}"
printf '签名SHA256 : %s\n' "${D1:-未签名}"
printf '签名DN     : %s\n' "${DN1:-未知}"

if printf '%s' "$DN1" | grep -qi 'CN=Android Debug'; then
  echo
  echo "⚠️  这是 debug 签名。debug 签名的包【无法】覆盖安装正式签名的包，"
  echo "    每个 debug 版本之间也会因密钥不同而互相冲突，请配置发布签名。"
  echo "signed=false" >> "${GITHUB_OUTPUT:-/dev/null}"
else
  echo "signed=true" >> "${GITHUB_OUTPUT:-/dev/null}"
fi

if [ $# -lt 2 ]; then
  echo "=========================================="
  exit 0
fi

IFS='|' read -r P2 C2 N2 D2 DN2 <<< "$(get_info "$2")"
APK2="$2"

echo
echo "================ 覆盖安装判定 ================"
printf '旧包      : %s (%s / %s)\n' "$APK2" "${P2:-?}" "${C2:-?}"
echo

FAIL=0
if [ "$P1" != "$P2" ]; then
  echo "❌ 包名不同：$P1 vs $P2 —— 无法覆盖安装（会被装成两个 App）"
  FAIL=1
else
  echo "✅ 包名一致：$P1"
fi

if [ -z "$D1" ] || [ -z "$D2" ]; then
  echo "⚠️  签名信息不完整，无法判定签名一致性"
  FAIL=1
elif [ "$D1" != "$D2" ]; then
  echo "❌ 签名不一致 —— 无法覆盖安装！"
  echo "   新包：$D1"
  echo "   旧包：$D2"
  echo "   说明：必须用同一个 keystore 签名，否则用户只能卸载后重装（会丢容器数据）。"
  FAIL=1
else
  echo "✅ 签名一致：$D1（可覆盖安装）"
fi

# versionCode 必须递增，否则部分 ROM / 安装器会拒绝
if [ -n "$C1" ] && [ -n "$C2" ]; then
  if [ "$C1" -gt "$C2" ] 2>/dev/null; then
    echo "✅ versionCode 递增：$C2 → $C1"
  elif [ "$C1" -eq "$C2" ] 2>/dev/null; then
    echo "⚠️  versionCode 相同（$C1）：可以覆盖安装，但部分应用商店/安装器会拒绝，建议递增"
  else
    echo "❌ versionCode 回退：$C2 → $C1 —— 系统会判定为降级安装并拒绝"
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
