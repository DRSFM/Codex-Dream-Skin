[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$InstanceId,
  [int]$Port = 9335,
  [string]$ProfilePath
)

$ErrorActionPreference = 'Stop'
$PortExplicit = $PSBoundParameters.ContainsKey('Port')
. (Join-Path $PSScriptRoot 'common-windows.ps1')

Assert-DreamSkinInstanceId -InstanceId $InstanceId
if ($ProfilePath) { $ProfilePath = [System.IO.Path]::GetFullPath($ProfilePath) }
if ($InstanceId -cne 'default' -and -not $ProfilePath) {
  throw 'A non-default status query requires an explicit -ProfilePath.'
}

$stateRoot = Get-DreamSkinInstanceStateRoot -InstanceId $InstanceId
$customRoot = Get-DreamSkinInstanceCustomRoot -InstanceId $InstanceId
$statePath = Join-Path $stateRoot 'state.json'
$state = Read-DreamSkinState -Path $statePath
if ($null -ne $state -and $state.instanceId -and "$($state.instanceId)" -cne $InstanceId) {
  throw "Dream Skin state belongs to another instance: $($state.instanceId)"
}
if ($null -ne $state -and $state.profilePath) {
  $savedProfilePath = [System.IO.Path]::GetFullPath("$($state.profilePath)")
  if ($ProfilePath -and -not (Test-DreamSkinPathEqual -Left $ProfilePath -Right $savedProfilePath)) {
    throw 'The requested profile does not match the saved Dream Skin instance state.'
  }
  if (-not $ProfilePath) { $ProfilePath = $savedProfilePath }
}
if (-not $PortExplicit -and $null -ne $state -and $state.port) { $Port = [int]$state.port }
Assert-DreamSkinPort -Port $Port

$codexCandidates = @()
try {
  $codexCandidates += Get-DreamSkinCodexInstall
} catch {
  throw "Codex install discovery failed during status query: $($_.Exception.Message)"
}
$savedCodex = Get-DreamSkinCodexInstallFromState -State $state
if ($null -ne $savedCodex -and
  -not ($codexCandidates | Where-Object {
    Test-DreamSkinPathEqual -Left $_.Executable -Right $savedCodex.Executable
  })) {
  $codexCandidates += $savedCodex
}

$desktopProcessIds = @()
$cdpIdentity = $null
foreach ($codex in $codexCandidates) {
  $desktopProcessIds += @(Get-DreamSkinCodexProcesses -Codex $codex -ProfilePath $ProfilePath -MatchProfile |
    ForEach-Object { [int]$_.ProcessId })
  if ($null -eq $cdpIdentity) {
    $cdpIdentity = Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $codex `
      -ProfilePath $ProfilePath -MatchProfile
  }
}
$desktopProcessIds = @($desktopProcessIds | Sort-Object -Unique)
$injectorRunning = $false
if ($null -ne $state -and $state.injectorPid) {
  $injectorRunning = $null -ne (Get-Process -Id ([int]$state.injectorPid) -ErrorAction SilentlyContinue)
}
$skinRunning = $null -ne $cdpIdentity -and $injectorRunning

$supportedExtensions = @('.png', '.jpg', '.jpeg', '.webp')
$managedImages = @()
if (Test-Path -LiteralPath $customRoot -PathType Container) {
  $managedImages = @(Get-ChildItem -LiteralPath $customRoot -File -ErrorAction Stop |
    Where-Object {
      $_.BaseName -ceq 'custom-image' -and $_.Extension.ToLowerInvariant() -in $supportedExtensions
    })
}
if ($managedImages.Count -gt 1) { throw "Multiple managed backgrounds exist for instance: $InstanceId" }
$windowsRoot = Split-Path -Parent $PSScriptRoot
$image = if ($managedImages.Count -eq 1) {
  $managedImages[0].FullName
} else {
  Join-Path $windowsRoot 'assets\dream-reference.png'
}
$mode = 'home-card'
$modePath = Join-Path $customRoot 'image-mode.txt'
if (Test-Path -LiteralPath $modePath) {
  $savedMode = (Read-DreamSkinUtf8File -Path $modePath).Trim()
  if ($savedMode -in @('full-window', 'home-card')) { $mode = $savedMode }
}
$themeId = 'pink-dream'
$themePath = Join-Path $customRoot 'active-theme.txt'
if (Test-Path -LiteralPath $themePath) {
  $savedTheme = (Read-DreamSkinUtf8File -Path $themePath).Trim()
  if ($savedTheme -cmatch '^[a-z0-9][a-z0-9-]{0,79}$') { $themeId = $savedTheme }
}
$verifyPath = Join-Path $stateRoot 'verify.log'
$status = if ($skinRunning) {
  'running'
} elseif ($desktopProcessIds.Count -gt 0) {
  'desktop-only'
} elseif ($null -ne $state) {
  'attention'
} else {
  'stopped'
}

[pscustomobject]@{
  schemaVersion = 1
  instanceId = $InstanceId
  status = $status
  isProtected = $InstanceId -ceq 'default'
  desktopRunning = $desktopProcessIds.Count -gt 0
  desktopProcessIds = $desktopProcessIds
  skinRunning = $skinRunning
  cdpVerified = $null -ne $cdpIdentity
  injectorRunning = $injectorRunning
  injectorPid = if ($null -ne $state) { $state.injectorPid } else { $null }
  port = $Port
  profilePath = $ProfilePath
  statePath = $statePath
  customRoot = $customRoot
  image = $image
  hasCustomImage = $managedImages.Count -eq 1
  mode = $mode
  themeId = $themeId
  stateCreatedAt = if ($null -ne $state) { $state.createdAt } else { $null }
  lastVerifiedAt = if (Test-Path -LiteralPath $verifyPath) {
    (Get-Item -LiteralPath $verifyPath).LastWriteTimeUtc.ToString('o')
  } else { $null }
} | ConvertTo-Json -Depth 4
