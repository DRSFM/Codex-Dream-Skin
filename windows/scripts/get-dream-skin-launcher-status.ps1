[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$RequestPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'common-windows.ps1')

$requestRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'CodexDreamSkinLauncher'
$requestFullPath = [System.IO.Path]::GetFullPath($RequestPath)
if (-not (Test-DreamSkinPathWithin -Path $requestFullPath -Root $requestRoot)) {
  throw 'Launcher status request must stay inside the dedicated temporary directory.'
}
$request = (Read-DreamSkinUtf8File -Path $requestFullPath) | ConvertFrom-Json -ErrorAction Stop
if ($null -eq $request -or [int]$request.schemaVersion -ne 1 -or $request.instances -isnot [array]) {
  throw 'Launcher status request format is unsupported.'
}
$items = @($request.instances)
if ($items.Count -lt 1 -or $items.Count -gt 128) { throw 'Launcher status request count is invalid.' }

$registeredCodexInstalls = @(Get-DreamSkinRegisteredCodexInstalls)
if ($registeredCodexInstalls.Count -eq 0) {
  throw 'The official OpenAI.Codex Store package is not installed or its identity cannot be validated.'
}
$currentCodex = $registeredCodexInstalls[0]
$windowsRoot = Split-Path -Parent $PSScriptRoot
$supportedExtensions = @('.png', '.jpg', '.jpeg', '.webp')
$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf)) {
  throw 'Windows PowerShell is required for the launcher process snapshot.'
}
$snapshotCommand = @'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$listeners = foreach ($line in @(& "$env:SystemRoot\System32\netstat.exe" -ano -p tcp)) {
  if ($line -notmatch '^\s*TCP\s+(?<local>\S+)\s+\S+\s+LISTENING\s+(?<pid>\d+)\s*$') { continue }
  $localEndpoint = $Matches.local
  $pidValue = [int]$Matches.pid
  if ($localEndpoint -match '^\[(?<address>[^\]]+)\]:(?<port>\d+)$') {
    $address = $Matches.address
    $port = [int]$Matches.port
  } elseif ($localEndpoint -match '^(?<address>[^:]+):(?<port>\d+)$') {
    $address = $Matches.address
    $port = [int]$Matches.port
  } else {
    continue
  }
  [pscustomobject]@{
    LocalAddress = $address
    LocalPort = $port
    OwningProcess = $pidValue
  }
}
[pscustomobject]@{
  schemaVersion = 1
  processes = @(Get-WmiObject Win32_Process -Filter "Name = 'ChatGPT.exe'" -ErrorAction Stop |
    Select-Object ProcessId, ParentProcessId, ExecutablePath, CommandLine)
  listeners = @($listeners)
} | ConvertTo-Json -Depth 4 -Compress
'@
$snapshotJson = & $windowsPowerShell -NoProfile -NonInteractive -Command $snapshotCommand
if ($LASTEXITCODE -ne 0) { throw 'Failed to create the launcher process snapshot.' }
$launcherSnapshot = $snapshotJson | ConvertFrom-Json -ErrorAction Stop
if ($null -eq $launcherSnapshot -or [int]$launcherSnapshot.schemaVersion -ne 1) {
  throw 'The launcher process snapshot format is unsupported.'
}
$script:launcherProcessSnapshot = @($launcherSnapshot.processes)
$script:launcherPortListeners = @($launcherSnapshot.listeners)
$script:launcherProcessById = @{}
foreach ($process in $script:launcherProcessSnapshot) {
  $script:launcherProcessById[[int]$process.ProcessId] = $process
}
$script:launcherProcessCache = @{}

function Get-LauncherSnapshotUserDataDir {
  param([Parameter(Mandatory = $true)][object]$ProcessInfo)

  $current = $ProcessInfo
  $visited = @{}
  $expectedPath = Get-DreamSkinProcessExecutablePath -ProcessInfo $ProcessInfo
  while ($null -ne $current -and -not $visited.ContainsKey([int]$current.ProcessId)) {
    $visited[[int]$current.ProcessId] = $true
    $currentPath = Get-DreamSkinProcessExecutablePath -ProcessInfo $current
    if (-not $currentPath -or -not (Test-DreamSkinPathEqual -Left $currentPath -Right $expectedPath)) { break }
    $profile = Get-DreamSkinUserDataDirFromCommandLine -CommandLine "$($current.CommandLine)"
    if ($profile) { return $profile }
    if ([int]$current.ParentProcessId -le 0) { break }
    $current = $script:launcherProcessById[[int]$current.ParentProcessId]
  }
  return $null
}

