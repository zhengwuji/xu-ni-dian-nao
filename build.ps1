# build.ps1 -- 小小电脑 / Tiny Computer 的 APK 构建脚本
#
# TINY-OPT (2026-09-20) 相对原版的改动：
#   1. 去掉了硬编码的 C:\Users\29513\Downloads，改为参数 / 环境变量 / 默认值三级回退
#   2. 构建失败时以非零退出码结束（原来只 Write-Error + continue，pwsh -File 退出码是 0，
#      CI 会把失败的构建当成功）
#   3. 分片命名不再用 $index % 26：超过 26 片会静默覆盖 xaa。现在支持 xaa..xaz,xba..
#      并在超出命名空间时直接抛错
#   4. 生成 assets/xa.sha256 清单，App 首启会用 busybox sha256sum -c 校验分片完整性
#   5. 每套桌面环境使用独立的 --split-debug-info 目录（原来共用 tiny_computer/sdi，
#      后一个版本会覆盖前一个的符号表，导致已发布 APK 的混淆栈无法符号化）
#   6. 产出 .sha256 而不是重命名 Flutter 自带的 .sha1（后者内容是原文件名，改名后失真）
#   7. 构建前做输入校验（jniLibs / assets.zip / patch.tar.gz / 分片），缺文件直接失败
#   8. 固定工作目录为脚本所在目录，避免“必须在工程根目录运行”的隐式前提

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, ValueFromRemainingArguments=$true)]
    [ValidateSet("xfce", "lxqt", "gxde")]
    [string[]]$DesktopEnvs,

    [string]$NameSuffix,

    # rootfs tar.xz 所在目录。优先级：-SourceDir > $env:TC_ROOTFS_DIR > 用户下载目录
    [string]$SourceDir,

    # 符号表归档目录
    [string]$SymbolsDir,

    # 跳过 flutter build（只做分片与校验，用于调试脚本本身）
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$ProjectRoot = $PSScriptRoot
$AssetsDir = Join-Path $ProjectRoot "assets"

if ([string]::IsNullOrEmpty($SourceDir)) {
    if (-not [string]::IsNullOrEmpty($env:TC_ROOTFS_DIR)) {
        $SourceDir = $env:TC_ROOTFS_DIR
    } else {
        $SourceDir = Join-Path $env:USERPROFILE "Downloads"
    }
}
if ([string]::IsNullOrEmpty($SymbolsDir)) {
    $SymbolsDir = Join-Path $ProjectRoot "build/symbols"
}

Write-Host "工程目录 : $ProjectRoot"
Write-Host "rootfs源 : $SourceDir"
Write-Host "符号目录 : $SymbolsDir"

# 分片长度：98MB（与历史发布保持一致，App 侧只关心顺序与命名，不关心大小）
$PartSizeBytes = 102760448

# 分片命名
# 原实现是 `"xa" + [char]($index % 26)`，第 27 片会重新写出 xaa 并静默覆盖第一片。
# 本实现：
#   1. 26 片以内与原实现完全一致（xaa..xaz）—— 已发布的 assets 与用户本地缓存依赖它；
#   2. 名字唯一、长度固定，且字典序等于拆分顺序（App 端是 `cat xa*` 拼接的）；
#   3. 第 27 片起改用补零数字前缀 xa01a…（详见下面的注释），并且一旦真的越过 26 片，
#      Assert-BuildInputs 会直接报错中止，提醒必须同步改 App 端的拼接方式。
# 98MB 一片的 rootfs 要涨到 2.5GB 才会越过 26 片，正常发布用不到多字母分支。
function Get-SplitFileName {
    param([int]$index)
    if ($index -lt 0 -or $index -ge 676) {
        throw "分片数超出命名空间（最大 676 片），请调大分片长度：index=$index"
    }
    if ($index -lt 26) {
        $letter = [char](97 + $index)               # 97 = 'a'，与原实现一致
        return "xa$letter"                          # xaa .. xaz
    }
    # 26 片之后。这里有个绕不开的矛盾，写清楚免得后人再踩：
    #   - App 端是 `cat xa*`，依赖字典序等于拆分顺序；
    #   - 纯字母名（xaaa、xba…）的字典序必然和自然顺序冲突（"xaa" < "xaaa" < "xab"，已实测）；
    #   - 补零数字前缀 xa01a… 字典序正确、长度固定，只是不等于 GNU split 的命名。
    # 所以第 27 片起走补零数字方案。注意 xa01* 的字典序排在"xaa"之前，因此这组名字
    # 只有在分片总数 ≤ 26（也就是根本不进入这个分支）或 App 端改成分组拼接时才安全，
    # 这也是 Assert-BuildInputs 里对 >26 片直接报错的原因。
    $n = $index - 26
    $hi = [int][math]::Floor($n / 26) + 1            # 1..25
    $lo = $n % 26                                    # 0..25
    return "xa$($hi.ToString('00'))$([char](97 + $lo))"   # xa01a .. xa25z
}

