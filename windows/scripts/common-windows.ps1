. (Join-Path $PSScriptRoot 'config-utf8.ps1')

function Enter-DreamSkinOperationLock {
  $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $mutex = [System.Threading.Mutex]::new($false, "Local\CodexDreamSkin.$sid.Operation")
  $acquired = $false
  try {
    $acquired = $mutex.WaitOne(0)
  } catch [System.Threading.AbandonedMutexException] {
    $acquired = $true
  }
  if (-not $acquired) {
    $mutex.Dispose()
    throw 'Another Codex Dream Skin install, start, restore, or verify operation is already running.'
  }
  return $mutex
}

function Exit-DreamSkinOperationLock {
  param([Parameter(Mandatory = $true)][System.Threading.Mutex]$Mutex)
  try { $Mutex.ReleaseMutex() } finally { $Mutex.Dispose() }
}

function Assert-DreamSkinPort {
  param([Parameter(Mandatory = $true)][int]$Port)
  if ($Port -lt 1024 -or $Port -gt 65535) { throw "Port must be between 1024 and 65535: $Port" }
}

function Assert-DreamSkinInstanceId {
  param([Parameter(Mandatory = $true)][string]$InstanceId)
  if (-not $InstanceId -or $InstanceId -cnotmatch '^[a-z0-9][a-z0-9-]{0,63}$') {
    throw "Instance ID is unsafe: $InstanceId"
  }
}

function Get-DreamSkinInstanceStateRoot {
  param([Parameter(Mandatory = $true)][string]$InstanceId)
  Assert-DreamSkinInstanceId -InstanceId $InstanceId
  $baseRoot = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'
  if ($InstanceId -ceq 'default') { return $baseRoot }
  return Join-Path $baseRoot (Join-Path 'instances' $InstanceId)
}

function Get-DreamSkinInstanceCustomRoot {
  param([Parameter(Mandatory = $true)][string]$InstanceId)
  return Join-Path (Get-DreamSkinInstanceStateRoot -InstanceId $InstanceId) 'custom'
}

$script:DreamSkinAuthenticationEnvironmentNames = @(
  'APICODEX_API_KEY',
  'OPENAI_API_KEY',
  'CODEX_API_KEY',
  'CODEX_AUTH_TOKEN',
  'OPENAI_AUTH_TOKEN'
)

function Suspend-DreamSkinAuthenticationEnvironment {
  $saved = @{}
  foreach ($name in $script:DreamSkinAuthenticationEnvironmentNames) {
    $entry = Get-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
    if ($null -ne $entry) {
      $saved[$name] = $entry.Value
      Remove-Item -LiteralPath "Env:$name" -ErrorAction Stop
    }
  }
  return $saved
}

function Restore-DreamSkinAuthenticationEnvironment {
  param([Parameter(Mandatory = $true)][hashtable]$Saved)
  foreach ($name in $script:DreamSkinAuthenticationEnvironmentNames) {
    Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
  }
  foreach ($name in $Saved.Keys) {
    Set-Item -LiteralPath "Env:$name" -Value "$($Saved[$name])" -ErrorAction Stop
  }
}

