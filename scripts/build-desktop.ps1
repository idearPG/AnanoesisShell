# =====================================================================
# AnanoesisShell 桌面客户端一键构建（任务 5.1，design D8）
# PowerShell 5.1 兼容：不用 &&、文件带 UTF-8 BOM、逐步检查 $LASTEXITCODE。
#
# 链路：vite build → mvnw package → Temurin JRE 17 下载缓存 →
#       三物暂存 desktop/build/ → electron-builder --win nsis →
#       产物落 frontend/desktop/dist-release/AnanoesisShell-Setup-*.exe
#
# 签名钩子（design D11）：仅当 ANANOESIS_CERT_FILE + ANANOESIS_CERT_PASSWORD
# 环境变量存在时启用 Authenticode；否则显式打印「未签名」，绝不伪称。
#
# 开关：-SkipFrontend -SkipBackend -SkipJre -SkipBuilder（分段调试用）
#       -SkipWipe：跳过打包前清库（日常调试用；发布构建不得跳过）
#       -OutDir：electron-builder 输出目录。默认落在同 drive 的工作区外
#       ——IDE 文件监视器会对新造的 win-unpacked.tmp 持有无 FILE_SHARE_DELETE
#       的目录句柄，令 tmp→win-unpacked 的 rename 持续 EPERM（5.1 实证）；
#       产物 exe 以文件级拷回 desktop/dist-release，路径契约不变。
# =====================================================================
param(
  [switch]$SkipFrontend,
  [switch]$SkipBackend,
  [switch]$SkipJre,
  [switch]$SkipBuilder,
  [switch]$SkipWipe,
  [string]$OutDir
)
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot          # scripts/ 的主仓库根
$frontend = Join-Path $root 'frontend'
$backend = Join-Path $root 'backend'
$desktop = Join-Path $frontend 'desktop'
$staging = Join-Path $desktop 'build'
$jreCacheDir = Join-Path $root '.cache\temurin-jre17'
$jreVersion = '17'                                 # Temurin LTS 17，与后端编译基线同代

function Step([string]$msg) { Write-Output "==> $msg" }
function Die([string]$msg) { Write-Output "!! $msg"; exit 1 }

# ---------------------------------------------------------------------
# 0. 打包前清库（用户裁定：交付物首启必须是零配置零主机的空库）
#
# 实证澄清（.tmp-probe/inspect-pkg-db.ps1）：安装包内从不携带数据库——
# 数据在用户级目录 ~/.ananoesis/data.db，开发与已装壳共用同一份，
# “装后见既往数据”源于此而非打包泄漏。清库保证的是**本机验证安装时**
# 的干净首启；最终用户机器首启由 Flyway 自动建空库（schema 迁移不受影响）。
# 文件被运行中的后端锁住时绝不静默跳过：那会静默交付“脏验证”结果。
# ---------------------------------------------------------------------
if (-not $SkipWipe) {
  Step '打包前清空用户数据目录（~/.ananoesis/data.db*）'
  $dataDir = Join-Path $env:USERPROFILE '.ananoesis'
  $dbFiles = @(Get-ChildItem $dataDir -File -Filter 'data.db*' -ErrorAction SilentlyContinue)
  foreach ($f in $dbFiles) {
    try {
      Remove-Item $f.FullName -Force -ErrorAction Stop
    } catch {
      Die "清库失败： $($f.FullName) 被占用（开发后端还在运行？）。停掉后端重试，或调试构建传 -SkipWipe"
    }
  }
  Step ("已清除 {0} 个数据库文件（Flyway 首启自动重建空库）" -f $dbFiles.Count)
}

# ---------------------------------------------------------------------
# 1. 前端：vite build（desktop CSP meta 由 vite.config.ts 在 build 相位注入）
# ---------------------------------------------------------------------
if (-not $SkipFrontend) {
  Step '前端 vite build'
  Push-Location $frontend
  try {
    & npm.cmd run build
    if ($LASTEXITCODE -ne 0) { Die "vite build 失败（exit=$LASTEXITCODE）" }
  } finally { Pop-Location }
  if (-not (Test-Path (Join-Path $frontend 'dist\index.html'))) { Die 'frontend/dist/index.html 不存在' }
}

# ---------------------------------------------------------------------
# 2. 后端：mvnw package（fat jar；测试由 6.4 验证门禁统一把关）
# ---------------------------------------------------------------------
if (-not $SkipBackend) {
  Step '后端 mvnw package'
  Push-Location $backend
  try {
    & .\mvnw.cmd -B -DskipTests package
    if ($LASTEXITCODE -ne 0) { Die "mvnw package 失败（exit=$LASTEXITCODE）" }
  } finally { Pop-Location }
}
$jar = Get-ChildItem (Join-Path $backend 'target') -Filter 'ananoesis-shell-backend-*.jar' |
  Where-Object { $_.Name -notmatch 'sources|original' } |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $jar) { Die 'backend/target 下找不到 fat jar' }
Step ("后端产物：{0}（{1:N1} MB）" -f $jar.Name, ($jar.Length / 1MB))

