#!/usr/bin/env bash
# build.sh —— Linux/macOS/CI 下的 APK 构建脚本，等价于 build.ps1
#
# 与 build.ps1 保持同一套规则：
#   - rootfs 分片 98MB，命名为 xaa..xaz（超过 26 片直接报错，因为 App 端 `cat xa*` 依赖字典序）
#   - 生成 assets/xa.sha256，App 首启会用它校验分片完整性
#   - 每套桌面环境用独立的 --split-debug-info 目录，避免符号表互相覆盖
#   - 失败以非零退出码结束
#
# 用法：
#   ./build.sh xfce                  # 完整构建
#   ./build.sh xfce lxqt             # 连续构建两个桌面环境
#   DESKTOP=xfce SKIP_BUILD=1 ./build.sh xfce   # 只切分 + 算哈希，不编译
#   SOURCE_DIR=/path/to/rootfs ./build.sh xfce

set -euo pipefail

DESKTOP_ENVS=("$@")
if [ ${#DESKTOP_ENVS[@]} -eq 0 ]; then
  echo "用法: $0 <xfce|lxqt|gxde> [...]" >&2
  exit 2
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

ASSETS_DIR="$PROJECT_ROOT/assets"
SOURCE_DIR="${SOURCE_DIR:-${TC_ROOTFS_DIR:-$HOME/Downloads}}"
SYMBOLS_ROOT="${SYMBOLS_DIR:-$PROJECT_ROOT/build/symbols}"
PART_SIZE=$((98 * 1024 * 1024))
SKIP_BUILD="${SKIP_BUILD:-0}"

log() { printf '\n==> %s\n' "$*"; }

check_inputs() {
  local missing=()
  [ -f "assets/assets.zip" ]    || missing+=("assets/assets.zip")
  [ -f "assets/patch.tar.gz" ]  || missing+=("assets/patch.tar.gz")
  local jni="android/app/src/main/jniLibs/arm64-v8a"
  if [ ! -d "$jni" ] || [ "$(ls -A "$jni" 2>/dev/null | wc -l)" -eq 0 ]; then
    missing+=("android/app/src/main/jniLibs/arm64-v8a/*（需从 Releases 下载 jniLibs.zip）")
  fi
  local shards
  shards=$(ls assets/xa[a-z] 2>/dev/null | wc -l)
  [ "$shards" -ge 2 ] || missing+=("assets/xa*（rootfs 分片，当前 $shards 个）")

  if [ ${#missing[@]} -gt 0 ]; then
    printf '构建输入不完整，已中止：\n' >&2
    printf '  - %s\n' "${missing[@]}" >&2
    exit 1
  fi
  log "构建输入校验通过：$shards 个分片"
}

for DESKTOP in "${DESKTOP_ENVS[@]}"; do
  case "$DESKTOP" in
    xfce|lxqt|gxde) ;;
    *) echo "未知桌面环境：$DESKTOP（可选 xfce/lxqt/gxde）" >&2; exit 2 ;;
  esac

  log "开始处理 $DESKTOP 桌面环境"
  TAR_FILE="debian-$DESKTOP.tar.xz"
  SRC="$SOURCE_DIR/$TAR_FILE"

  mkdir -p "$ASSETS_DIR"
  if [ -f "$SRC" ]; then
    log "分割 $TAR_FILE -> assets/xa*（每片 98MB）"
    rm -f "$ASSETS_DIR"/xa[a-z] "$ASSETS_DIR"/xa.sha256
    split -b "$PART_SIZE" "$SRC" "$ASSETS_DIR/xa"
    PART_COUNT=$(ls "$ASSETS_DIR"/xa[a-z] | wc -l)
    log "共 $PART_COUNT 个分片"
    if [ "$PART_COUNT" -gt 26 ]; then
      echo "错误：分片数超过 26，命名会越过 xaa..xaz；App 端 lib/workflow.dart 的 'cat xa*'" >&2
      echo "      拼接依赖字典序，必须同步改成显式列表拼接，或调大分片长度。" >&2
      exit 1
    fi
    log "生成 assets/xa.sha256"
    ( cd "$ASSETS_DIR" && sha256sum $(ls xa[a-z] | sort) > xa.sha256 )
  else
    log "找不到 $SRC，跳过切分（沿用 assets/ 下已有的分片）"
    [ -f "$ASSETS_DIR/xa.sha256" ] || { ( cd "$ASSETS_DIR" && sha256sum $(ls xa[a-z] | sort) > xa.sha256 ); }
  fi

  if [ "$SKIP_BUILD" = "1" ]; then
    log "SKIP_BUILD=1，跳过编译"
    continue
  fi

  check_inputs

  SDI="$SYMBOLS_ROOT/$DESKTOP"
  mkdir -p "$SDI"
  log "flutter build apk（符号表 -> $SDI）"
  flutter build apk \
    --target-platform android-arm64 \
    --split-per-abi \
    --obfuscate \
    --split-debug-info="$SDI"

  APK_SRC="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
  [ -f "$APK_SRC" ] || { echo "错误：找不到 APK $APK_SRC" >&2; exit 1; }

  APK_OUT="$PROJECT_ROOT/tiny-computer-$DESKTOP.apk"
  mv -f "$APK_SRC" "$APK_OUT"
  ( cd "$PROJECT_ROOT" && sha256sum "$(basename "$APK_OUT")" > "$(basename "$APK_OUT").sha256" )
  log "已生成 $APK_OUT"
  cat "$APK_OUT.sha256"
done

log "全部完成"
