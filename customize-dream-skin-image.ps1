[CmdletBinding()]
param(
  [string]$ImagePath,
  [ValidateSet('full-window', 'home-card')]
  [string]$Mode,
  [switch]$Reset,
  [switch]$NoApply
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$startScript = Join-Path $root 'windows\scripts\start-dream-skin.ps1'
$customRoot = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin\custom'
$modePath = Join-Path $customRoot 'image-mode.txt'
$supportedExtensions = @('.png', '.jpg', '.jpeg', '.webp')
$maximumBytes = 16MB
$imagePathWasProvided = $PSBoundParameters.ContainsKey('ImagePath')

function Select-DreamSkinImage {
  Add-Type -AssemblyName System.Windows.Forms
  $dialog = [System.Windows.Forms.OpenFileDialog]::new()
  try {
    $dialog.Title = '选择 Codex Dream Skin 图片'
    $dialog.Filter = '支持的图片 (*.png;*.jpg;*.jpeg;*.webp)|*.png;*.jpg;*.jpeg;*.webp|所有文件 (*.*)|*.*'
    $dialog.Multiselect = $false
    $pictures = [Environment]::GetFolderPath('MyPictures')
    if ($pictures) { $dialog.InitialDirectory = $pictures }
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    return $dialog.FileName
  } finally {
    $dialog.Dispose()
  }
}

function Select-DreamSkinImageMode {
  Add-Type -AssemblyName System.Windows.Forms
  $message = @'
请选择图片的显示方式：

“是”    = 整窗背景（推荐）
“否”    = 只插入主页图片卡片（保留原有效果）
“取消”  = 不更改
'@
  $result = [System.Windows.Forms.MessageBox]::Show(
    $message,
    'Codex Dream Skin 图片显示方式',
    [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
    [System.Windows.Forms.MessageBoxIcon]::Question,
    [System.Windows.Forms.MessageBoxDefaultButton]::Button1
  )
  switch ($result) {
    ([System.Windows.Forms.DialogResult]::Yes) { return 'full-window' }
    ([System.Windows.Forms.DialogResult]::No) { return 'home-card' }
    default { return $null }
  }
}

function Write-DreamSkinModeAtomically {
  param([Parameter(Mandatory = $true)][string]$Value)
  $temporary = Join-Path $customRoot ".image-mode.$PID.$([guid]::NewGuid().ToString('N')).tmp"
  $backup = Join-Path $customRoot ".image-mode.$PID.$([guid]::NewGuid().ToString('N')).backup"
  try {
    [IO.File]::WriteAllText($temporary, "$Value`r`n", [Text.UTF8Encoding]::new($false))
    if ([IO.File]::Exists($modePath)) {
      [IO.File]::Replace($temporary, $modePath, $backup)
    } else {
      [IO.File]::Move($temporary, $modePath)
    }
  } finally {
    if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    if ([IO.File]::Exists($backup)) { [IO.File]::Delete($backup) }
  }
}

function Invoke-DreamSkinReapply {
  if ($NoApply) { return }
  & $startScript
  if ($LASTEXITCODE -ne 0) { throw "Dream Skin 重新应用失败，退出码：$LASTEXITCODE" }
}

try {
  New-Item -ItemType Directory -Force -Path $customRoot | Out-Null

  if ($Reset) {
    Get-ChildItem -LiteralPath $customRoot -File -Filter 'custom-image.*' -ErrorAction SilentlyContinue |
      Remove-Item -Force
    Remove-Item -LiteralPath $modePath -Force -ErrorAction SilentlyContinue
    Invoke-DreamSkinReapply
    Write-Host '已恢复仓库内置图片和主页图片卡片模式。' -ForegroundColor Green
    exit 0
  }

  if (-not $ImagePath) { $ImagePath = Select-DreamSkinImage }
  if (-not $ImagePath) {
    Write-Host '已取消，没有更改图片。'
    exit 0
  }
  if (-not $Mode) {
    $Mode = if ($imagePathWasProvided) { 'full-window' } else { Select-DreamSkinImageMode }
  }
  if (-not $Mode) {
    Write-Host '已取消，没有更改图片。'
    exit 0
  }

  $source = Get-Item -LiteralPath $ImagePath -ErrorAction Stop
  if ($source.PSIsContainer) { throw '请选择图片文件，而不是文件夹。' }
  $extension = $source.Extension.ToLowerInvariant()
  if ($extension -notin $supportedExtensions) {
    throw '仅支持 PNG、JPG/JPEG 和 WebP 图片。'
  }
  if ($source.Length -lt 1 -or $source.Length -gt $maximumBytes) {
    throw '图片必须大于 0 字节且不超过 16 MB。'
  }

  $target = Join-Path $customRoot "custom-image$extension"
  $temporary = Join-Path $customRoot ".custom-image.$PID.$([guid]::NewGuid().ToString('N')).tmp"
  $replaceBackup = Join-Path $customRoot ".custom-image.$PID.$([guid]::NewGuid().ToString('N')).backup"
  try {
    [IO.File]::Copy($source.FullName, $temporary, $true)
    if ([IO.File]::Exists($target)) {
      [IO.File]::Replace($temporary, $target, $replaceBackup)
    } else {
      [IO.File]::Move($temporary, $target)
    }
  } finally {
    if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    if ([IO.File]::Exists($replaceBackup)) { [IO.File]::Delete($replaceBackup) }
  }

  Get-ChildItem -LiteralPath $customRoot -File -Filter 'custom-image.*' |
    Where-Object { $_.FullName -ne $target } |
    Remove-Item -Force
  Write-DreamSkinModeAtomically -Value $Mode

  Invoke-DreamSkinReapply
  $modeName = if ($Mode -eq 'full-window') { '整窗背景' } else { '主页图片卡片' }
  Write-Host "自定义图片已应用：$($source.Name)；显示方式：$modeName" -ForegroundColor Green
} catch {
  Write-Host ''
  Write-Host "更换图片失败：$($_.Exception.Message)" -ForegroundColor Red
  Read-Host '按 Enter 关闭窗口'
  exit 1
}
