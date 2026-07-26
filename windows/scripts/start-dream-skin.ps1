[CmdletBinding()]
param(
  [int]$Port = 9335,
  [switch]$RestartExisting,
  [switch]$PromptRestart,
  [string]$InstanceId = 'default',
  [string]$ProfilePath,
  [switch]$ForegroundInjector
)

$ErrorActionPreference = 'Stop'
$PortExplicit = $PSBoundParameters.ContainsKey('Port')
$ProfileExplicit = $PSBoundParameters.ContainsKey('ProfilePath')
$Injector = Join-Path $PSScriptRoot 'injector.mjs'
$StartupVerifyTimeoutMs = 60000
. (Join-Path $PSScriptRoot 'common-windows.ps1')

$operationLock = Enter-DreamSkinOperationLock
try {
  Assert-DreamSkinPort -Port $Port
  Assert-DreamSkinInstanceId -InstanceId $InstanceId
  if ($ProfilePath) { $ProfilePath = [System.IO.Path]::GetFullPath($ProfilePath) }
  if ($InstanceId -cne 'default' -and -not $ProfilePath) {
    throw 'A non-default Dream Skin instance requires an explicit -ProfilePath.'
  }
  $node = Get-DreamSkinNodeRuntime
  $currentCodex = Get-DreamSkinCodexInstall
  $codex = $currentCodex
  $StateRoot = Get-DreamSkinInstanceStateRoot -InstanceId $InstanceId
  $CustomRoot = Get-DreamSkinInstanceCustomRoot -InstanceId $InstanceId
  $StatePath = Join-Path $StateRoot 'state.json'
  $StdoutPath = Join-Path $StateRoot 'injector.log'
  $StderrPath = Join-Path $StateRoot 'injector-error.log'
  $VerifyPath = Join-Path $StateRoot 'verify.log'
  New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null

  $previousState = Read-DreamSkinState -Path $StatePath
  if ($null -ne $previousState -and $previousState.instanceId -and
    "$($previousState.instanceId)" -cne $InstanceId) {
    throw "Dream Skin state belongs to another instance: $($previousState.instanceId)"
  }
  if (-not $ProfileExplicit -and $null -ne $previousState -and $previousState.profilePath) {
    $ProfilePath = [System.IO.Path]::GetFullPath("$($previousState.profilePath)")
  }
  # Every instance is profile-scoped. The default instance matches only Codex processes
  # without an explicit user-data-dir, so API Desktop processes are never restarted with it.
  $MatchProfile = $true
  if ($null -ne $previousState -and $previousState.profilePath -and
    -not (Test-DreamSkinPathEqual -Left "$($previousState.profilePath)" -Right $ProfilePath)) {
    throw 'The requested profile does not match the saved Dream Skin instance state.'
  }
  if (-not $PortExplicit -and $null -ne $previousState -and $previousState.port) {
    $savedPort = [int]$previousState.port
    Assert-DreamSkinPort -Port $savedPort
    $Port = $savedPort
  }
  $savedPathCandidate = Get-DreamSkinCodexStatePathCandidate -State $previousState
  $savedCodex = Get-DreamSkinCodexInstallFromState -State $previousState
  $candidateMatchesCurrent = [bool]($null -ne $savedPathCandidate -and
    (Test-DreamSkinPathEqual -Left $savedPathCandidate.PackageRoot -Right $currentCodex.PackageRoot) -and
    (Test-DreamSkinPathEqual -Left $savedPathCandidate.Executable -Right $currentCodex.Executable))
  if ($null -ne $savedPathCandidate -and $null -eq $savedCodex -and -not $candidateMatchesCurrent) {
    $unverifiedSavedRunning = (Get-DreamSkinCodexProcesses -Codex $savedPathCandidate `
      -ProfilePath $ProfilePath -MatchProfile:$MatchProfile).Count -gt 0
    $unverifiedSavedOwnsPort = Test-DreamSkinCodexPortOwner -Port $Port -Codex $savedPathCandidate `
      -ProfilePath $ProfilePath -MatchProfile:$MatchProfile
    if ($unverifiedSavedRunning -or $unverifiedSavedOwnsPort) {
      throw 'The saved Codex path is still active but no longer matches a registered OpenAI.Codex package. Close it manually; state was preserved.'
    }
  }

  $currentProcesses = Get-DreamSkinCodexProcesses -Codex $currentCodex `
    -ProfilePath $ProfilePath -MatchProfile:$MatchProfile
  $codexToStop = $currentCodex
  $cdpIdentity = Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $currentCodex `
    -ProfilePath $ProfilePath -MatchProfile:$MatchProfile
  $savedIsDifferent = [bool]($null -ne $savedCodex -and
    -not (Test-DreamSkinPathEqual -Left $savedCodex.Executable -Right $currentCodex.Executable))
  if ($savedIsDifferent) {
    $savedProcesses = Get-DreamSkinCodexProcesses -Codex $savedCodex `
      -ProfilePath $ProfilePath -MatchProfile:$MatchProfile
    $savedOwnsPort = Test-DreamSkinCodexPortOwner -Port $Port -Codex $savedCodex `
      -ProfilePath $ProfilePath -MatchProfile:$MatchProfile
    if ($currentProcesses.Count -gt 0 -and ($savedProcesses.Count -gt 0 -or $savedOwnsPort)) {
      throw 'Multiple registered Codex package versions are active. Close them manually before starting Dream Skin.'
    }
    if ($savedProcesses.Count -gt 0 -or $savedOwnsPort) {
      if ($savedOwnsPort -and $savedProcesses.Count -eq 0) {
        throw 'The saved Codex listener is active but its process cannot be managed safely; state was preserved.'
      }
      $savedIdentity = Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $savedCodex `
        -ProfilePath $ProfilePath -MatchProfile:$MatchProfile
      if ($null -ne $savedIdentity) {
        $codex = $savedCodex
        $codexToStop = $savedCodex
        $cdpIdentity = $savedIdentity
        Write-Warning 'Reapplying Dream Skin to the still-running registered Codex version; the current Store version will be used after that app exits.'
      } else {
        $codexToStop = $savedCodex
        $currentProcesses = $savedProcesses
      }
    }
  }
  $debugReady = $null -ne $cdpIdentity
  $codexProcesses = if (Test-DreamSkinPathEqual -Left $codexToStop.Executable -Right $currentCodex.Executable) {
    $currentProcesses
  } else {
    Get-DreamSkinCodexProcesses -Codex $codexToStop -ProfilePath $ProfilePath -MatchProfile:$MatchProfile
  }
  $closedExistingCodex = $false
  if (-not $debugReady -and $codexProcesses.Count -gt 0) {
    $restartAuthorized = [bool]$RestartExisting
    if (-not $restartAuthorized -and $PromptRestart) {
      $restartAuthorized = Confirm-DreamSkinRestart -Message 'Codex must restart once to enable Dream Skin. Unsaved input may be lost. Restart now?'
      if (-not $restartAuthorized) {
        Write-Host 'Dream Skin launch was cancelled; Codex was not changed.'
        exit 0
      }
    }
    if (-not $restartAuthorized) {
      throw 'Codex is open without a verified Dream Skin CDP endpoint. Close it first or explicitly use -RestartExisting.'
    }
    Stop-DreamSkinCodex -Codex $codexToStop -ProfilePath $ProfilePath -MatchProfile:$MatchProfile -AllowForce
    $closedExistingCodex = $true
    $codex = $currentCodex
  }

  $launchedWithCdp = $false
  try {
    if ($null -eq (Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $codex `
        -ProfilePath $ProfilePath -MatchProfile:$MatchProfile)) {
      if (-not (Test-DreamSkinPortAvailable -Port $Port)) {
        if ($PortExplicit) { throw "Port $Port is already occupied by an unverified listener. Choose another port." }
        $Port = Select-DreamSkinPort -PreferredPort $Port
      }
      Start-DreamSkinCodexProcess -Codex $codex -ProfilePath $ProfilePath -Port $Port -EnableCdp
      $launchedWithCdp = $true
    }

    $deadline = (Get-Date).AddSeconds(45)
    $cdpIdentity = Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $codex `
      -ProfilePath $ProfilePath -MatchProfile:$MatchProfile
    while ($null -eq $cdpIdentity) {
      if ((Get-Date) -ge $deadline) {
        throw "Codex did not expose a verified loopback CDP endpoint on port $Port within 45 seconds."
      }
      Start-Sleep -Milliseconds 400
      $cdpIdentity = Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $codex `
        -ProfilePath $ProfilePath -MatchProfile:$MatchProfile
    }
  } catch {
    $launchError = $_
    if ($launchedWithCdp) {
      try {
        Stop-DreamSkinCodex -Codex $codex -ProfilePath $ProfilePath -MatchProfile:$MatchProfile -AllowForce
      } catch {
        Write-Warning 'Launch rollback could not fully close the failed CDP session.'
      }
    }
    if (($closedExistingCodex -or $launchedWithCdp) -and
      (Get-DreamSkinCodexProcesses -Codex $codex -ProfilePath $ProfilePath `
        -MatchProfile:$MatchProfile).Count -eq 0) {
      if ($launchedWithCdp) {
        Write-Warning 'Dream Skin launch failed; reopening Codex without a debugging port.'
      }
      try { Start-DreamSkinCodexProcess -Codex $codex -ProfilePath $ProfilePath } catch {
        Write-Warning 'Launch rollback could not reopen Codex automatically.'
      }
    }
    throw $launchError
  }

  try {
    $recordedInjectorStopped = Stop-DreamSkinRecordedInjector -State $previousState
    if (-not $recordedInjectorStopped) {
      $staleStatePath = Archive-DreamSkinStateFile -Path $StatePath
      Write-Warning "Archived stale Dream Skin state at $staleStatePath"
    }
  } catch {
    if ($launchedWithCdp) {
      try {
        Stop-DreamSkinCodex -Codex $codex -ProfilePath $ProfilePath -MatchProfile:$MatchProfile -AllowForce
        Start-DreamSkinCodexProcess -Codex $codex -ProfilePath $ProfilePath
      } catch {
        Write-Warning 'State validation rollback could not fully restart Codex; close Codex to ensure its CDP port is closed.'
      }
    }
    throw
  }

  if ($ForegroundInjector) {
    Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
    Exit-DreamSkinOperationLock -Mutex $operationLock
    $operationLock = $null
    $savedAuthentication = Suspend-DreamSkinAuthenticationEnvironment
    try {
      & $node.Path $Injector --watch --port $Port --browser-id $cdpIdentity.BrowserId `
        --custom-root $CustomRoot
      $foregroundExitCode = $LASTEXITCODE
    } finally {
      Restore-DreamSkinAuthenticationEnvironment -Saved $savedAuthentication
    }
    exit $foregroundExitCode
  }

  $state = $null
  $daemon = $null
  try {
    $injectorArgs = @((ConvertTo-DreamSkinProcessArgument -Value $Injector), '--watch', '--port', "$Port",
      '--browser-id', $cdpIdentity.BrowserId, '--custom-root',
      (ConvertTo-DreamSkinProcessArgument -Value $CustomRoot))
    $savedAuthentication = Suspend-DreamSkinAuthenticationEnvironment
    try {
      $daemon = Start-Process -FilePath $node.Path -ArgumentList $injectorArgs -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath
    } finally {
      Restore-DreamSkinAuthenticationEnvironment -Saved $savedAuthentication
    }
    Start-Sleep -Milliseconds 500
    if ($daemon.HasExited) { throw "The injector exited during startup. See $StderrPath" }

    $injectorStartedAt = Get-DreamSkinProcessStartedAt -ProcessId $daemon.Id
    if (-not $injectorStartedAt) { throw 'The injector process identity could not be recorded safely.' }
    $state = [pscustomobject]@{
      schemaVersion = 3
      platform = 'windows'
      instanceId = $InstanceId
      port = $Port
      injectorPid = $daemon.Id
      injectorStartedAt = $injectorStartedAt
      injectorPath = $Injector
      nodePath = $node.Path
      nodeVersion = $node.Version
      codexExe = $codex.Executable
      codexPackageRoot = $codex.PackageRoot
      codexPackageFullName = $codex.PackageFullName
      codexPackageFamilyName = $codex.PackageFamilyName
      codexVersion = $codex.Version
      browserId = $cdpIdentity.BrowserId
      profilePath = $ProfilePath
      customRoot = $CustomRoot
      createdAt = (Get-Date).ToUniversalTime().ToString('o')
    }
    Write-DreamSkinState -Path $StatePath -State $state

    $savedAuthentication = Suspend-DreamSkinAuthenticationEnvironment
    try {
      $verifyOutput = @(& $node.Path $Injector --verify --port $Port --browser-id $cdpIdentity.BrowserId `
        --custom-root $CustomRoot --timeout-ms $StartupVerifyTimeoutMs 2>&1)
      $verifyExitCode = $LASTEXITCODE
    } finally {
      Restore-DreamSkinAuthenticationEnvironment -Saved $savedAuthentication
    }
    Write-DreamSkinUtf8FileAtomically -Path $VerifyPath -Content (($verifyOutput -join "`r`n") + "`r`n")
    if ($verifyExitCode -ne 0) { throw "Dream Skin verification failed. See $VerifyPath" }
  } catch {
    $startupError = $_
    $injectorStopped = $true
    if ($null -ne $state) {
      try {
        $injectorStopped = Stop-DreamSkinRecordedInjector -State $state
      } catch {
        $injectorStopped = $false
        Write-Warning $_.Exception.Message
      }
    } elseif ($null -ne $daemon -and -not $daemon.HasExited) {
      try {
        Stop-Process -InputObject $daemon -Force -ErrorAction Stop
        [void]$daemon.WaitForExit(5000)
        $injectorStopped = $daemon.HasExited
      } catch {
        $injectorStopped = $false
        Write-Warning 'The newly created injector could not be stopped during startup rollback.'
      }
    }
    if ($injectorStopped -and -not $launchedWithCdp) {
      try {
        $rollbackIdentity = Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $codex `
          -ProfilePath $ProfilePath -MatchProfile:$MatchProfile
        if ($null -ne $rollbackIdentity -and $rollbackIdentity.BrowserId -ceq $cdpIdentity.BrowserId) {
          & $node.Path $Injector --remove --port $Port --browser-id $cdpIdentity.BrowserId `
            --timeout-ms 5000 *> $null
          if ($LASTEXITCODE -ne 0) { throw 'Injector removal returned a failure status.' }
        }
      } catch {
        Write-Warning 'Startup rollback could not remove the partially applied live skin; reload or close Codex to clear it.'
      }
    }
    if ($injectorStopped) { Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue }
    if ($launchedWithCdp) {
      try {
        Stop-DreamSkinCodex -Codex $codex -ProfilePath $ProfilePath -MatchProfile:$MatchProfile -AllowForce
        Start-DreamSkinCodexProcess -Codex $codex -ProfilePath $ProfilePath
      } catch {
        Write-Warning 'Startup rollback could not fully restart Codex; close Codex to ensure its CDP port is closed.'
      }
    }
    throw $startupError
  }

  Write-Host "Codex Dream Skin is active on verified loopback port $Port."
} finally {
  if ($null -ne $operationLock) { Exit-DreamSkinOperationLock -Mutex $operationLock }
}