function Get-LauncherCachedCodexProcesses {
  param(
    [Parameter(Mandatory = $true)][object]$Codex,
    [string]$ProfilePath
  )

  $cacheKey = [System.IO.Path]::GetFullPath("$($Codex.Executable)").ToLowerInvariant()
  if (-not $script:launcherProcessCache.ContainsKey($cacheKey)) {
    $records = @($script:launcherProcessSnapshot |
      Where-Object {
        $processPath = Get-DreamSkinProcessExecutablePath -ProcessInfo $_
        Test-DreamSkinPathEqual -Left $processPath -Right $Codex.Executable
      } |
      ForEach-Object {
        [pscustomobject]@{
          Process = $_
          ProfilePath = Get-LauncherSnapshotUserDataDir -ProcessInfo $_
        }
      })
    $script:launcherProcessCache[$cacheKey] = $records
  }

  $records = @($script:launcherProcessCache[$cacheKey])
  return @($records | Where-Object {
    if (-not $ProfilePath) { return -not $_.ProfilePath }
    return Test-DreamSkinPathEqual -Left $_.ProfilePath -Right $ProfilePath
  } | ForEach-Object { $_.Process })
}

function Test-LauncherCodexPortOwner {
  param(
    [int]$Port,
    [Parameter(Mandatory = $true)][object]$Codex,
    [string]$ProfilePath
  )

  $listeners = @($script:launcherPortListeners | Where-Object { [int]$_.LocalPort -eq $Port })
  if ($listeners.Count -eq 0) { return $false }
  foreach ($listener in $listeners) {
    if ($listener.LocalAddress -notin @('127.0.0.1', '::1')) { return $false }
    $snapshot = $script:launcherProcessById[[int]$listener.OwningProcess]
    $current = Get-Process -Id ([int]$listener.OwningProcess) -ErrorAction SilentlyContinue
    $currentPath = if ($current) { "$($current.Path)" } else { $null }
    $snapshotPath = if ($snapshot) { Get-DreamSkinProcessExecutablePath -ProcessInfo $snapshot } else { $null }
    if (-not $currentPath -or -not $snapshotPath -or
      -not (Test-DreamSkinPathEqual -Left $currentPath -Right $Codex.Executable) -or
      -not (Test-DreamSkinPathEqual -Left $snapshotPath -Right $Codex.Executable)) {
      return $false
    }
    $actualProfile = Get-LauncherSnapshotUserDataDir -ProcessInfo $snapshot
    if ((-not $ProfilePath -and $actualProfile) -or
      ($ProfilePath -and -not (Test-DreamSkinPathEqual -Left $actualProfile -Right $ProfilePath))) {
      return $false
    }
  }
  return $true
}

function Get-LauncherVerifiedCdpIdentity {
  param(
    [int]$Port,
    [Parameter(Mandatory = $true)][object]$Codex,
    [string]$ProfilePath
  )

  if (-not (Test-LauncherCodexPortOwner -Port $Port -Codex $Codex -ProfilePath $ProfilePath)) {
    return $null
  }
  $browser = Get-DreamSkinCdpBrowserIdentity -Port $Port
  if ($null -eq $browser) { return $null }
  $targets = Get-DreamSkinCdpTargets -Port $Port
  if ($targets.Count -eq 0) { return $null }
  if (-not (Test-LauncherCodexPortOwner -Port $Port -Codex $Codex -ProfilePath $ProfilePath)) {
    return $null
  }
  return [pscustomobject]@{
    BrowserId = $browser.BrowserId
    BrowserWebSocketDebuggerUrl = $browser.WebSocketDebuggerUrl
    Browser = $browser.Browser
    TargetCount = $targets.Count
  }
}

