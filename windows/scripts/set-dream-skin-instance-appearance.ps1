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
. (Join-Path $PSScriptRoot 'theme-windows.ps1')

if ($ImagePath -and $ClearImage) { throw 'Choose either -ImagePath or -ClearImage, not both.' }
if (-not $ImagePath -and -not $ClearImage -and -not $Mode -and -not $ThemeId) {
  throw 'No appearance change was requested.'
}

$operationLock = Enter-DreamSkinOperationLock
try {
  Assert-DreamSkinInstanceId -InstanceId $InstanceId
  $stateRoot = Get-DreamSkinInstanceStateRoot -InstanceId $InstanceId
  $windowsRoot = Split-Path -Parent $PSScriptRoot
  $themePaths = Initialize-DreamSkinThemeStore -SkillRoot $windowsRoot -StateRoot $stateRoot
  $active = Read-DreamSkinTheme -ThemeDirectory $themePaths.Active
  $customImageMarker = Join-Path $stateRoot 'launcher-custom-image'

  $effectiveImage = $active.ImagePath
  if ($ImagePath) {
    $effectiveImage = [System.IO.Path]::GetFullPath($ImagePath)
    Assert-DreamSkinImageFile -Path $effectiveImage
    Write-DreamSkinUtf8FileAtomically -Path $customImageMarker -Content "custom`r`n"
  } elseif ($ClearImage) {
    $effectiveImage = Join-Path $windowsRoot 'assets\dream-reference.jpg'
    Assert-DreamSkinImageFile -Path $effectiveImage
    Remove-Item -LiteralPath $customImageMarker -Force -ErrorAction SilentlyContinue
  }

  $theme = $active.Theme
  if ($ThemeId) {
    if ($ThemeId -cnotmatch '^[a-z0-9][a-z0-9-]{0,79}$') { throw "Unsafe theme ID: $ThemeId" }
    $catalogPath = Join-Path $windowsRoot "themes\$ThemeId\theme.json"
    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) { throw "Theme not found: $ThemeId" }
    $catalog = (Read-DreamSkinUtf8File -Path $catalogPath) | ConvertFrom-Json -ErrorAction Stop
    if ([int]$catalog.schemaVersion -ne 1 -or "$($catalog.id)" -cne $ThemeId) {
      throw "Theme package identity does not match: $ThemeId"
    }
    $theme = [pscustomobject]@{
      id = $ThemeId
      name = "$($catalog.name)"
      brandSubtitle = if ($catalog.brandSubtitle) { "$($catalog.brandSubtitle)" } else { 'CODEX DREAM SKIN' }
      tagline = if ($catalog.description) { "$($catalog.description)" } else { 'Make something wonderful.' }
      projectPrefix = '选择项目 · '
      projectLabel = '◉  选择项目'
      statusText = 'DREAM SKIN ONLINE'
      quote = if ($catalog.signature) { "$($catalog.signature)" } else { 'MAKE SOMETHING WONDERFUL' }
      appearance = if ("$($catalog.scheme)" -in @('light', 'dark')) { "$($catalog.scheme)" } else { 'auto' }
      art = [pscustomobject]@{
        focusX = $active.Theme.art.focusX
        focusY = $active.Theme.art.focusY
        safeArea = if ($active.Theme.art.safeArea) { "$($active.Theme.art.safeArea)" } else { 'auto' }
        taskMode = if ($Mode -ceq 'full-window') { 'full' } elseif ($Mode -ceq 'home-card') { 'banner' } `
          elseif ($active.Theme.art.taskMode) { "$($active.Theme.art.taskMode)" } else { 'auto' }
      }
      colors = [pscustomobject]@{
        background = "$($catalog.colors.background)"
        panel = "$($catalog.colors.panel)"
        panelAlt = "$($catalog.colors.panelAlt)"
        accent = "$($catalog.colors.accent)"
        accentAlt = "$($catalog.colors.accentAlt)"
        secondary = "$($catalog.colors.secondary)"
        highlight = "$($catalog.colors.highlight)"
        text = "$($catalog.colors.ink)"
        muted = "$($catalog.colors.muted)"
        line = "$($catalog.colors.line)"
      }
    }
  } elseif ($Mode) {
    $theme.art.taskMode = if ($Mode -ceq 'full-window') { 'full' } else { 'banner' }
  }

  Set-DreamSkinActiveTheme -ImagePath $effectiveImage -Theme $theme -StateRoot $stateRoot | Out-Null
  if ($Mode) {
    Write-DreamSkinUtf8FileAtomically -Path (Join-Path $stateRoot 'launcher-mode.txt') -Content "$Mode`r`n"
  }

  $updated = Read-DreamSkinTheme -ThemeDirectory $themePaths.Active
  $effectiveMode = if (Test-Path -LiteralPath (Join-Path $stateRoot 'launcher-mode.txt')) {
    (Read-DreamSkinUtf8File -Path (Join-Path $stateRoot 'launcher-mode.txt')).Trim()
  } elseif ("$($updated.Theme.art.taskMode)" -eq 'full') { 'full-window' } else { 'home-card' }
  [pscustomobject]@{
    schemaVersion = 1
    instanceId = $InstanceId
    customRoot = $themePaths.Active
    image = $updated.ImagePath
    hasCustomImage = Test-Path -LiteralPath $customImageMarker -PathType Leaf
    imageSha256 = (Get-FileHash -LiteralPath $updated.ImagePath -Algorithm SHA256).Hash
    mode = $effectiveMode
    themeId = "$($updated.Theme.id)"
  } | ConvertTo-Json -Depth 3
} finally {
  Exit-DreamSkinOperationLock -Mutex $operationLock
}
