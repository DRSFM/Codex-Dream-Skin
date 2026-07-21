[CmdletBinding()]
param(
  [int]$Port = 9335,
  [string]$InstanceId = 'default',
  [switch]$Uninstall,
  [switch]$RestoreBaseTheme,
  [switch]$RecoverConfigBackup,
  [switch]$PromptRestart,
  [switch]$ForceRestart,
  [switch]$NoRelaunch
)

$ErrorActionPreference = 'Stop'
$PortExplicit = $PSBoundParameters.ContainsKey('Port')
. (Join-Path $PSScriptRoot 'common-windows.ps1')

$operationLock = Enter-DreamSkinOperationLock
try {
  if ($RestoreBaseTheme -and $RecoverConfigBackup) {
    throw 'Choose either -RestoreBaseTheme or -RecoverConfigBackup, not both.'
  }
  Assert-DreamSkinPort -Port $Port
  Assert-DreamSkinInstanceId -InstanceId $InstanceId
  if ($InstanceId -cne 'default' -and ($Uninstall -or $RestoreBaseTheme -or $RecoverConfigBackup)) {
    throw 'Non-default Dream Skin instances cannot uninstall shared shortcuts or restore the default Codex config.'
  }

  $StateRoot = Get-DreamSkinInstanceStateRoot -InstanceId $InstanceId
  $StatePath = Join-Path $StateRoot 'state.json'
  $state = Read-DreamSkinState -Path $StatePath
  if ($InstanceId -cne 'default' -and $null -eq $state) {
    throw "No state exists for Dream Skin instance: $InstanceId"
  }
  if ($null -ne $state -and $state.instanceId -and "$($state.instanceId)" -cne $InstanceId) {
    throw "Dream Skin state belongs to another instance: $($state.instanceId)"
  }
  $ProfilePath = if ($null -ne $state -and $state.profilePath) {
    [System.IO.Path]::GetFullPath("$($state.profilePath)")
  } else {
    $null
  }
  $MatchProfile = [bool]($InstanceId -cne 'default' -or
    ($null -ne $state -and @($state.PSObject.Properties.Name) -contains 'profilePath'))
  if (-not $PortExplicit -and $null -ne $state -and $state.port) {
    $Port = [int]$state.port
    Assert-DreamSkinPort -Port $Port
  }

  $currentCodex = $null
  try { $currentCodex = Get-DreamSkinCodexInstall } catch { Write-Warning $_.Exception.Message }
  $savedPathCandidate = Get-DreamSkinCodexStatePathCandidate -State $state
  $savedCodex = Get-DreamSkinCodexInstallFromState -State $state
  $candidateMatchesCurrent = [bool]($null -ne $savedPathCandidate -and $null -ne $currentCodex -and
    (Test-DreamSkinPathEqual -Left $savedPathCandidate.PackageRoot -Right $currentCodex.PackageRoot) -and
    (Test-DreamSkinPathEqual -Left $savedPathCandidate.Executable -Right $currentCodex.Executable))
  if ($null -ne $savedPathCandidate -and $null -eq $savedCodex -and -not $candidateMatchesCurrent) {
    $unverifiedSavedRunning = (Get-DreamSkinCodexProcesses -Codex $savedPathCandidate `
      -ProfilePath $ProfilePath -MatchProfile:$MatchProfile).Count -gt 0
    $unverifiedSavedOwnsPort = Test-DreamSkinCodexPortOwner -Port $Port -Codex $savedPathCandidate `
      -ProfilePath $ProfilePath -MatchProfile:$MatchProfile
    if ($unverifiedSavedRunning -or $unverifiedSavedOwnsPort) {
      throw 'The saved Codex path is still active but no longer matches a registered OpenAI.Codex package. Close it manually; state and configuration were preserved.'
    }
  }
  $savedIsDifferent = [bool]($null -ne $savedCodex -and $null -ne $currentCodex -and
    -not (Test-DreamSkinPathEqual -Left $savedCodex.Executable -Right $currentCodex.Executable))
  $currentRunning = $null -ne $currentCodex -and (Get-DreamSkinCodexProcesses -Codex $currentCodex `
    -ProfilePath $ProfilePath -MatchProfile:$MatchProfile).Count -gt 0
  $savedRunning = $null -ne $savedCodex -and (Get-DreamSkinCodexProcesses -Codex $savedCodex `
    -ProfilePath $ProfilePath -MatchProfile:$MatchProfile).Count -gt 0
  $savedOwnsPort = $null -ne $savedCodex -and (Test-DreamSkinCodexPortOwner -Port $Port -Codex $savedCodex `
    -ProfilePath $ProfilePath -MatchProfile:$MatchProfile)
  if ($savedIsDifferent -and $currentRunning -and ($savedRunning -or $savedOwnsPort)) {
    throw 'Multiple Codex package versions are active. Close them manually before restore; state and configuration were preserved.'
  }

  $codex = $currentCodex
  if ($savedRunning -or $savedOwnsPort -or $null -eq $currentCodex) {
    $codex = $savedCodex
    if ($null -ne $codex -and $savedIsDifferent) {
      Write-Warning 'Using the saved Codex package identity to close its older active CDP session.'
    } elseif ($null -ne $codex -and $null -eq $currentCodex) {
      Write-Warning 'Using the saved Codex identity after revalidating it against the registered Store package.'
    }
  }
  $relaunchCodex = if ($null -ne $currentCodex) { $currentCodex } else { $codex }
  $codexRunning = $null -ne $codex -and (Get-DreamSkinCodexProcesses -Codex $codex `
    -ProfilePath $ProfilePath -MatchProfile:$MatchProfile).Count -gt 0
  $portOwnedByCodex = $null -ne $codex -and (Test-DreamSkinCodexPortOwner -Port $Port -Codex $codex `
    -ProfilePath $ProfilePath -MatchProfile:$MatchProfile)
  if ($portOwnedByCodex -and -not $codexRunning) {
    throw 'A Codex-owned listener exists without a manageable Codex process; state was preserved.'
  }
  if ($null -ne $state -and $null -eq $codex -and -not (Test-DreamSkinPortAvailable -Port $Port)) {
    throw "Port $Port is still active, but Codex ownership cannot be verified. State and configuration were preserved."
  }

  $shouldCloseCodex = $codexRunning
  $forceAuthorized = [bool]$ForceRestart
  if ($shouldCloseCodex -and $PromptRestart) {
    $restartMessage = if ($NoRelaunch) {
      'Restore will close Codex and remove Dream Skin plus its CDP session. Continue?'
    } else {
      'Restore will close Codex, remove Dream Skin and its CDP session, then reopen the official app. Continue?'
    }
    $forceAuthorized = Confirm-DreamSkinRestart -Message $restartMessage
    if (-not $forceAuthorized) {
      Write-Host 'Restore was cancelled; no state or configuration was changed.'
      exit 0
    }
  }

  $backup = Join-Path $StateRoot 'config.before-dream-skin.toml'
  $config = Join-Path $HOME '.codex\config.toml'
  if ($RecoverConfigBackup) {
    if (-not (Test-Path -LiteralPath $backup)) { throw 'No pre-install config backup is available.' }
    $null = Read-DreamSkinUtf8File -Path $backup
  } elseif ($RestoreBaseTheme) {
    if (-not (Test-Path -LiteralPath $backup)) { throw 'No pre-install config backup is available.' }
    $null = Read-DreamSkinUtf8File -Path $backup
    $null = Read-DreamSkinUtf8File -Path $config
  }

  $restoreError = $null
  try {
    if ($shouldCloseCodex) {
      Stop-DreamSkinCodex -Codex $codex -ProfilePath $ProfilePath -MatchProfile:$MatchProfile `
        -AllowForce:$forceAuthorized
      if ($portOwnedByCodex -and -not (Wait-DreamSkinPortAvailable -Port $Port -TimeoutSeconds 5)) {
        throw "Port $Port is still listening after Codex closed; state was preserved for inspection."
      }
    }

    $recordedInjectorStopped = Stop-DreamSkinRecordedInjector -State $state
    if (-not $recordedInjectorStopped) {
      $staleStatePath = Archive-DreamSkinStateFile -Path $StatePath
      Write-Warning "Archived stale Dream Skin state at $staleStatePath"
    }

    if ($RecoverConfigBackup) {
      $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N')
      $recoveryBackup = Join-Path $StateRoot "config.before-recovery-$stamp.toml"
      Restore-DreamSkinConfigBackup -ConfigPath $config -BackupPath $backup -RecoveryBackupPath $recoveryBackup
      Write-Host "Recovered the exact pre-install config; previous current config saved at $recoveryBackup"
    } elseif ($RestoreBaseTheme) {
      Restore-DreamSkinBaseTheme -ConfigPath $config -BackupPath $backup
    }
    if ($RecoverConfigBackup -or $RestoreBaseTheme) {
      $archiveStamp = (Get-Date).ToString('yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N')
      $archivePath = Join-Path $StateRoot "config.restored-$archiveStamp.toml"
      Archive-DreamSkinConfigBackup -BackupPath $backup -ArchivePath $archivePath
      Write-Host "Archived the completed pre-install backup at $archivePath"
    }

    Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
    if ($Uninstall) {
      $desktop = [Environment]::GetFolderPath('Desktop')
      $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
      $skillRoot = Split-Path -Parent $PSScriptRoot
      $shortcutRoot = Join-Path $skillRoot 'shortcuts'
      @(
        (Join-Path $desktop 'Codex Dream Skin.lnk'),
        (Join-Path $desktop '安装 Codex Dream Skin.lnk'),
        (Join-Path $desktop 'Codex Dream Skin - Restore.lnk'),
        (Join-Path $desktop '切换 Codex Dream Skin 主题.lnk'),
        (Join-Path $desktop '更换 Codex Dream Skin 图片.lnk'),
        (Join-Path $desktop '恢复 Codex Dream Skin 默认图片.lnk'),
        (Join-Path $startMenu 'Codex Dream Skin.lnk'),
        (Join-Path $startMenu '安装 Codex Dream Skin.lnk'),
        (Join-Path $startMenu 'Codex Dream Skin - Restore.lnk'),
        (Join-Path $startMenu '切换 Codex Dream Skin 主题.lnk'),
        (Join-Path $startMenu '更换 Codex Dream Skin 图片.lnk'),
        (Join-Path $startMenu '恢复 Codex Dream Skin 默认图片.lnk'),
        (Join-Path $shortcutRoot '安装 Codex Dream Skin.lnk'),
        (Join-Path $shortcutRoot 'Codex Dream Skin - Restore.lnk'),
        (Join-Path $shortcutRoot '切换 Codex Dream Skin 主题.lnk'),
        (Join-Path $shortcutRoot '更换 Codex Dream Skin 图片.lnk'),
        (Join-Path $shortcutRoot '恢复 Codex Dream Skin 默认图片.lnk')
      ) | ForEach-Object { Remove-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue }
    }

    if ($shouldCloseCodex -and -not $NoRelaunch) {
      if ($null -eq $relaunchCodex -or -not (Test-Path -LiteralPath $relaunchCodex.Executable)) {
        throw 'Codex cannot be reopened because its current executable is unavailable.'
      }
      Start-DreamSkinCodexProcess -Codex $relaunchCodex -ProfilePath $ProfilePath
    }
  } catch {
    $restoreError = $_
    if ($shouldCloseCodex -and -not $NoRelaunch -and $null -ne $relaunchCodex -and
      (Get-DreamSkinCodexProcesses -Codex $codex -ProfilePath $ProfilePath `
        -MatchProfile:$MatchProfile).Count -eq 0 -and (Test-Path -LiteralPath $relaunchCodex.Executable)) {
      try { Start-DreamSkinCodexProcess -Codex $relaunchCodex -ProfilePath $ProfilePath } catch {
        Write-Warning 'Restore failed and Codex could not be reopened automatically.'
      }
    }
    throw $restoreError
  }

  Write-Host 'Dream Skin restore actions completed; any saved CDP session was closed.'
} finally {
  Exit-DreamSkinOperationLock -Mutex $operationLock
}