$results = foreach ($item in $items) {
  $instanceId = "$($item.instanceId)"
  try {
    Assert-DreamSkinInstanceId -InstanceId $instanceId
    $port = [int]$item.port
    Assert-DreamSkinPort -Port $port
    $profilePath = if ($item.profilePath) {
      [System.IO.Path]::GetFullPath("$($item.profilePath)")
    } else { $null }
    if ($instanceId -cne 'default' -and -not $profilePath) {
      throw 'A non-default status query requires an explicit profile path.'
    }

    $stateRoot = Get-DreamSkinInstanceStateRoot -InstanceId $instanceId
    $customRoot = Get-DreamSkinInstanceCustomRoot -InstanceId $instanceId
    $statePath = Join-Path $stateRoot 'state.json'
    $state = Read-DreamSkinState -Path $statePath
    if ($null -ne $state -and $state.instanceId -and "$($state.instanceId)" -cne $instanceId) {
      throw "Dream Skin state belongs to another instance: $($state.instanceId)"
    }
    if ($null -ne $state -and $state.profilePath) {
      $savedProfilePath = [System.IO.Path]::GetFullPath("$($state.profilePath)")
      if ($profilePath -and -not (Test-DreamSkinPathEqual -Left $profilePath -Right $savedProfilePath)) {
        throw 'The requested profile does not match the saved Dream Skin instance state.'
      }
      if (-not $profilePath) { $profilePath = $savedProfilePath }
    }

    $codexCandidates = @($currentCodex)
    $savedCodex = Resolve-DreamSkinCodexInstallFromState -State $state `
      -RegisteredInstalls $registeredCodexInstalls
    if ($null -ne $savedCodex -and -not (Test-DreamSkinPathEqual `
        -Left $currentCodex.Executable -Right $savedCodex.Executable)) {
      $codexCandidates += $savedCodex
    }
    $desktopProcessIds = @()
    $cdpIdentity = $null
    foreach ($codex in $codexCandidates) {
      $desktopProcessIds += @(Get-LauncherCachedCodexProcesses -Codex $codex `
        -ProfilePath $profilePath | ForEach-Object { [int]$_.ProcessId })
      if ($null -eq $cdpIdentity) {
        $cdpIdentity = Get-LauncherVerifiedCdpIdentity -Port $port -Codex $codex `
          -ProfilePath $profilePath
      }
    }
    $desktopProcessIds = @($desktopProcessIds | Sort-Object -Unique)
    $injectorRunning = $false
    if ($null -ne $state -and $state.injectorPid) {
      $injectorRunning = $null -ne (Get-Process -Id ([int]$state.injectorPid) -ErrorAction SilentlyContinue)
    }
    $skinRunning = $null -ne $cdpIdentity -and $injectorRunning

    $managedImages = @()
    if (Test-Path -LiteralPath $customRoot -PathType Container) {
      $managedImages = @(Get-ChildItem -LiteralPath $customRoot -File -ErrorAction Stop |
        Where-Object {
          $_.BaseName -ceq 'custom-image' -and $_.Extension.ToLowerInvariant() -in $supportedExtensions
        })
    }
    if ($managedImages.Count -gt 1) { throw "Multiple managed backgrounds exist for instance: $instanceId" }
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
    $statusCode = if ($skinRunning) {
      'running'
    } elseif ($desktopProcessIds.Count -gt 0) {
      'desktop-only'
    } elseif ($null -ne $state) {
      'attention'
    } else {
      'stopped'
    }
    [pscustomobject]@{
      instanceId = $instanceId
      error = $null
      status = [pscustomobject]@{
        schemaVersion = 1
        instanceId = $instanceId
        status = $statusCode
        isProtected = $instanceId -ceq 'default'
        desktopRunning = $desktopProcessIds.Count -gt 0
        desktopProcessIds = $desktopProcessIds
        skinRunning = $skinRunning
        cdpVerified = $null -ne $cdpIdentity
        injectorRunning = $injectorRunning
        injectorPid = if ($null -ne $state) { $state.injectorPid } else { $null }
        port = $port
        profilePath = $profilePath
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
      }
    }
  } catch {
    [pscustomobject]@{
      instanceId = $instanceId
      error = $_.Exception.Message
      status = $null
    }
  }
}

[pscustomobject]@{
  schemaVersion = 1
  instances = @($results)
} | ConvertTo-Json -Depth 7
