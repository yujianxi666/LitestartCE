# 打包 LitestartCE 为 Chromium(.zip) 与 Firefox(.xpi) 可安装包
# 用法: pwsh -File tools\build-packages.ps1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$outDir = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# ---- 运行期文件清单（白名单，避免把 docs/截图/临时文件打进去）----
$runtimeFiles = @(
  'manifest.json'
  'index.html'
  'script.js'
  'LICENSE'
  'PRIVACY_POLICY.md'
  'img/background.webp'
  'img/icon.png'
  'img/icon_d.png'
  'img/icon_l.png'
  'img/logo/baidu_logo_dark.png'
  'img/logo/baidu_logo_light.png'
  'img/logo/google_logo_dark.png'
  'img/logo/google_logo_light.png'
  '_locales/en/messages.json'
  '_locales/ja/messages.json'
  '_locales/ru/messages.json'
  '_locales/zh_CN/messages.json'
  '_locales/zh_TW/messages.json'
)

# ---- 1. 清单自检：文件是否齐全 ----
$missing = $runtimeFiles | Where-Object { -not (Test-Path (Join-Path $root $_)) }
if ($missing) { throw "缺少运行期文件: $($missing -join ', ')" }
Write-Host "[1/5] 运行期文件齐全 ($($runtimeFiles.Count) 个)"

# ---- 2. 引用自检：manifest / 页面里点名的资源是否都在清单内 ----
$manifest = Get-Content (Join-Path $root 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$referenced = @()
$referenced += $manifest.chrome_url_overrides.newtab
$referenced += $manifest.icons.PSObject.Properties.Value
foreach ($p in $manifest.web_accessible_resources) { $referenced += $p.resources }
# 本地图片引用（img/…）也从 index.html / script.js 里扫一遍。
# 用两个简单模式，避免把引号写进字符类里（PS 5.1 的解析器会误判）
foreach ($f in @('index.html', 'script.js')) {
  $text = Get-Content (Join-Path $root $f) -Raw -Encoding UTF8
  $patterns = @(
    'src="(img/[^"]+)"'
    "src='(img/[^']+)'"
    'href="(img/[^"]+)"'
    "href='(img/[^']+)'"
    '"(img/[A-Za-z0-9_/.-]+\.(?:png|webp|jpg|jpeg|svg))"'
  )
  foreach ($pat in $patterns) {
    foreach ($m in [regex]::Matches($text, $pat)) {
      $referenced += $m.Groups[1].Value
    }
  }
}
# 图标按目录通配(img/*)声明的，实际用到哪些文件要逐个核对。
# 只校验"像静态文件"的路径：末段带扩展名；含 ${...} 的是运行时拼出来的，无法静态核对，跳过
$extraNeeded = New-Object System.Collections.Generic.HashSet[string]
$refList = @($referenced |
  Where-Object { $_ } |
  Where-Object { $_ -notmatch '\*' } |
  Where-Object { $_ -notmatch '\$\{' } |
  Where-Object { $_ -match '\.[A-Za-z0-9]+$' } |
  Sort-Object -Unique)
foreach ($r in $refList) {
  if (-not (Test-Path -LiteralPath (Join-Path $root $r))) { [void]$extraNeeded.Add($r) }
}
if ($extraNeeded.Count) { throw "以下被引用的文件不存在: $($extraNeeded -join ', ')" }
Write-Host "[2/5] 资源引用全部存在 (manifest 版本 $($manifest.version))"

# 被引用但不在白名单里的文件，也要补进包（例如以后新增图标）
$notPacked = $refList | Where-Object { $runtimeFiles -notcontains $_ }
if ($notPacked) {
  Write-Host "      补充未被白名单覆盖的引用: $($notPacked -join ', ')"
  $runtimeFiles += $notPacked
}

# ---- 3. 生成 Firefox 专用 manifest ----
$ffManifest = Get-Content (Join-Path $root 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$ffManifest | Add-Member -NotePropertyName 'browser_specific_settings' -NotePropertyValue ([pscustomobject]@{
  gecko = [pscustomobject]@{
    id = 'litestartce@yujianxi666'
    strict_min_version = '109.0'
  }
}) -Force
$ffJson = $ffManifest | ConvertTo-Json -Depth 10
$ffTemp = Join-Path $outDir 'manifest.firefox.json'
[System.IO.File]::WriteAllText($ffTemp, $ffJson, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "[3/5] 已生成 Firefox 专用 manifest (gecko id + strict_min_version)"

# ---- 4. 打包 ----
function New-Package {
  param([string]$TargetPath, [string]$ManifestOverride)
  if (Test-Path $TargetPath) { Remove-Item $TargetPath -Force }
  $zip = [System.IO.Compression.ZipFile]::Open($TargetPath, 'Create')
  try {
    foreach ($rel in $runtimeFiles) {
      $entryName = $rel -replace '\\', '/'          # ZIP 规范要求正斜杠
      $src = if ($rel -eq 'manifest.json' -and $ManifestOverride) { $ManifestOverride } else { Join-Path $root $rel }
      [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $src, $entryName, [System.IO.Compression.CompressionLevel]::Optimal)
    }
  } finally { $zip.Dispose() }
}

$ver = $manifest.version
$zipPath = Join-Path $outDir "LitestartCE-v$ver-chrome.zip"
$xpiPath = Join-Path $outDir "LitestartCE-v$ver-firefox.xpi"
New-Package -TargetPath $zipPath
New-Package -TargetPath $xpiPath -ManifestOverride $ffTemp
Remove-Item $ffTemp -Force
Write-Host "[4/5] 已生成两个包"

# ---- 5. 回读校验 ----
foreach ($pkg in @($zipPath, $xpiPath)) {
  $zip = [System.IO.Compression.ZipFile]::OpenRead($pkg)
  try {
    $names = $zip.Entries | ForEach-Object { $_.FullName }
    if ($names -contains 'manifest.json') {
      $reader = New-Object System.IO.StreamReader($zip.GetEntry('manifest.json').Open())
      $inner = $reader.ReadToEnd() | ConvertFrom-Json
      $reader.Close()
      $gecko = if ($inner.browser_specific_settings) { $inner.browser_specific_settings.gecko.id } else { '(无)' }
      Write-Host ("[5/5] {0}: {1} 项, manifest v{2}, gecko id {3}, 大小 {4:N1} KB" -f `
        (Split-Path $pkg -Leaf), $names.Count, $inner.manifest_version, $gecko, ((Get-Item $pkg).Length / 1KB))
      $badSlash = $names | Where-Object { $_ -match '\\' }
      if ($badSlash) { throw "$pkg 里存在反斜杠路径: $($badSlash -join ', ')" }
      $nested = $names | Where-Object { $_ -match '^[^/]+/manifest\.json$' }
      if ($nested) { throw "$pkg 的 manifest.json 被套进了子目录: $nested" }
    } else {
      throw "$pkg 根目录缺少 manifest.json"
    }
  } finally { $zip.Dispose() }
}
Write-Host ""
Write-Host "完成，产物在: $outDir"
Get-ChildItem $outDir | Select-Object Name, @{n='KB';e={[math]::Round($_.Length/1KB,1)}} | Format-Table -AutoSize