function Test-DreamSkinPathEqual {
  param([string]$Left, [string]$Right)
  if (-not $Left -or -not $Right) { return $false }
  try {
    return ([System.IO.Path]::GetFullPath($Left).TrimEnd('\') -ieq [System.IO.Path]::GetFullPath($Right).TrimEnd('\'))
  } catch {
    return $false
  }
}

function Test-DreamSkinPathWithin {
  param([string]$Path, [string]$Root)
  if (-not $Path -or -not $Root) { return $false }
  try {
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $prefix = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    return $fullPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
  } catch {
    return $false
  }
}

function Test-DreamSkinCommandLineToken {
  param([string]$CommandLine, [string]$Token)
  if (-not $CommandLine -or -not $Token) { return $false }
  $pattern = '(?i)(?:^|[\s"])' + [regex]::Escape($Token) + '(?=$|[\s"])'
  return [regex]::IsMatch($CommandLine, $pattern)
}

function ConvertTo-DreamSkinProcessArgument {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
  if ($Value.Contains('"')) { throw 'Process arguments containing a double quote are not supported.' }
  if ($Value -notmatch '\s') { return $Value }
  $escaped = [regex]::Replace($Value, '(\\+)$', '$1$1')
  return '"' + $escaped + '"'
}

function Start-DreamSkinCodexProcess {
  param(
    [Parameter(Mandatory = $true)][object]$Codex,
    [string]$ProfilePath,
    [int]$Port,
    [switch]$EnableCdp
  )
  $arguments = @()
  if ($EnableCdp) {
    Assert-DreamSkinPort -Port $Port
    $arguments += @('--remote-debugging-address=127.0.0.1', "--remote-debugging-port=$Port")
  }
  if ($ProfilePath) {
    New-Item -ItemType Directory -Force -Path $ProfilePath | Out-Null
    $arguments += ConvertTo-DreamSkinProcessArgument -Value "--user-data-dir=$ProfilePath"
  }
  if ($arguments.Count -gt 0) {
    Start-Process -FilePath $Codex.Executable -ArgumentList $arguments | Out-Null
  } else {
    Start-Process -FilePath $Codex.Executable | Out-Null
  }
}

function Get-DreamSkinProcessExecutablePath {
  param([Parameter(Mandatory = $true)][object]$ProcessInfo)
  if ($ProcessInfo.ExecutablePath) { return "$($ProcessInfo.ExecutablePath)" }
  try {
    $process = Get-Process -Id ([int]$ProcessInfo.ProcessId) -ErrorAction Stop
    if ($process.Path) { return "$($process.Path)" }
    return "$($process.MainModule.FileName)"
  } catch {
    return $null
  }
}

function Get-DreamSkinUserDataDirFromCommandLine {
  param([string]$CommandLine)
  if (-not $CommandLine) { return $null }
  $match = [regex]::Match($CommandLine, '(?i)(?:^|\s)--user-data-dir(?:=|\s+)(?:"(?<quoted>[^"]+)"|(?<bare>[^\s]+))(?=$|\s)')
  if (-not $match.Success) { return $null }
  $value = if ($match.Groups['quoted'].Success) { $match.Groups['quoted'].Value } else { $match.Groups['bare'].Value }
  try { return [System.IO.Path]::GetFullPath($value).TrimEnd('\') } catch { return $value }
}

function Get-DreamSkinProcessUserDataDir {
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
    $current = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$current.ParentProcessId)" -ErrorAction SilentlyContinue
  }
  return $null
}

function Test-DreamSkinProcessProfile {
  param(
    [Parameter(Mandatory = $true)][object]$ProcessInfo,
    [string]$ProfilePath,
    [switch]$MatchProfile
  )
  if (-not $MatchProfile) { return $true }
  $actual = Get-DreamSkinProcessUserDataDir -ProcessInfo $ProcessInfo
  if (-not $ProfilePath) { return -not $actual }
  return Test-DreamSkinPathEqual -Left $actual -Right $ProfilePath
}

function Get-DreamSkinNodeRuntime {
  param([int]$MinimumMajor = 22)

  $command = Get-Command node.exe -ErrorAction SilentlyContinue
  if (-not $command) { $command = Get-Command node -ErrorAction SilentlyContinue }
  if (-not $command) { throw "Node.js $MinimumMajor or newer is required and was not found in PATH." }
  $version = "$(& $command.Source -p 'process.versions.node' 2>$null)".Trim()
  if ($LASTEXITCODE -ne 0 -or -not $version) { throw 'The Node.js runtime could not be validated.' }
  $runtimePath = "$(& $command.Source -p 'process.execPath' 2>$null)".Trim()
  if ($LASTEXITCODE -ne 0 -or -not $runtimePath -or -not (Test-Path -LiteralPath $runtimePath)) {
    throw 'The Node.js executable path could not be validated.'
  }
  $major = 0
  if (-not [int]::TryParse(($version -split '\.')[0], [ref]$major) -or $major -lt $MinimumMajor) {
    throw "Node.js $MinimumMajor or newer is required; found $version at $runtimePath."
  }
  return [pscustomobject]@{ Path = $runtimePath; Version = $version; Major = $major }
}

function ConvertTo-DreamSkinCodexInstall {
  param([Parameter(Mandatory = $true)][object]$Package)
  if ("$($Package.Name)" -ine 'OpenAI.Codex' -or -not $Package.InstallLocation -or
    -not $Package.PackageFullName -or -not $Package.PackageFamilyName -or
    "$($Package.SignatureKind)" -ine 'Store' -or [bool]$Package.IsDevelopmentMode) {
    return $null
  }
  $packageRoot = "$($Package.InstallLocation)"
  $executable = Join-Path $packageRoot 'app\ChatGPT.exe'
  if (-not (Test-Path -LiteralPath $executable)) { return $null }
  return [pscustomobject]@{
    PackageRoot = $packageRoot
    Executable = $executable
    Version = "$($Package.Version)"
    PackageFullName = "$($Package.PackageFullName)"
    PackageFamilyName = "$($Package.PackageFamilyName)"
    SignatureKind = "$($Package.SignatureKind)"
  }
}

function Get-DreamSkinRegisteredCodexInstalls {
  $packages = @(Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction Stop | Sort-Object Version -Descending)
  $installs = @()
  foreach ($package in $packages) {
    $install = ConvertTo-DreamSkinCodexInstall -Package $package
    if ($null -ne $install) { $installs += $install }
  }
  return $installs
}

function Get-DreamSkinCodexInstall {
  $installs = @(Get-DreamSkinRegisteredCodexInstalls)
  if ($installs.Count -eq 0) { throw 'The official OpenAI.Codex Store package is not installed or its identity cannot be validated.' }
  return $installs[0]
}

function Get-DreamSkinCodexStatePathCandidate {
  param([AllowNull()][object]$State)
  if ($null -eq $State -or -not $State.codexExe -or -not $State.codexPackageRoot) { return $null }
  $executable = "$($State.codexExe)"
  $packageRoot = "$($State.codexPackageRoot)"
  $expectedExecutable = Join-Path $packageRoot 'app\ChatGPT.exe'
  if (-not (Test-DreamSkinPathEqual -Left $executable -Right $expectedExecutable)) { return $null }
  return [pscustomobject]@{
    PackageRoot = $packageRoot
    Executable = $executable
    Version = "$($State.codexVersion)"
    FromState = $true
    RegisteredPackageVerified = $false
  }
}

function Resolve-DreamSkinCodexInstallFromState {
  param(
    [AllowNull()][object]$State,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$RegisteredInstalls
  )
  $candidate = Get-DreamSkinCodexStatePathCandidate -State $State
  if ($null -eq $candidate) { return $null }

  $hasFullName = [bool]$State.codexPackageFullName
  $hasFamilyName = [bool]$State.codexPackageFamilyName
  if ($hasFullName -xor $hasFamilyName) { return $null }
  foreach ($install in $RegisteredInstalls) {
    $pathMatches = (Test-DreamSkinPathEqual -Left $candidate.PackageRoot -Right $install.PackageRoot) -and
      (Test-DreamSkinPathEqual -Left $candidate.Executable -Right $install.Executable)
    if (-not $pathMatches) { continue }
    if ($hasFullName -and ("$($State.codexPackageFullName)" -ine $install.PackageFullName -or
      "$($State.codexPackageFamilyName)" -ine $install.PackageFamilyName)) {
      continue
    }
    return [pscustomobject]@{
      PackageRoot = $install.PackageRoot
      Executable = $install.Executable
      Version = $install.Version
      PackageFullName = $install.PackageFullName
      PackageFamilyName = $install.PackageFamilyName
      SignatureKind = $install.SignatureKind
      FromState = $true
      RegisteredPackageVerified = $true
    }
  }
  return $null
}

function Get-DreamSkinCodexInstallFromState {
  param([AllowNull()][object]$State)
  try { $installs = @(Get-DreamSkinRegisteredCodexInstalls) } catch { return $null }
  return Resolve-DreamSkinCodexInstallFromState -State $State -RegisteredInstalls $installs
}

function Test-DreamSkinWebSocketUrl {
  param([string]$Value, [int]$Port)
  try {
    $uri = [Uri]$Value
    $hostName = $uri.Host.ToLowerInvariant()
    return ($uri.IsAbsoluteUri -and $uri.Scheme -eq 'ws' -and $uri.Port -eq $Port -and
      $hostName -in @('127.0.0.1', 'localhost', '::1', '[::1]') -and -not $uri.UserInfo -and
      -not $uri.Query -and -not $uri.Fragment -and
      $uri.AbsolutePath -cmatch '^/devtools/(?:page|browser)/[A-Za-z0-9._-]{1,200}$')
  } catch {
    return $false
  }
}

function Test-DreamSkinCdpPageTarget {
  param([AllowNull()][object]$Target, [int]$Port)
  if ($null -eq $Target -or "$($Target.type)" -cne 'page' -or
    "$($Target.url)" -notlike 'app://*') {
    return $false
  }
  if ($Target.id -isnot [string]) { return $false }
  $targetId = "$($Target.id)"
  $webSocketUrl = "$($Target.webSocketDebuggerUrl)"
  if (-not (Test-DreamSkinBrowserId -Value $targetId) -or
    -not (Test-DreamSkinWebSocketUrl -Value $webSocketUrl -Port $Port)) {
    return $false
  }
  try {
    return ([Uri]$webSocketUrl).AbsolutePath -ceq "/devtools/page/$targetId"
  } catch {
    return $false
  }
}

function Get-DreamSkinCdpTargets {
  param([int]$Port)
  try {
    $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/list" -TimeoutSec 2 `
      -MaximumRedirection 0 -ErrorAction Stop
    return @($targets | Where-Object { Test-DreamSkinCdpPageTarget -Target $_ -Port $Port })
  } catch {
    return @()
  }
}

function Test-DreamSkinBrowserId {
  param([string]$Value)
  return [bool]($Value -and $Value.Length -le 200 -and $Value -cmatch '^[A-Za-z0-9._-]+$')
}

function Get-DreamSkinCdpBrowserIdentity {
  param([int]$Port)
  try {
    $version = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/version" -TimeoutSec 2 `
      -MaximumRedirection 0 -ErrorAction Stop
    $webSocketUrl = "$($version.webSocketDebuggerUrl)"
    if (-not (Test-DreamSkinWebSocketUrl -Value $webSocketUrl -Port $Port)) { return $null }
    $uri = [Uri]$webSocketUrl
    $match = [regex]::Match($uri.AbsolutePath, '^/devtools/browser/(?<id>[A-Za-z0-9._-]{1,200})$')
    if (-not $match.Success -or $uri.Query -or $uri.Fragment) { return $null }
    $browserId = $match.Groups['id'].Value
    if (-not (Test-DreamSkinBrowserId -Value $browserId)) { return $null }
    return [pscustomobject]@{
      BrowserId = $browserId
      WebSocketDebuggerUrl = $webSocketUrl
      Browser = "$($version.Browser)"
    }
  } catch {
    return $null
  }
}

function Get-DreamSkinPortListeners {
  param([int]$Port)
  if (-not (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) {
    throw 'Get-NetTCPConnection is required to verify CDP listener ownership.'
  }
  return @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
}

function Test-DreamSkinPortAvailable {
  param([int]$Port)
  return (Get-DreamSkinPortListeners -Port $Port).Count -eq 0
}

function Test-DreamSkinCodexPortOwner {
  param(
    [int]$Port,
    [Parameter(Mandatory = $true)][object]$Codex,
    [string]$ProfilePath,
    [switch]$MatchProfile
  )
  $listeners = Get-DreamSkinPortListeners -Port $Port
  if ($listeners.Count -eq 0) { return $false }
  foreach ($listener in $listeners) {
    if ($listener.LocalAddress -notin @('127.0.0.1', '::1')) { return $false }
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$listener.OwningProcess)" -ErrorAction SilentlyContinue
    $processPath = if ($process) { Get-DreamSkinProcessExecutablePath -ProcessInfo $process } else { $null }
    if (-not $processPath -or -not (Test-DreamSkinPathEqual -Left $processPath -Right $Codex.Executable) -or
      -not (Test-DreamSkinProcessProfile -ProcessInfo $process -ProfilePath $ProfilePath -MatchProfile:$MatchProfile)) {
      return $false
    }
  }
  return $true
}

function Get-DreamSkinVerifiedCdpIdentity {
  param(
    [int]$Port,
    [Parameter(Mandatory = $true)][object]$Codex,
    [string]$ProfilePath,
    [switch]$MatchProfile
  )
  if (-not (Test-DreamSkinCodexPortOwner -Port $Port -Codex $Codex -ProfilePath $ProfilePath -MatchProfile:$MatchProfile)) {
    return $null
  }
  $browser = Get-DreamSkinCdpBrowserIdentity -Port $Port
  if ($null -eq $browser) { return $null }
  $targets = Get-DreamSkinCdpTargets -Port $Port
  if ($targets.Count -eq 0) { return $null }
  if (-not (Test-DreamSkinCodexPortOwner -Port $Port -Codex $Codex -ProfilePath $ProfilePath -MatchProfile:$MatchProfile)) {
    return $null
  }
  return [pscustomobject]@{
    BrowserId = $browser.BrowserId
    BrowserWebSocketDebuggerUrl = $browser.WebSocketDebuggerUrl
    Browser = $browser.Browser
    TargetCount = $targets.Count
  }
}

function Test-DreamSkinCodexCdpEndpoint {
  param(
    [int]$Port,
    [Parameter(Mandatory = $true)][object]$Codex,
    [string]$ProfilePath,
    [switch]$MatchProfile
  )
  return $null -ne (Get-DreamSkinVerifiedCdpIdentity -Port $Port -Codex $Codex `
    -ProfilePath $ProfilePath -MatchProfile:$MatchProfile)
}

function Select-DreamSkinPort {
  param([int]$PreferredPort)
  for ($candidate = $PreferredPort; $candidate -le [Math]::Min(65535, $PreferredPort + 100); $candidate++) {
    if (Test-DreamSkinPortAvailable -Port $candidate) { return $candidate }
  }
  throw "No free loopback port was found between $PreferredPort and $([Math]::Min(65535, $PreferredPort + 100))."
}

function Wait-DreamSkinPortAvailable {
  param([int]$Port, [int]$TimeoutSeconds = 5)
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    if (Test-DreamSkinPortAvailable -Port $Port) { return $true }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $deadline)
  return $false
}

function Read-DreamSkinState {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  try {
    $state = (Read-DreamSkinUtf8File -Path $Path) | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $state -or $state -is [string] -or $state -is [array]) { throw 'State root must be an object.' }
    foreach ($timestampProperty in @('injectorStartedAt', 'createdAt')) {
      if ($state.PSObject.Properties.Name -contains $timestampProperty) {
        if ($state.$timestampProperty -is [DateTime]) {
          $state.$timestampProperty = $state.$timestampProperty.ToUniversalTime().ToString('o')
        } elseif ($state.$timestampProperty -is [DateTimeOffset]) {
          $state.$timestampProperty = $state.$timestampProperty.ToUniversalTime().ToString('o')
        }
      }
    }
    $properties = @($state.PSObject.Properties.Name)
    if ($properties -contains 'platform' -and "$($state.platform)" -ine 'windows') {
      throw 'State platform is not Windows.'
    }
    $schemaVersion = 1
    if ($properties -contains 'schemaVersion') {
      $schemaVersion = 0
      if (-not [int]::TryParse("$($state.schemaVersion)", [ref]$schemaVersion) -or
        $schemaVersion -lt 1 -or $schemaVersion -gt 3) {
        throw 'State schema is not supported.'
      }
    }
    if ($schemaVersion -ge 3) {
      foreach ($required in @(
        'platform', 'port', 'injectorPid', 'injectorStartedAt', 'injectorPath', 'nodePath',
        'codexExe', 'codexPackageRoot', 'codexPackageFullName', 'codexPackageFamilyName', 'browserId'
      )) {
        if ($properties -notcontains $required -or -not $state.$required) {
          throw "State schema 3 is missing required field: $required"
        }
      }
    }
    if ($properties -contains 'port') {
      $statePort = 0
      if (-not [int]::TryParse("$($state.port)", [ref]$statePort)) { throw 'State port is invalid.' }
      Assert-DreamSkinPort -Port $statePort
    }
    if ($properties -contains 'injectorPid' -and $null -ne $state.injectorPid) {
      $statePid = 0
      if (-not [int]::TryParse("$($state.injectorPid)", [ref]$statePid) -or $statePid -le 0) {
        throw 'State injector PID is invalid.'
      }
    }
    if ($properties -contains 'browserId' -and $state.browserId -and
      -not (Test-DreamSkinBrowserId -Value "$($state.browserId)")) {
      throw 'State browser ID is invalid.'
    }
    return $state
  } catch {
    throw "Dream Skin state is unreadable; it was preserved for inspection: $Path"
  }
}

function Write-DreamSkinState {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$State)
  $json = $State | ConvertTo-Json -Depth 6
  Write-DreamSkinUtf8FileAtomically -Path $Path -Content ($json + "`r`n")
}

function Archive-DreamSkinStateFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  $directory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($Path))
  $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss-fff')
  $archivePath = Join-Path $directory "state.stale-$stamp-$([guid]::NewGuid().ToString('N')).json"
  Move-Item -LiteralPath $Path -Destination $archivePath -ErrorAction Stop
  return $archivePath
}

function Get-DreamSkinProcessStartedAt {
  param([int]$ProcessId)
  try {
    return (Get-Process -Id $ProcessId -ErrorAction Stop).StartTime.ToUniversalTime().ToString('o')
  } catch {
    return $null
  }
}

function Stop-DreamSkinRecordedInjector {
  param([AllowNull()][object]$State)
  if ($null -eq $State -or -not $State.injectorPid) { return $true }
  $processId = [int]$State.injectorPid
  $process = Get-CimInstance Win32_Process -Filter "ProcessId = $processId" -ErrorAction SilentlyContinue
  if (-not $process) { return $true }

  $expectedInjector = if ($State.injectorPath) {
    "$($State.injectorPath)"
  } elseif ($State.skillRoot) {
    Join-Path "$($State.skillRoot)" 'scripts\injector.mjs'
  } else {
    $null
  }
  $processPath = Get-DreamSkinProcessExecutablePath -ProcessInfo $process
  $commandLine = "$($process.CommandLine)"
  if (-not $processPath -or -not $commandLine) {
    throw "The recorded injector PID $processId is running, but its identity cannot be inspected. State was preserved."
  }
  $isNodeExecutable = [System.IO.Path]::GetFileName("$processPath") -ieq 'node.exe'
  $nodeMatches = -not $State.nodePath -or
    (Test-DreamSkinPathEqual -Left $processPath -Right "$($State.nodePath)")
  $injectorPathMatches = [bool]($expectedInjector -and
    (Test-DreamSkinCommandLineToken -CommandLine $commandLine -Token $expectedInjector))
  $watchMatches = Test-DreamSkinCommandLineToken -CommandLine $commandLine -Token '--watch'
  $portMatches = $false
  if ($State.port) {
    $portPattern = '(?i)(?:^|\s)--port(?:=|\s+)' + [regex]::Escape("$($State.port)") + '(?=$|\s)'
    $portMatches = [regex]::IsMatch($commandLine, $portPattern)
  }
  $browserMatches = $true
  if ($State.browserId) {
    $browserPattern = '(?:^|\s)(?i:--browser-id)(?:=|\s+)' + [regex]::Escape("$($State.browserId)") + '(?=$|\s)'
    $browserMatches = [regex]::IsMatch($commandLine, $browserPattern)
  }
  $customRootMatches = $true
  if ($State.customRoot) {
    $customRootMatches =
      (Test-DreamSkinCommandLineToken -CommandLine $commandLine -Token '--custom-root') -and
      (Test-DreamSkinCommandLineToken -CommandLine $commandLine -Token "$($State.customRoot)")
  }
  $startedAt = Get-DreamSkinProcessStartedAt -ProcessId $processId
  $startMatches = -not $State.injectorStartedAt -or $startedAt -eq "$($State.injectorStartedAt)"
  $failedChecks = @()
  if (-not $isNodeExecutable) { $failedChecks += 'node-executable' }
  if (-not $nodeMatches) { $failedChecks += 'node-path' }
  if (-not $injectorPathMatches) { $failedChecks += 'injector-path' }
  if (-not $watchMatches) { $failedChecks += 'watch-mode' }
  if (-not $portMatches) { $failedChecks += 'port' }
  if (-not $browserMatches) { $failedChecks += 'browser-id' }
  if (-not $customRootMatches) { $failedChecks += 'custom-root' }
  if (-not $startMatches) { $failedChecks += 'start-time' }

  if ($failedChecks.Count -gt 0) {
    Write-Warning "Skipped stale injector PID $processId because these identity checks failed: $($failedChecks -join ', ')."
    return $false
  }

  Stop-Process -Id $processId -Force -ErrorAction Stop
  try { Wait-Process -Id $processId -Timeout 5 -ErrorAction Stop } catch {}
  if (Get-Process -Id $processId -ErrorAction SilentlyContinue) {
    throw "The recorded Dream Skin injector did not stop: PID $processId"
  }
  return $true
}

function Get-DreamSkinCodexProcesses {
  param(
    [Parameter(Mandatory = $true)][object]$Codex,
    [string]$ProfilePath,
    [switch]$MatchProfile
  )
  return @(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
      $processPath = Get-DreamSkinProcessExecutablePath -ProcessInfo $_
      (Test-DreamSkinPathEqual -Left $processPath -Right $Codex.Executable) -and
        (Test-DreamSkinProcessProfile -ProcessInfo $_ -ProfilePath $ProfilePath -MatchProfile:$MatchProfile)
    })
}

function Stop-DreamSkinCodex {
  param(
    [Parameter(Mandatory = $true)][object]$Codex,
    [string]$ProfilePath,
    [switch]$MatchProfile,
    [switch]$AllowForce,
    [ValidateRange(1, 60)][int]$GracePeriodSeconds = 15
  )
  $processes = Get-DreamSkinCodexProcesses -Codex $Codex -ProfilePath $ProfilePath -MatchProfile:$MatchProfile
  if ($processes.Count -eq 0) { return }
  foreach ($item in $processes) {
    try { [void](Get-Process -Id $item.ProcessId -ErrorAction Stop).CloseMainWindow() } catch {}
  }

  $deadline = (Get-Date).AddSeconds($GracePeriodSeconds)
  while ((Get-DreamSkinCodexProcesses -Codex $Codex -ProfilePath $ProfilePath `
      -MatchProfile:$MatchProfile).Count -gt 0 -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 250
  }
  $remaining = Get-DreamSkinCodexProcesses -Codex $Codex -ProfilePath $ProfilePath -MatchProfile:$MatchProfile
  if ($remaining.Count -eq 0) { return }
  if (-not $AllowForce) {
    throw "Codex did not close within $GracePeriodSeconds seconds. Close it manually or explicitly authorize a forced restart."
  }
  foreach ($item in $remaining) {
    $current = Get-CimInstance Win32_Process -Filter "ProcessId = $([int]$item.ProcessId)" -ErrorAction SilentlyContinue
    $currentPath = if ($current) { Get-DreamSkinProcessExecutablePath -ProcessInfo $current } else { $null }
    if ($currentPath -and (Test-DreamSkinPathEqual -Left $currentPath -Right $Codex.Executable)) {
      Stop-Process -Id $item.ProcessId -Force -ErrorAction SilentlyContinue
    }
  }
  Start-Sleep -Milliseconds 500
  if ((Get-DreamSkinCodexProcesses -Codex $Codex -ProfilePath $ProfilePath `
      -MatchProfile:$MatchProfile).Count -gt 0) { throw 'Codex could not be stopped safely.' }
}

function Confirm-DreamSkinRestart {
  param([string]$Message)
  $shell = New-Object -ComObject WScript.Shell
  return $shell.Popup($Message, 0, 'Codex Dream Skin', 52) -eq 6
}
