#!/usr/bin/env bash
# 为 CI 准备构建输入：jniLibs、patch.tar.gz、rootfs 分片（assets/xa*）
#
# 两条路线：
#   A. 仓库里已经有 assets/xa*（你自己提交过分片）→ 直接校验，不下载
#   B. 没有 → 从上游 Release 下载 debian-<桌面>.tar.xz，按 98MB 分割成 xa*
#      （这一步和 build.ps1 的切分逻辑保持一致，并生成 assets/xa.sha256）
#
# 上游 release 的直链可用 GITHUB_TOKEN 访问；同时保留 gh 命令作为回退。

set -euo pipefail

DESKTOP="${DESKTOP:-xfce}"
UPSTREAM_TAG="${UPSTREAM_TAG:-v1.1.0}"
UPSTREAM_REPO="${UPSTREAM_REPO:-Cateners/tiny_container}"
BASE_URL="https://github.com/${UPSTREAM_REPO}/releases/download/${UPSTREAM_TAG}"
PART_SIZE=$((98 * 1024 * 1024))       # 与 build.ps1 的 98MB 对齐

JNI_DIR="android/app/src/main/jniLibs/arm64-v8a"
ASSETS_DIR="assets"
DOWNLOADS="${RUNNER_TEMP:-/tmp}/tc-inputs"

log() { printf '\n==> %s\n' "$*"; }

# ---------- 工具函数 ----------
# 分片计数与列举统一走这两个函数，避免各处 glob 写法不一致。
# 注意：必须用 find -regex 而不是 shell 的 xa[a-z]，
# 因为 shell glob 未展开时会原样传参（历史上这里踩过坑）。
shard_list() {
  find "$ASSETS_DIR" -maxdepth 1 -type f -regextype posix-extended \
       -regex '.*/xa[a-z]$' -printf '%f\n' 2>/dev/null | sort
}
shard_count() { shard_list | wc -l | tr -d ' '; }

split_rootfs() {
  local src="$1"
  log "分割 $(basename "$src") -> ${ASSETS_DIR}/xa*（每片 98MB）"

  # 清理旧分片：逐个删除，不要写 'xa[a-z]' 这种可能不被展开的字面量
  local old
  while IFS= read -r old; do
    [ -n "$old" ] && rm -f "$ASSETS_DIR/$old"
  done < <(find "$ASSETS_DIR" -maxdepth 1 -type f \( -name 'xa*' \) -printf '%f\n' 2>/dev/null)
  rm -f "$ASSETS_DIR/xa.sha256"

  # ⚠️ split 的前缀只能写到 "x"。
  # GNU split 会自己在前缀后面补两位后缀 aa, ab, ... az, ba, ...
  #   前缀 assets/x   -> xaa, xab, ... xaz   ✅ App 端就是这个命名
  #   前缀 assets/xa  -> xaaa, xaab, ...      ❌ 多了一个 a（CI 上就是这么挂的）
  split -b "${PART_SIZE}" "$src" "${ASSETS_DIR}/x"

  local n
  n=$(shard_count)
  if [ "$n" -eq 0 ]; then
    echo "错误：split 没有产出任何分片，输出目录内容：" >&2
    ls -la "$ASSETS_DIR" >&2
    exit 1
  fi
  if [ "$n" -gt 26 ]; then
    echo "错误：分片数 $n 超过 26，命名会越过 xaa..xaz，" >&2
    echo "      App 端 lib/workflow.dart 用的是 'cat xa*' 按字典序拼接，必须同步改。" >&2
    exit 1
  fi
  log "共 $n 个分片: $(shard_list | tr '\n' ' ')"
}

gen_manifest() {
  log "生成分片校验清单 assets/xa.sha256"
  local list
  list=$(cd "$ASSETS_DIR" && shard_list)
  if [ -z "$list" ]; then
    echo "错误：没有可校验的分片，无法生成清单" >&2
    exit 1
  fi
  ( cd "$ASSETS_DIR" && sha256sum $list > xa.sha256 )
  local lines
  lines=$(wc -l < "$ASSETS_DIR/xa.sha256" | tr -d ' ')
  log "清单条目数：$lines"
  if [ "$lines" -ne "$(shard_count)" ]; then
    echo "错误：清单条目数 $lines 与分片数 $(shard_count) 不一致" >&2
    exit 1
  fi
}

# ---------- 1. rootfs 分片 ----------
mkdir -p "$ASSETS_DIR"
COUNT=$(shard_count)
if [ "$COUNT" -ge 2 ]; then
  log "仓库内已有 $COUNT 个 rootfs 分片，跳过下载"
  if [ ! -f "$ASSETS_DIR/xa.sha256" ]; then
    gen_manifest
  else
    log "校验已有分片"
    ( cd "$ASSETS_DIR" && sha256sum -c xa.sha256 )
  fi
