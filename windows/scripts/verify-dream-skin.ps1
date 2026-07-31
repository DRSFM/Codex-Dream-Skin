[CmdletBinding()]
param(
  [int]$Port = 9335,
  [string]$InstanceId = 'default',
  [string]$ProfilePath,
  [string]$ScreenshotPath
)

$ErrorActionPreference = 'Stop'
$PortExplicit = $PSBoundParameters.ContainsKey('Port')
$ProfileExplicit = $PSBoundParameters.ContainsKey('ProfilePath')
$injector = Join-Path $PSScriptRoot 'injector.mjs'
. (Join-Path $PSScriptRoot 'common-windows.ps1')

$operationLock = Enter-DreamSkinOperationLock
$verifyExitCode = 1
try {
  Assert-DreamSkinInstanceId -InstanceId $InstanceId
  $StateRoot = Get-DreamSkinInstanceStateRoot -InstanceId $InstanceId
  $StatePath = Join-Path $StateRoot 'state.json'
  $state = Read-DreamSkinState -Path $StatePath
  if ($null -ne $state -and $state.instanceId -and "$($state.instanceId)" -cne $InstanceId) {
    throw "Dream Skin state belongs to another instance: $($state.instanceId)"
  }
  if (-not $ProfileExplicit -and $null -ne $state -and $state.profilePath) {
    $ProfilePath = [System.IO.Path]::GetFullPath("$($state.profilePath)")
  } elseif ($ProfilePath) {
    $ProfilePath = [System.IO.Path]::GetFullPath($ProfilePath)
  }
  if ($InstanceId -cne 'default' -and -not $ProfilePath) {
    throw 'A non-default Dream Skin verify requires an explicit or saved profile path.'
  }
  if ($null -ne $state -and $state.profilePath -and
    -not (Test-DreamSkinPathEqual -Left "$($state.profilePath)" -Right $ProfilePath)) {
    throw 'The requested profile does not match the saved Dream Skin instance state.'
  }
  $MatchProfile = $true
  if (-not $PortExplicit -and $null -ne $state -and $state.port) { $Port = [int]$state.port }
  Assert-DreamSkinPort -Port $Port
  $node = Get-DreamSkinNodeRuntime
  $currentCodex = Get-DreamSkinCodexInstall
  $codex = $currentCodex
  $cdpIdentity = Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $codex `
    -ProfilePath $ProfilePath -MatchProfile:$MatchProfile
  if ($null -eq $cdpIdentity -and $null -ne $state) {
    $savedCodex = Get-DreamSkinCodexInstallFromState -State $state
    if ($null -ne $savedCodex -and
      -not (Test-DreamSkinPathEqual -Left $savedCodex.Executable -Right $currentCodex.Executable)) {
      $savedIdentity = Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $savedCodex `
        -ProfilePath $ProfilePath -MatchProfile:$MatchProfile
      if ($null -ne $savedIdentity) {
        $codex = $savedCodex
        $cdpIdentity = $savedIdentity
      }
    }
  }
  if ($null -eq $cdpIdentity) {
    # A Store auto-update replaces the "current" package while an older
    # registered version still owns the verified endpoint.
    $runningRegistered = Get-DreamSkinVerifiedCdpIdentityForAnyRegistered -Port $Port `
      -ProfilePath $ProfilePath -MatchProfile:$MatchProfile
    if ($null -ne $runningRegistered) {
      $codex = $runningRegistered.Codex
      $cdpIdentity = $runningRegistered.Identity
    }
  }
  if ($null -eq $cdpIdentity) {
    throw "No verified Codex CDP endpoint is active on loopback port $Port."
  }
  if ($null -ne $state -and $state.browserId -and "$($state.browserId)" -cne $cdpIdentity.BrowserId) {
    throw 'The active CDP browser does not match the saved Dream Skin session; state was preserved.'
  }

  # Without an explicit --theme-dir the injector falls back to the engine's
  # bundled assets theme, so verification compares the live skin against the
  # wrong expected theme and never passes.  Always verify against the staged
  # active theme, exactly like the watcher applies it.
  $themePaths = Get-DreamSkinThemePaths -StateRoot $StateRoot
  $arguments = @($injector, '--verify', '--port', "$Port", '--browser-id', $cdpIdentity.BrowserId,
    '--theme-dir', $themePaths.Active, '--timeout-ms', '30000')
  if ($ScreenshotPath) { $arguments += @('--screenshot', $ScreenshotPath) }
  & $node.Path @arguments
  $verifyExitCode = $LASTEXITCODE
} finally {
  Exit-DreamSkinOperationLock -Mutex $operationLock
}
exit $verifyExitCode
