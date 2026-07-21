[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$InstanceId,
  [string]$ImagePath,
  [switch]$ClearImage,
  [ValidateSet('full-window', 'home-card')]
  [string]$Mode,
  [string]$ThemeId
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')

if ($ImagePath -and $ClearImage) { throw 'Choose either -ImagePath or -ClearImage, not both.' }
if (-not $ImagePath -and -not $ClearImage -and -not $Mode -and -not $ThemeId) {
  throw 'No appearance change was requested.'
}

$operationLock = Enter-DreamSkinOperationLock
try {
  Assert-DreamSkinInstanceId -InstanceId $InstanceId
  $customRoot = Get-DreamSkinInstanceCustomRoot -InstanceId $InstanceId
  $windowsRoot = Split-Path -Parent $PSScriptRoot
  $supportedExtensions = @('.png', '.jpg', '.jpeg', '.webp')
  New-Item -ItemType Directory -Force -Path $customRoot | Out-Null

  if ($ImagePath) {
    $source = Get-Item -LiteralPath $ImagePath -ErrorAction Stop
    if ($source.PSIsContainer) { throw 'The selected background must be a file.' }
    $extension = $source.Extension.ToLowerInvariant()
    if ($extension -notin $supportedExtensions) { throw 'Only PNG, JPG/JPEG and WebP images are supported.' }
    if ($source.Length -lt 1 -or $source.Length -gt 16MB) {
      throw 'The selected background must be between 1 byte and 16 MB.'
    }

    $destination = Join-Path $customRoot "custom-image$extension"
    $temporary = Join-Path $customRoot ".custom-image.$PID.$([guid]::NewGuid().ToString('N')).tmp"
    $backup = Join-Path $customRoot ".custom-image.$PID.$([guid]::NewGuid().ToString('N')).backup"
    try {
      [IO.File]::Copy($source.FullName, $temporary, $true)
      if ([IO.File]::Exists($destination)) {
        [IO.File]::Replace($temporary, $destination, $backup)
      } else {
        [IO.File]::Move($temporary, $destination)
      }
    } finally {
      if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
      if ([IO.File]::Exists($backup)) { [IO.File]::Delete($backup) }
    }
    Get-ChildItem -LiteralPath $customRoot -File -ErrorAction Stop |
      Where-Object {
        $_.BaseName -ceq 'custom-image' -and $_.FullName -cne $destination -and
          $_.Extension.ToLowerInvariant() -in $supportedExtensions
      } |
      Remove-Item -Force
  } elseif ($ClearImage) {
    Get-ChildItem -LiteralPath $customRoot -File -ErrorAction SilentlyContinue |
      Where-Object {
        $_.BaseName -ceq 'custom-image' -and $_.Extension.ToLowerInvariant() -in $supportedExtensions
      } |
      Remove-Item -Force
  }

  if ($Mode) {
    Write-DreamSkinUtf8FileAtomically -Path (Join-Path $customRoot 'image-mode.txt') `
      -Content "$Mode`r`n"
  }

  if ($ThemeId) {
    if ($ThemeId -cnotmatch '^[a-z0-9][a-z0-9-]{0,79}$') { throw "Unsafe theme ID: $ThemeId" }
    $themePath = Join-Path $windowsRoot "themes\$ThemeId\theme.json"
    if (-not (Test-Path -LiteralPath $themePath -PathType Leaf)) { throw "Theme not found: $ThemeId" }
    $theme = (Read-DreamSkinUtf8File -Path $themePath) | ConvertFrom-Json -ErrorAction Stop
    if ([int]$theme.schemaVersion -ne 1 -or "$($theme.id)" -cne $ThemeId) {
      throw "Theme package identity does not match: $ThemeId"
    }
    Write-DreamSkinUtf8FileAtomically -Path (Join-Path $customRoot 'active-theme.txt') `
      -Content "$ThemeId`r`n"
  }

  $managedImages = @(Get-ChildItem -LiteralPath $customRoot -File -ErrorAction Stop |
    Where-Object {
      $_.BaseName -ceq 'custom-image' -and $_.Extension.ToLowerInvariant() -in $supportedExtensions
    })
  if ($managedImages.Count -gt 1) { throw 'Multiple managed background images remain after update.' }

  $effectiveMode = 'home-card'
  $modePath = Join-Path $customRoot 'image-mode.txt'
  if (Test-Path -LiteralPath $modePath) {
    $savedMode = (Read-DreamSkinUtf8File -Path $modePath).Trim()
    if ($savedMode -in @('full-window', 'home-card')) { $effectiveMode = $savedMode }
  }
  $effectiveTheme = 'pink-dream'
  $themeSelectorPath = Join-Path $customRoot 'active-theme.txt'
  if (Test-Path -LiteralPath $themeSelectorPath) {
    $savedTheme = (Read-DreamSkinUtf8File -Path $themeSelectorPath).Trim()
    if ($savedTheme -cmatch '^[a-z0-9][a-z0-9-]{0,79}$') { $effectiveTheme = $savedTheme }
  }
  $image = if ($managedImages.Count -eq 1) {
    $managedImages[0].FullName
  } else {
    Join-Path $windowsRoot 'assets\dream-reference.png'
  }

  [pscustomobject]@{
    schemaVersion = 1
    instanceId = $InstanceId
    customRoot = $customRoot
    image = $image
    hasCustomImage = $managedImages.Count -eq 1
    imageSha256 = if (Test-Path -LiteralPath $image) {
      (Get-FileHash -LiteralPath $image -Algorithm SHA256).Hash
    } else { $null }
    mode = $effectiveMode
    themeId = $effectiveTheme
  } | ConvertTo-Json -Depth 3
} finally {
  Exit-DreamSkinOperationLock -Mutex $operationLock
}