else
  echo "仓库内没有 rootfs 分片（找到 $COUNT 个），开始从上游下载"
  mkdir -p "$DOWNLOADS" "$ASSETS_DIR"
  SRC="$DOWNLOADS/debian-${DESKTOP}.tar.xz"
  URL="${BASE_URL}/debian-${DESKTOP}.tar.xz"

  log "下载 $URL"
  ok=0
  for attempt in 1 2 3; do
    if curl -fL --retry 3 --retry-delay 5 -C - -o "$SRC" "$URL"; then ok=1; break; fi
    echo "第 $attempt 次下载失败，重试…"
    sleep 5
  done
  if [ "$ok" -ne 1 ] && command -v gh >/dev/null 2>&1; then
    log "curl 失败，改用 gh release download"
    gh release download "$UPSTREAM_TAG" -R "$UPSTREAM_REPO" -p "debian-${DESKTOP}.tar.xz" -D "$DOWNLOADS" && ok=1
  fi
  [ "$ok" -eq 1 ] || { echo "错误：rootfs 下载失败" >&2; exit 1; }

  ls -lh "$SRC"
  split_rootfs "$SRC"
  gen_manifest
fi

# ---------- 2. jniLibs ----------
if [ -d "$JNI_DIR" ] && [ "$(ls -A "$JNI_DIR" 2>/dev/null | wc -l)" -gt 0 ]; then
  log "仓库内已有 jniLibs（$(ls -A "$JNI_DIR" | wc -l) 个文件），跳过下载"
else
  log "下载 jniLibs.zip"
  mkdir -p "$DOWNLOADS"
  ZIP="$DOWNLOADS/jniLibs.zip"
  URL="${BASE_URL}/jniLibs.zip"
  ok=0
  for attempt in 1 2 3; do
    if curl -fL --retry 3 --retry-delay 5 -C - -o "$ZIP" "$URL"; then ok=1; break; fi
    echo "第 $attempt 次下载失败，重试…"
    sleep 5
  done
  if [ "$ok" -ne 1 ] && command -v gh >/dev/null 2>&1; then
    gh release download "$UPSTREAM_TAG" -R "$UPSTREAM_REPO" -p 'jniLibs.zip' -D "$DOWNLOADS" && ok=1
  fi
  [ "$ok" -eq 1 ] || { echo "错误：jniLibs 下载失败" >&2; exit 1; }

  mkdir -p "$JNI_DIR"
  unzip -o -q "$ZIP" -d "$JNI_DIR"
  # 上游 zip 里可能直接是 .so，也可能带一层目录，这里统一摊平到 jniLibs/arm64-v8a
  find "$JNI_DIR" -mindepth 2 -type f -name '*.so' -exec mv -f {} "$JNI_DIR"/ \;
  find "$JNI_DIR" -mindepth 1 -type d -exec rm -rf {} + 
  echo "jniLibs 文件数：$(ls -A "$JNI_DIR" | wc -l)"
  ls -A "$JNI_DIR" | head -20
fi

# ---------- 3. patch.tar.gz ----------
if [ -f "$ASSETS_DIR/patch.tar.gz" ]; then
  log "仓库内已有 assets/patch.tar.gz（$(du -h "$ASSETS_DIR/patch.tar.gz" | cut -f1)），跳过下载"
else
  log "下载 patch.tar.gz"
  mkdir -p "$DOWNLOADS"
  ok=0
  for attempt in 1 2 3; do
    if curl -fL --retry 3 --retry-delay 5 -C - -o "$ASSETS_DIR/patch.tar.gz" \
         "${BASE_URL}/patch.tar.gz"; then ok=1; break; fi
    echo "第 $attempt 次下载失败，重试…"
    sleep 5
  done
  if [ "$ok" -ne 1 ] && command -v gh >/dev/null 2>&1; then
    gh release download "$UPSTREAM_TAG" -R "$UPSTREAM_REPO" -p 'patch.tar.gz' -D "$ASSETS_DIR" && ok=1
  fi
  [ "$ok" -eq 1 ] || { echo "错误：patch.tar.gz 下载失败" >&2; exit 1; }
  ls -lh "$ASSETS_DIR/patch.tar.gz"
fi

# ---------- 4. 汇总 ----------
log "构建输入清单"
printf '  %-46s %s\n' "jniLibs:        $(ls -A "$JNI_DIR" | wc -l) 个文件" ""
printf '  %-46s %s\n' "patch.tar.gz:   $(du -h "$ASSETS_DIR/patch.tar.gz" | cut -f1)" ""
printf '  %-46s %s\n' "rootfs 分片:    $(ls -A "$ASSETS_DIR" | grep -cE '^xa[a-z]+$') 个" ""
du -sh "$ASSETS_DIR"
df -h / | tail -1
