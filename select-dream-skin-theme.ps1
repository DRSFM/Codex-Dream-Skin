[CmdletBinding()]
param(
  [string]$ThemeId,
  [switch]$Reset,
  [switch]$List,
  [switch]$NoApply
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$themesRoot = Join-Path $root 'windows\themes'
$startScript = Join-Path $root 'windows\scripts\start-dream-skin.ps1'
$customRoot = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin\custom'
$activeThemePath = Join-Path $customRoot 'active-theme.txt'
$defaultThemeId = 'pink-dream'
$themeOrder = @(
  'pink-dream',
  'fortune-work',
  'red-white-sci-fi',
  'crystal-clear',
  'inspiration-cosmos',
  'purple-night',
  'miku-future',
  'stage-black-gold'
)

function Get-DreamSkinThemes {
  $themesById = @{}
  foreach ($file in Get-ChildItem -LiteralPath $themesRoot -Recurse -File -Filter 'theme.json') {
    $theme = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json -ErrorAction Stop
    if ($theme.schemaVersion -ne 1 -or -not $theme.id -or -not $theme.name) {
      throw "主题文件格式不受支持：$($file.FullName)"
    }
    if ($theme.id -notmatch '^[a-z0-9][a-z0-9-]{0,79}$') {
      throw "主题 ID 不安全：$($theme.id)"
    }
    if ($themesById.ContainsKey($theme.id)) { throw "主题 ID 重复：$($theme.id)" }
    $themesById[$theme.id] = $theme
  }
  return @($themeOrder | Where-Object { $themesById.ContainsKey($_) } | ForEach-Object { $themesById[$_] })
}

function Select-DreamSkinTheme {
  param(
    [Parameter(Mandatory = $true)][array]$Themes,
    [Parameter(Mandatory = $true)][string]$CurrentId
  )

  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing

  $form = [Windows.Forms.Form]::new()
  $form.Text = '选择 Codex Dream Skin 主题'
  $form.StartPosition = 'CenterScreen'
  $form.ClientSize = [Drawing.Size]::new(660, 420)
  $form.MinimumSize = [Drawing.Size]::new(680, 460)
  $form.Font = [Drawing.Font]::new('Microsoft YaHei UI', 10)

  $list = [Windows.Forms.ListBox]::new()
  $list.Location = [Drawing.Point]::new(18, 18)
  $list.Size = [Drawing.Size]::new(225, 340)
  $list.DisplayMember = 'name'
  foreach ($theme in $Themes) { [void]$list.Items.Add($theme) }

  $title = [Windows.Forms.Label]::new()
  $title.Location = [Drawing.Point]::new(270, 28)
  $title.Size = [Drawing.Size]::new(355, 34)
  $title.Font = [Drawing.Font]::new('Microsoft YaHei UI', 17, [Drawing.FontStyle]::Bold)

  $description = [Windows.Forms.Label]::new()
  $description.Location = [Drawing.Point]::new(272, 74)
  $description.Size = [Drawing.Size]::new(350, 52)

  $preview = [Windows.Forms.Panel]::new()
  $preview.Location = [Drawing.Point]::new(270, 140)
  $preview.Size = [Drawing.Size]::new(355, 150)
  $preview.BorderStyle = 'FixedSingle'

  $previewTitle = [Windows.Forms.Label]::new()
  $previewTitle.Location = [Drawing.Point]::new(20, 18)
  $previewTitle.Size = [Drawing.Size]::new(310, 32)
  $previewTitle.Font = [Drawing.Font]::new('Microsoft YaHei UI', 13, [Drawing.FontStyle]::Bold)
  $preview.Controls.Add($previewTitle)

  $swatches = [Windows.Forms.FlowLayoutPanel]::new()
  $swatches.Location = [Drawing.Point]::new(20, 72)
  $swatches.Size = [Drawing.Size]::new(310, 54)
  $swatches.WrapContents = $false
  $preview.Controls.Add($swatches)

  $apply = [Windows.Forms.Button]::new()
  $apply.Text = '立即应用'
  $apply.Location = [Drawing.Point]::new(430, 330)
  $apply.Size = [Drawing.Size]::new(95, 36)
  $apply.DialogResult = [Windows.Forms.DialogResult]::OK

  $cancel = [Windows.Forms.Button]::new()
  $cancel.Text = '取消'
  $cancel.Location = [Drawing.Point]::new(535, 330)
  $cancel.Size = [Drawing.Size]::new(90, 36)
  $cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel

  $updatePreview = {
    $theme = $list.SelectedItem
    if (-not $theme) { return }
    $title.Text = $theme.name
    $description.Text = $theme.description
    $previewTitle.Text = $theme.brandTitle
    $preview.BackColor = [Drawing.ColorTranslator]::FromHtml($theme.colors.panel)
    $previewTitle.ForeColor = [Drawing.ColorTranslator]::FromHtml($theme.colors.ink)
    $swatches.Controls.Clear()
    foreach ($key in @('accent', 'accentAlt', 'secondary', 'highlight', 'backgroundAlt')) {
      $swatch = [Windows.Forms.Panel]::new()
      $swatch.Size = [Drawing.Size]::new(48, 42)
      $swatch.Margin = [Windows.Forms.Padding]::new(0, 0, 10, 0)
      $swatch.BackColor = [Drawing.ColorTranslator]::FromHtml($theme.colors.$key)
      $swatches.Controls.Add($swatch)
    }
  }
  $list.Add_SelectedIndexChanged($updatePreview)

  $form.Controls.AddRange(@($list, $title, $description, $preview, $apply, $cancel))
  $form.AcceptButton = $apply
  $form.CancelButton = $cancel
  $selectedIndex = 0
  for ($index = 0; $index -lt $Themes.Count; $index++) {
    if ($Themes[$index].id -eq $CurrentId) { $selectedIndex = $index; break }
  }
  $list.SelectedIndex = $selectedIndex

  try {
    if ($form.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return $null }
    return $list.SelectedItem.id
  } finally {
    $form.Dispose()
  }
}

function Write-DreamSkinActiveTheme {
  param([Parameter(Mandatory = $true)][string]$Id)

  New-Item -ItemType Directory -Force -Path $customRoot | Out-Null
  $utf8 = [Text.UTF8Encoding]::new($false, $true)
  $temporary = Join-Path $customRoot ".active-theme.$PID.$([guid]::NewGuid().ToString('N')).tmp"
  $replaceBackup = Join-Path $customRoot ".active-theme.$PID.$([guid]::NewGuid().ToString('N')).backup"
  try {
    [IO.File]::WriteAllText($temporary, "$Id`n", $utf8)
    if ([IO.File]::Exists($activeThemePath)) {
      [IO.File]::Replace($temporary, $activeThemePath, $replaceBackup)
    } else {
      [IO.File]::Move($temporary, $activeThemePath)
    }
  } finally {
    if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    if ([IO.File]::Exists($replaceBackup)) { [IO.File]::Delete($replaceBackup) }
  }
}

try {
  $themes = @(Get-DreamSkinThemes)
  if ($themes.Count -eq 0) { throw '没有找到可用主题。' }

  if ($List) {
    $themes | Select-Object id, name, description, scheme | Format-Table -AutoSize
    exit 0
  }

  $currentId = $defaultThemeId
  if (Test-Path -LiteralPath $activeThemePath) {
    $savedId = (Get-Content -Raw -LiteralPath $activeThemePath).Trim()
    if ($savedId) { $currentId = $savedId }
  }
  if ($Reset) { $ThemeId = $defaultThemeId }
  if (-not $ThemeId) { $ThemeId = Select-DreamSkinTheme -Themes $themes -CurrentId $currentId }
  if (-not $ThemeId) {
    Write-Host '已取消，没有切换主题。'
    exit 0
  }

  $selected = $themes | Where-Object { $_.id -eq $ThemeId } | Select-Object -First 1
  if (-not $selected) { throw "找不到主题：$ThemeId" }
  Write-DreamSkinActiveTheme -Id $selected.id

  if (-not $NoApply) {
    & $startScript
    if ($LASTEXITCODE -ne 0) { throw "主题重新应用失败，退出码：$LASTEXITCODE" }
  }
  Write-Host "已应用主题：$($selected.name)" -ForegroundColor Green
} catch {
  Write-Host ''
  Write-Host "切换主题失败：$($_.Exception.Message)" -ForegroundColor Red
  Read-Host '按 Enter 关闭窗口'
  exit 1
}
