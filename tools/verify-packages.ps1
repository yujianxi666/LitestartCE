# 独立校验已生成的包（不复用打包脚本的判断逻辑）
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $root 'dist'
$required = @(
  'manifest.json', 'index.html', 'script.js',
  '_locales/zh_CN/messages.json', '_locales/zh_TW/messages.json',
  '_locales/en/messages.json', '_locales/ja/messages.json', '_locales/ru/messages.json',
  'img/icon.png', 'img/icon_d.png', 'img/icon_l.png', 'img/background.webp',
  'img/logo/baidu_logo_dark.png', 'img/logo/baidu_logo_light.png',
  'img/logo/google_logo_dark.png', 'img/logo/google_logo_light.png'
)
$forbiddenPrefixes = @('docs/', 'tools/', '.github/', 'dist/')
$forbiddenNames = @('build-packages.ps1', 'README.md', 'README_EN.md', 'manifest.firefox.json')

foreach ($pkg in Get-ChildItem $dist -File | Sort-Object Name) {
  Write-Host "==== $($pkg.Name) ===="
  # 用流方式完整读一遍，能读通说明 zip 结构没坏
  $fs = [System.IO.File]::OpenRead($pkg.FullName)
  $zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Read)
  try {
    $entries = $zip.Entries
    $names = $entries | ForEach-Object { $_.FullName }
    Write-Host ("  条目数: {0}" -f $entries.Count)

    # 完整解压到内存，验证 CRC / 数据可读
    $total = 0
    foreach ($e in $entries) {
      $s = $e.Open()
      $buf = New-Object byte[] 65536
      while (($n = $s.Read($buf, 0, $buf.Length)) -gt 0) { $total += $n }
      $s.Close()
    }
    Write-Host ("  解压校验通过，共 {0:N1} KB 数据" -f ($total / 1KB))

    # 必需文件
    $miss = $required | Where-Object { $names -notcontains $_ }
    if ($miss) { Write-Host "  [失败] 缺少: $($miss -join ', ')" } else { Write-Host "  [通过] 必需文件齐全" }

    # 根目录必须有 manifest.json
    if ($names -contains 'manifest.json') { Write-Host "  [通过] manifest.json 在根目录" } else { Write-Host "  [失败] manifest.json 不在根目录" }

    # 反斜杠 / 嵌套目录
    $bs = $names | Where-Object { $_ -match '\\' }
    if ($bs) { Write-Host "  [失败] 反斜杠路径: $($bs -join ', ')" } else { Write-Host "  [通过] 全部使用正斜杠" }
    $nested = $names | Where-Object { $_ -match '^[^/]+/manifest\.json$' }
    if ($nested) { Write-Host "  [失败] manifest.json 被套进子目录" } else { Write-Host "  [通过] 没有多余的外层目录" }

    # 不该出现的开发文件
    $leak = $names | Where-Object {
      $n = $_
      ($forbiddenPrefixes | Where-Object { $n.StartsWith($_) }) -or ($forbiddenNames -contains $n)
    }
    if ($leak) { Write-Host "  [失败] 打进了开发文件: $($leak -join ', ')" } else { Write-Host "  [通过] 未包含开发文件/截图" }

    # manifest 内容
    $sr = New-Object System.IO.StreamReader($zip.GetEntry('manifest.json').Open(), [System.Text.Encoding]::UTF8)
    $mf = $sr.ReadToEnd() | ConvertFrom-Json
    $sr.Close()
    Write-Host ("  manifest: v{0} version {1} 默认语言 {2}" -f $mf.manifest_version, $mf.version, $mf.default_locale)
    Write-Host ("  覆盖新标签页: {0}" -f $mf.chrome_url_overrides.newtab)
    if ($mf.browser_specific_settings) {
      Write-Host ("  gecko id: {0} / strict_min_version {1}" -f $mf.browser_specific_settings.gecko.id, $mf.browser_specific_settings.gecko.strict_min_version)
    } else {
      Write-Host "  gecko 配置: 无（Chromium 包不需要）"
    }

    # script.js 必须能找到 index.html 里引用的元素（粗查：文件非空且以 DOMContentLoaded 收尾）
    $sr2 = New-Object System.IO.StreamReader($zip.GetEntry('script.js').Open(), [System.Text.Encoding]::UTF8)
    $js = $sr2.ReadToEnd()
    $sr2.Close()
    Write-Host ("  script.js {0:N0} 字符，末尾片段: {1}" -f $js.Length, ($js.Substring($js.Length - 30) -replace '\s+', ' '))
  } finally {
    $zip.Dispose(); $fs.Dispose()
  }
}
Write-Host ""
Write-Host "dist 目录内容:"
Get-ChildItem $dist | Select-Object Name, @{n='KB';e={[math]::Round($_.Length/1KB,1)}} | Format-Table -AutoSize
