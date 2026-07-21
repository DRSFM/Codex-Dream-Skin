[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$InstanceId,
  [string]$SourceInstanceId = 'default'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')

Assert-DreamSkinInstanceId -InstanceId $InstanceId
Assert-DreamSkinInstanceId -InstanceId $SourceInstanceId
if ($InstanceId -ceq 'default') { throw 'The default appearance cannot be overwritten by an instance copy.' }
if ($InstanceId -ceq $SourceInstanceId) { throw 'Source and destination Dream Skin instances must differ.' }

$sourceRoot = Get-DreamSkinInstanceCustomRoot -InstanceId $SourceInstanceId
$destinationRoot = Get-DreamSkinInstanceCustomRoot -InstanceId $InstanceId
$supportedExtensions = @('.png', '.jpg', '.jpeg', '.webp')
$images = @(Get-ChildItem -LiteralPath $sourceRoot -File -ErrorAction Stop |
  Where-Object { $_.BaseName -ceq 'custom-image' -and $_.Extension.ToLowerInvariant() -in $supportedExtensions })
if ($images.Count -ne 1) {
  throw "Expected exactly one managed custom image in $sourceRoot; found $($images.Count)."
}
$sourceImage = $images[0]
if ($sourceImage.Length -lt 1 -or $sourceImage.Length -gt 16MB) {
  throw 'The source custom image must be between 1 byte and 16 MB.'
}

$sourceModePath = Join-Path $sourceRoot 'image-mode.txt'
$sourceThemePath = Join-Path $sourceRoot 'active-theme.txt'
$mode = (Read-DreamSkinUtf8File -Path $sourceModePath).Trim()
$themeId = (Read-DreamSkinUtf8File -Path $sourceThemePath).Trim()
if ($mode -notin @('full-window', 'home-card')) { throw "Unsupported source image mode: $mode" }
if ($themeId -cnotmatch '^[a-z0-9][a-z0-9-]{0,79}$') { throw "Unsafe source theme ID: $themeId" }
$themePath = Join-Path (Split-Path -Parent $PSScriptRoot) "themes\$themeId\theme.json"
if (-not (Test-Path -LiteralPath $themePath -PathType Leaf)) {
  throw "The selected theme package is unavailable: $themeId"
}

New-Item -ItemType Directory -Force -Path $destinationRoot | Out-Null
$extension = $sourceImage.Extension.ToLowerInvariant()
$destinationImage = Join-Path $destinationRoot "custom-image$extension"
$temporary = Join-Path $destinationRoot ".custom-image.$PID.$([guid]::NewGuid().ToString('N')).tmp"
$replaceBackup = Join-Path $destinationRoot ".custom-image.$PID.$([guid]::NewGuid().ToString('N')).backup"
try {
  [IO.File]::Copy($sourceImage.FullName, $temporary, $true)
  if ([IO.File]::Exists($destinationImage)) {
    [IO.File]::Replace($temporary, $destinationImage, $replaceBackup)
  } else {
    [IO.File]::Move($temporary, $destinationImage)
  }
} finally {
  if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
  if ([IO.File]::Exists($replaceBackup)) { [IO.File]::Delete($replaceBackup) }
}

Get-ChildItem -LiteralPath $destinationRoot -File -ErrorAction Stop |
  Where-Object {
    $_.BaseName -ceq 'custom-image' -and $_.FullName -cne $destinationImage -and
      $_.Extension.ToLowerInvariant() -in $supportedExtensions
  } |
  Remove-Item -Force
Write-DreamSkinUtf8FileAtomically -Path (Join-Path $destinationRoot 'image-mode.txt') -Content "$mode`r`n"
Write-DreamSkinUtf8FileAtomically -Path (Join-Path $destinationRoot 'active-theme.txt') -Content "$themeId`r`n"

$sourceHash = (Get-FileHash -LiteralPath $sourceImage.FullName -Algorithm SHA256).Hash
$destinationHash = (Get-FileHash -LiteralPath $destinationImage -Algorithm SHA256).Hash
if ($sourceHash -cne $destinationHash) { throw 'The copied appearance image hash does not match the source.' }

[pscustomobject]@{
  instanceId = $InstanceId
  sourceInstanceId = $SourceInstanceId
  customRoot = $destinationRoot
  image = $destinationImage
  imageSha256 = $destinationHash
  mode = $mode
  themeId = $themeId
} | ConvertTo-Json -Depth 3