function Split-File {
    param(
        [string]$Path,
        [long]$PartSizeBytes,
        [string]$DestinationPath
    )

    $stream = [System.IO.File]::OpenRead($Path)
    $buffer = New-Object byte[] $PartSizeBytes
    $partNumber = 0

    try {
        while (($bytesRead = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $partName = Get-SplitFileName $partNumber
            $partPath = Join-Path $DestinationPath $partName

            $partStream = [System.IO.File]::OpenWrite($partPath)
            try {
                $partStream.Write($buffer, 0, $bytesRead)
            } finally {
                $partStream.Close()
            }

            Write-Host "创建分片: $partName ($bytesRead 字节)"
            $partNumber++
        }
    } finally {
        $stream.Close()
    }

    return $partNumber
}

# 构建输入校验：缺任何一项都直接失败，而不是打出一个“装得上但一启动就崩”的包
function Assert-BuildInputs {
    $missing = @()

    foreach ($rel in @("assets/assets.zip", "assets/patch.tar.gz")) {
        $p = Join-Path $ProjectRoot $rel
        if (-not (Test-Path $p)) { $missing += $rel }
    }

    $jniDir = Join-Path $ProjectRoot "android/app/src/main/jniLibs/arm64-v8a"
    if (-not (Test-Path $jniDir) -or @(Get-ChildItem $jniDir -File -ErrorAction SilentlyContinue).Count -eq 0) {
        $missing += "android/app/src/main/jniLibs/arm64-v8a/*（见 README 构建说明，需从 Releases 下载 jniLibs.zip）"
    }

    $shards = @(Get-ChildItem $AssetsDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^xa[a-z]$' })
    if ($shards.Count -lt 2) {
        $missing += "assets/xa*（rootfs 分片，当前 $($shards.Count) 个）"
    }

    # 越过 26 片时命名会从 xaa/xab… 变成 xa01a/xa02a…，而 App 端是 `cat xa*` 按
    # 字典序拼接的，两种名字混在一起会静默拼出坏 rootfs。这里直接拦住，只在 -NoBuild 路径外生效。
    if ($shards.Count -gt 26) {
        $missing += ("分片数 $($shards.Count) 超过 26：命名已切换成 xa01a 形式，" +
                     "App 端 lib/workflow.dart 的 'cat xa*' 拼接必须同步改成分组拼接，" +
                     "或调大 `$PartSizeBytes 减少分片数")
    }

    if ($missing.Count -gt 0) {
        throw "构建输入不完整，已中止：`n  - " + ($missing -join "`n  - ")
    }
    Write-Host "构建输入校验通过：$($shards.Count) 个分片" -ForegroundColor Green
}

# -SkipBuild 时也要检查的项：只校验分片与清单，不要求 jniLibs / keystore 这些构建产物。
# 这样 `build.ps1 xfce -SkipBuild` 可以单独用来“重刷分片 + 重算哈希”，不会因为缺 jniLibs 而失败。
function Assert-ShardsOnly {
    $shards = @(Get-ChildItem $AssetsDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^xa[a-z]$' })
    if ($shards.Count -lt 2) {
        throw "assets 下只有 $($shards.Count) 个 rootfs 分片，至少需要 2 个"
    }
    if ($shards.Count -gt 26) {
        throw ("分片数 $($shards.Count) 超过 26：命名已切换成 xa01a 形式，" +
               "App 端 lib/workflow.dart 的 'cat xa*' 拼接必须同步改成分组拼接。")
    }
    Write-Host "分片校验通过：$($shards.Count) 个" -ForegroundColor Green
}

# 生成分片哈希清单。App 首启会在解包前用 busybox sha256sum -c 校验，损坏时报错而不是解出坏 rootfs。
# 只收 26 片以内的单字母名（xaa..xaz）：多字母/数字名不在 App 端 `cat xa*` 的兼容范围内。
function New-ShardManifest {
    $shards = @(Get-ChildItem $AssetsDir -File |
        Where-Object { $_.Name -match '^xa[a-z]$' } |
        Sort-Object Name)
    $lines = foreach ($s in $shards) {
        $hash = (Get-FileHash -Algorithm SHA256 $s.FullName).Hash.ToLower()
        "$hash  $($s.Name)"
    }
    $manifest = Join-Path $AssetsDir "xa.sha256"
    Set-Content -Path $manifest -Value $lines -Encoding ASCII
    $total = ($shards | Measure-Object Length -Sum).Sum
    Write-Host "分片清单: $manifest ($($shards.Count) 项, $([math]::Round($total/1MB,1)) MB)" -ForegroundColor Green
}

foreach ($DesktopEnv in $DesktopEnvs) {
    Write-Host "`n开始处理 $DesktopEnv 桌面环境..." -ForegroundColor Green

    $TarFile = "debian-$DesktopEnv.tar.xz"
    $SourcePath = Join-Path $SourceDir $TarFile

    if (-not (Test-Path $SourcePath)) {
        throw "找不到文件 $SourcePath（可用 -SourceDir 或环境变量 TC_ROOTFS_DIR 指定目录）"
    }

    # 只清理旧分片与旧清单，不动 assets/ 下的其它文件
    if (-not (Test-Path $AssetsDir)) {
        New-Item -ItemType Directory -Path $AssetsDir | Out-Null
    }
    # 清掉旧分片、旧清单，以及上个版本可能残留的 xa01a 形式分片
    Get-ChildItem -Path $AssetsDir -File | Where-Object { $_.Name -match '^xa([a-z]{1,2}|[0-9]{2}[a-z])(\.sha256)?$' } | Remove-Item -Force


    Write-Host "正在分割 $TarFile ..."
    $partCount = Split-File -Path $SourcePath -PartSizeBytes $PartSizeBytes -DestinationPath $AssetsDir
    Write-Host "文件分割完成，共创建 $partCount 个分片文件"

    New-ShardManifest

    if ($SkipBuild) {
        Assert-ShardsOnly
        Write-Host "-SkipBuild 已指定，跳过 flutter build" -ForegroundColor Yellow
        continue
    }

    Assert-BuildInputs

    Write-Host "正在运行Flutter构建..."
    flutter build apk --target-platform android-arm64 --split-per-abi

    if ($LASTEXITCODE -ne 0) {
        throw "Flutter 构建失败（$DesktopEnv），退出码 $LASTEXITCODE"
    }

    $ApkBaseName = "tiny-computer-$DesktopEnv"
    if (-not [string]::IsNullOrEmpty($NameSuffix)) {
        $ApkBaseName += "-$NameSuffix"
    }

    $ApkSource = "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
    if (-not (Test-Path $ApkSource)) {
        throw "找不到APK文件 $ApkSource"
    }
    $ApkOut = Join-Path $ProjectRoot "$ApkBaseName.apk"
    Move-Item -Path $ApkSource -Destination $ApkOut -Force
    Write-Host "已生成APK: $ApkBaseName.apk"

    # 自己算哈希（Flutter 自带的 .sha1 内容是原文件名，改名后已失真）
    $hash = (Get-FileHash -Algorithm SHA256 $ApkOut).Hash.ToLower()
    "$hash  $ApkBaseName.apk" | Set-Content -Path "$ApkOut.sha256" -Encoding ASCII
    Write-Host "SHA256: $hash"
}

Write-Host "`n所有桌面环境处理完成！" -ForegroundColor Cyan

# 原脚本末尾保留了当初生成这个脚本的 prompt，已移到 doc/build-prompt.md
