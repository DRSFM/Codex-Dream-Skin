[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$InstanceId,
  [int]$Port = 9335,
  [string]$ProfilePath,
  [switch]$AllowForce
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')

Assert-DreamSkinInstanceId -InstanceId $InstanceId
Assert-DreamSkinPort -Port $Port
if ($ProfilePath) { $ProfilePath = [System.IO.Path]::GetFullPath($ProfilePath) }
if ($InstanceId -cne 'default' -and -not $ProfilePath) {
  throw 'A non-default stop requires an explicit -ProfilePath.'
}

$operationLock = Enter-DreamSkinOperationLock
try {
  $codex = Get-DreamSkinCodexInstall
  $matching = @(Get-DreamSkinCodexProcesses -Codex $codex -ProfilePath $ProfilePath -MatchProfile)
  if ($matching.Count -eq 0) {
    Write-Host "No running Codex Desktop process matched instance: $InstanceId"
    return
  }

  Stop-DreamSkinCodex -Codex $codex -ProfilePath $ProfilePath -MatchProfile -AllowForce:$AllowForce
  Write-Host "Stopped Codex Desktop instance: $InstanceId"
} finally {
  Exit-DreamSkinOperationLock -Mutex $operationLock
}