# ---------------------------------------------------------------------
# 3. JRE：Temurin 17 win32-x64，下载进主仓库 .cache 复用（zip 顶层是一级目录）
# ---------------------------------------------------------------------
$jreHome = $null
if (-not $SkipJre) {
  Step 'Temurin JRE 17 检查/下载'
  $jreZip = Join-Path $root '.cache\temurin-jre17.zip'
  $url = "https://api.adoptium.net/v3/binary/latest/$jreVersion/ga/windows/x64/jre/hotspot/normal/eclipse?project=jdk"
  if (-not (Test-Path (Join-Path $jreCacheDir 'bin\java.exe'))) {
    New-Item -ItemType Directory -Force -Path (Split-Path $jreZip) | Out-Null
    Step "下载 $url"
    $ProgressPreference = 'SilentlyContinue'      # PS5.1 进度条会拖慢 WebCommand 数倍
    try {
      Invoke-WebRequest -Uri $url -OutFile $jreZip -UseBasicParsing -TimeoutSec 1800
    } catch {
      Die "JRE 下载失败：$($_.Exception.Message)（可手工放置 $jreZip 后重试）"
    }
    Step '解压 JRE（约 40MB zip）'
    $tmpExpand = Join-Path $env:TEMP ("ananoesis-jre-" + [guid]::NewGuid().ToString('N'))
    Expand-Archive -Path $jreZip -DestinationPath $tmpExpand -Force
    $inner = Get-ChildItem $tmpExpand -Directory | Select-Object -First 1
    if (-not $inner -or -not (Test-Path (Join-Path $inner.FullName 'bin\java.exe'))) {
      Remove-Item $tmpExpand -Recurse -Force
      Die '解压后未找到 bin/java.exe，zip 结构异常'
    }
    if (Test-Path $jreCacheDir) { Remove-Item $jreCacheDir -Recurse -Force }
    Move-Item $inner.FullName $jreCacheDir
    Remove-Item $tmpExpand -Recurse -Force -ErrorAction SilentlyContinue
  } else {
    Step "命中缓存：$jreCacheDir"
  }
  $jreHome = $jreCacheDir
}

# ---------------------------------------------------------------------
# 4. 暂存：三物摆进 desktop/build/（electron-builder.yml 的 extraResources 来源）
# ---------------------------------------------------------------------
Step '暂存 runtime / backend/app.jar / dist 到 desktop/build/'
Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $staging | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $staging 'backend') | Out-Null
if ($SkipJre) {
  # 分段调试：build/runtime 已有内容则沿用，否则从缓存拷
  $cacheRuntime = Join-Path $staging 'runtime'
  if (-not (Test-Path (Join-Path $cacheRuntime 'bin\java.exe')) -and (Test-Path (Join-Path $jreCacheDir 'bin\java.exe'))) {
    Copy-Item -Recurse $jreCacheDir $cacheRuntime
  }
} else {
  Copy-Item -Recurse $jreHome (Join-Path $staging 'runtime')
}
if (-not (Test-Path (Join-Path $staging 'runtime\bin\java.exe'))) { Die 'build/runtime/bin/java.exe 缺失（JRE 暂存失败或被跳过）' }
Copy-Item $jar.FullName (Join-Path $staging 'backend\app.jar')
Copy-Item -Recurse (Join-Path $frontend 'dist') (Join-Path $staging 'dist')
if (-not (Test-Path (Join-Path $staging 'dist\index.html'))) { Die 'build/dist/index.html 缺失' }
if (-not (Test-Path (Join-Path $desktop 'out\main.js'))) {
  Step '编译壳主进程（tsc）'
  Push-Location $desktop
  try {
    & npm.cmd run build:main
    if ($LASTEXITCODE -ne 0) { Die "tsc build:main 失败（exit=$LASTEXITCODE）" }
  } finally { Pop-Location }
}

# ---------------------------------------------------------------------
# 5. electron-builder：NSIS 安装包
# ---------------------------------------------------------------------
if (-not $SkipBuilder) {
  Step 'electron-builder --win nsis'
  $signArgs = @()
  $certFile = $env:ANANOESIS_CERT_FILE
  $certPass = $env:ANANOESIS_CERT_PASSWORD
  if ($certFile -and $certPass -and (Test-Path $certFile)) {
    Step "启用 Authenticode 签名：$certFile"
    # electron-builder 经 CLI 覆盖 win.certificateFile/certificatePassword
    $signArgs = @('-c.win.certificateFile="' + $certFile + '"', '-c.win.certificatePassword="' + $certPass + '"')
  } else {
    Write-Output '==> 未配置证书环境变量（ANANOESIS_CERT_FILE/_PASSWORD）：本次构建【未签名】，发布说明必须如实声明（design D11）'
  }
  # 输出目录：工作区外（同 drive），避开 IDE 监视器目录句柄导致的 rename EPERM
  $builderOut = if ($OutDir) { $OutDir } else { (Split-Path -Qualifier $root) + '\.ananoesis-desktop-build\release' }
  New-Item -ItemType Directory -Force -Path $builderOut | Out-Null
  Step "electron-builder 输出→$builderOut（工作区外，规避监视器持柄）"
  Push-Location $desktop
  try {
    & npx.cmd electron-builder --win nsis "-c.directories.output=$builderOut" @signArgs
    if ($LASTEXITCODE -ne 0) { Die "electron-builder 失败（exit=$LASTEXITCODE）" }
  } finally { Pop-Location }
  # 产物文件级拷回 dist-release（文件操作不受目录句柄影响）
  $releaseDir = Join-Path $desktop 'dist-release'
  New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null
  Get-ChildItem $builderOut -File | Copy-Item -Destination $releaseDir -Force
}

# ---------------------------------------------------------------------
# 6. 产物报告（体积记录进 spike-notes 的素材：预计 ~250MB，超 2GB 视为异常）
# ---------------------------------------------------------------------
$setup = Get-ChildItem (Join-Path $desktop 'dist-release') -Filter '*.exe' -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $setup) { Die 'dist-release 下没有 Setup.exe（构建被跳过或失败）' }
$mb = $setup.Length / 1MB
if ($mb -gt 2048) { Die "安装包 ${mb:N1} MB 超过 2GB 异常线" }
Step ("完成：{0}（{1:N1} MB）" -f $setup.FullName, $mb)
