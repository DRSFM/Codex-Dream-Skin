[CmdletBinding()]
param(
  [int]$Port = 9335,
  [string]$InstanceId = 'default',
  [string]$ScreenshotPath
)

$ErrorActionPreference = 'Stop'
$PortExplicit = $PSBoundParameters.ContainsKey('Port')
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
  if (-not $PortExplicit -and $null -ne $state -and $state.port) { $Port = [int]$state.port }
  Assert-DreamSkinPort -Port $Port
  $ProfilePath = if ($null -ne $state -and $state.profilePath) {
    [System.IO.Path]::GetFullPath("$($state.profilePath)")
  } else {
    $null
  }
  $MatchProfile = $true
  $CustomRoot = if ($null -ne $state -and $state.customRoot) {
    [System.IO.Path]::GetFullPath("$($state.customRoot)")
  } else {
    Get-DreamSkinInstanceCustomRoot -InstanceId $InstanceId
  }
  $expectedCustomRoot = Get-DreamSkinInstanceCustomRoot -InstanceId $InstanceId
  if (-not (Test-DreamSkinPathEqual -Left $CustomRoot -Right $expectedCustomRoot)) {
    throw 'The saved custom root does not match the requested Dream Skin instance.'
  }
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
    throw "No verified Codex CDP endpoint is active on loopback port $Port."
  }
  if ($null -ne $state -and $state.browserId -and "$($state.browserId)" -cne $cdpIdentity.BrowserId) {
    throw 'The active CDP browser does not match the saved Dream Skin session; state was preserved.'
  }

  $arguments = @($injector, '--verify', '--port', "$Port", '--browser-id', $cdpIdentity.BrowserId,
    '--custom-root', $CustomRoot, '--timeout-ms', '30000')
  if ($ScreenshotPath) { $arguments += @('--screenshot', $ScreenshotPath) }
  $savedAuthentication = Suspend-DreamSkinAuthenticationEnvironment
  try {
    & $node.Path @arguments
    $verifyExitCode = $LASTEXITCODE
  } finally {
    Restore-DreamSkinAuthenticationEnvironment -Saved $savedAuthentication
  }
} finally {
  Exit-DreamSkinOperationLock -Mutex $operationLock
}
exit $verifyExitCode
