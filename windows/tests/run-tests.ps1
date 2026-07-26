[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'scripts\common-windows.ps1')

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) "codex-dream-skin-tests-$PID-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

try {
  $configPath = Join-Path $temporaryRoot 'config.toml'
  $backupPath = Join-Path $temporaryRoot 'config.before-dream-skin.toml'
  $projectName = -join @([char]0x4EE3, [char]0x7801, [char]0x9879, [char]0x76EE, [char]0x7532)
  $laterValue = -join @([char]0x4FDD, [char]0x7559)
  $sample = "model = `"gpt-5`"`r`n`r`n[other]`r`nappearanceTheme = `"keep-other`"`r`n`r`n[projects.'C:\$projectName']`r`ntrust_level = `"trusted`"`r`n`r`n[desktop]`r`nappearanceTheme = `"system`"`r`nappearanceLightCodeThemeId = `"theme-`$special`"`r`n"
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false, $true)
  [System.IO.File]::WriteAllText($configPath, $sample, $utf8NoBom)
  $originalBytes = [System.IO.File]::ReadAllBytes($configPath)

  Install-DreamSkinBaseTheme -ConfigPath $configPath -BackupPath $backupPath
  $installed = Read-DreamSkinUtf8File -Path $configPath
  if (-not $installed.Contains($projectName) -or $installed -notmatch 'appearanceTheme = "light"') {
    throw 'Install changed a non-ASCII project name or missed the base theme.'
  }
  $backupBytes = [System.IO.File]::ReadAllBytes($backupPath)
  if ([Convert]::ToBase64String($backupBytes) -cne [Convert]::ToBase64String($originalBytes)) {
    throw 'Install did not preserve an exact pre-change config backup.'
  }

  $written = [System.IO.File]::ReadAllBytes($configPath)
  if ($written.Length -ge 3 -and $written[0] -eq 0xEF -and $written[1] -eq 0xBB -and $written[2] -eq 0xBF) {
    throw 'Config writer added an unexpected UTF-8 BOM.'
  }

  $installed += "afterInstall = `"$laterValue`"`r`n"
  Write-DreamSkinUtf8FileAtomically -Path $configPath -Content $installed
  Restore-DreamSkinBaseTheme -ConfigPath $configPath -BackupPath $backupPath
  $restored = Read-DreamSkinUtf8File -Path $configPath
  if (-not $restored.Contains($projectName) -or -not $restored.Contains($laterValue)) {
    throw 'Restore changed a project name or unrelated post-install setting.'
  }
  if ($restored -notmatch 'appearanceTheme = "system"' -or -not $restored.Contains('appearanceLightCodeThemeId = "theme-$special"')) {
    throw 'Restore did not put the original base theme keys back.'
  }
  if ($restored -notmatch '(?ms)^\[other\].*?appearanceTheme = "keep-other"') {
    throw 'Restore changed an appearance key outside the desktop section.'
  }

  $lfConfigPath = Join-Path $temporaryRoot 'config-lf.toml'
  $lfBackupPath = Join-Path $temporaryRoot 'config-lf.before.toml'
  $lfOriginal = "model = `"gpt-5`"`n[projects.'C:\$projectName']`ntrust_level = `"trusted`"`n"
  [System.IO.File]::WriteAllText($lfConfigPath, $lfOriginal, $utf8NoBom)
  Install-DreamSkinBaseTheme -ConfigPath $lfConfigPath -BackupPath $lfBackupPath
  $lfInstalled = Read-DreamSkinUtf8File -Path $lfConfigPath
  if ($lfInstalled.Contains("`r") -or $lfInstalled -notmatch '(?m)^\[desktop\]$') {
    throw 'Install did not preserve LF line endings or create the desktop section.'
  }
  Restore-DreamSkinBaseTheme -ConfigPath $lfConfigPath -BackupPath $lfBackupPath
  $lfRestored = Read-DreamSkinUtf8File -Path $lfConfigPath
  if ($lfRestored.Contains("`r") -or $lfRestored -match '(?m)^\[desktop\]$' -or -not $lfRestored.Contains($projectName)) {
    throw 'Restore did not preserve LF content or remove the generated empty desktop section.'
  }

  $quotedConfigPath = Join-Path $temporaryRoot 'config-quoted.toml'
  $quotedBackupPath = Join-Path $temporaryRoot 'config-quoted.before.toml'
  $quotedOriginal = "[`"desktop`"] # retained comment`r`n`"appearanceTheme`" = `"system`"`r`n'appearanceLightCodeThemeId' = `"theme-`$special`"`r`n"
  [System.IO.File]::WriteAllText($quotedConfigPath, $quotedOriginal, $utf8NoBom)
  Install-DreamSkinBaseTheme -ConfigPath $quotedConfigPath -BackupPath $quotedBackupPath
  $quotedInstalled = Read-DreamSkinUtf8File -Path $quotedConfigPath
  if ([regex]::Matches($quotedInstalled, '(?m)^\s*\[(?:"desktop"|desktop)\]').Count -ne 1) {
    throw 'A commented or quoted desktop table was duplicated during install.'
  }
  Restore-DreamSkinBaseTheme -ConfigPath $quotedConfigPath -BackupPath $quotedBackupPath
  if ((Read-DreamSkinUtf8File -Path $quotedConfigPath) -cne $quotedOriginal) {
    throw 'Quoted desktop keys or a table-header comment were not restored exactly.'
  }

  $singleLineArrayPath = Join-Path $temporaryRoot 'config-single-line-array.toml'
  $singleLineArrayBackup = Join-Path $temporaryRoot 'config-single-line-array.before.toml'
  $singleLineArray = "labels = [`"name[1]`", `"#tag]`"]`r`n"
  [System.IO.File]::WriteAllText($singleLineArrayPath, $singleLineArray, $utf8NoBom)
  Install-DreamSkinBaseTheme -ConfigPath $singleLineArrayPath -BackupPath $singleLineArrayBackup
  if (-not (Read-DreamSkinUtf8File -Path $singleLineArrayPath).Contains($singleLineArray.TrimEnd())) {
    throw 'A safe single-line array containing bracket text was changed or rejected.'
  }

  foreach ($unsupported in @(
    'desktop.appearanceTheme = "system"',
    'desktop = { appearanceTheme = "system" }',
    '[[desktop]]',
    '[desktop.appearanceTheme]',
    '["desktop".layout]',
    '["desk\u0074op".layout]',
    '["desk\u0074op"]',
    "note = `"`"`"fake`r`n[desktop]`r`nappearanceTheme = `"dark`"`r`n`"`"`"",
    "[desktop]`r`nappearanceTheme = [`r`n  `"light`"`r`n]",
    "[desktop]`r`nlayout = [`r`n  [1, 2],`r`n  [3, 4],`r`n]`r`nappearanceTheme = `"dark`"",
    "[desktop]`r`nlayout = [`"]`",`r`n  [`"[`", `"]`"],`r`n]`r`nappearanceTheme = `"dark`""
  )) {
    $unsupportedPath = Join-Path $temporaryRoot ("unsupported-$([guid]::NewGuid().ToString('N')).toml")
    $unsupportedBackup = "$unsupportedPath.before"
    [System.IO.File]::WriteAllText($unsupportedPath, $unsupported, $utf8NoBom)
    $unsupportedRejected = $false
    try { Install-DreamSkinBaseTheme -ConfigPath $unsupportedPath -BackupPath $unsupportedBackup } catch { $unsupportedRejected = $true }
    if (-not $unsupportedRejected -or (Test-Path -LiteralPath $unsupportedBackup)) {
      throw "Unsupported TOML desktop representation was not rejected safely: $unsupported"
    }
  }

  $recoveryPath = Join-Path $temporaryRoot 'config.before-recovery.toml'
  Write-DreamSkinUtf8FileAtomically -Path $configPath -Content 'intentionally changed'
  Restore-DreamSkinConfigBackup -ConfigPath $configPath -BackupPath $backupPath -RecoveryBackupPath $recoveryPath
  $recoveredBytes = [System.IO.File]::ReadAllBytes($configPath)
  if ([Convert]::ToBase64String($recoveredBytes) -cne [Convert]::ToBase64String($originalBytes)) {
    throw 'Exact config recovery did not restore the original bytes.'
  }
  if ((Read-DreamSkinUtf8File -Path $recoveryPath) -cne 'intentionally changed') {
    throw 'Exact config recovery did not preserve the replaced current config.'
  }
  $archivePath = Join-Path $temporaryRoot 'config.restored.toml'
  Archive-DreamSkinConfigBackup -BackupPath $backupPath -ArchivePath $archivePath
  if ((Test-Path -LiteralPath $backupPath) -or -not (Test-Path -LiteralPath $archivePath)) {
    throw 'Completed config backup was not archived for a safe future reinstall.'
  }
  $secondBaseline = "[desktop]`r`nappearanceTheme = `"dark`"`r`n"
  [System.IO.File]::WriteAllText($configPath, $secondBaseline, $utf8NoBom)
  $secondBaselineBytes = [System.IO.File]::ReadAllBytes($configPath)
  Install-DreamSkinBaseTheme -ConfigPath $configPath -BackupPath $backupPath
  if (-not (Test-DreamSkinBytesEqual -Left $secondBaselineBytes -Right ([System.IO.File]::ReadAllBytes($backupPath)))) {
    throw 'Reinstall did not capture a fresh config baseline after completed restore.'
  }

  $invalidPath = Join-Path $temporaryRoot 'invalid.toml'
  $invalidBackupPath = Join-Path $temporaryRoot 'invalid.before.toml'
  [System.IO.File]::WriteAllBytes($invalidPath, [byte[]](0x66, 0x6f, 0x80))
  $rejected = $false
  try { Install-DreamSkinBaseTheme -ConfigPath $invalidPath -BackupPath $invalidBackupPath } catch { $rejected = $true }
  if (-not $rejected -or (Test-Path -LiteralPath $invalidBackupPath)) {
    throw 'Invalid UTF-8 input was not rejected before backup creation.'
  }
  $utf16Path = Join-Path $temporaryRoot 'utf16.toml'
  $utf16BackupPath = Join-Path $temporaryRoot 'utf16.before.toml'
  [System.IO.File]::WriteAllText($utf16Path, 'model = "gpt-5"', [System.Text.Encoding]::Unicode)
  $utf16Rejected = $false
  try { Install-DreamSkinBaseTheme -ConfigPath $utf16Path -BackupPath $utf16BackupPath } catch { $utf16Rejected = $true }
  if (-not $utf16Rejected -or (Test-Path -LiteralPath $utf16BackupPath)) {
    throw 'A UTF-16 config was silently transcoded instead of being rejected.'
  }
  $utf16NoBomPath = Join-Path $temporaryRoot 'utf16-no-bom.toml'
  $utf16NoBomBackupPath = Join-Path $temporaryRoot 'utf16-no-bom.before.toml'
  [System.IO.File]::WriteAllBytes($utf16NoBomPath, [System.Text.Encoding]::Unicode.GetBytes('model = "gpt-5"'))
  $utf16NoBomRejected = $false
  try { Install-DreamSkinBaseTheme -ConfigPath $utf16NoBomPath -BackupPath $utf16NoBomBackupPath } catch { $utf16NoBomRejected = $true }
  if (-not $utf16NoBomRejected -or (Test-Path -LiteralPath $utf16NoBomBackupPath)) {
    throw 'A BOM-less UTF-16 config was silently treated as UTF-8 instead of being rejected.'
  }
  $racePath = Join-Path $temporaryRoot 'race.toml'
  [System.IO.File]::WriteAllText($racePath, 'before', $utf8NoBom)
  $raceExpected = [System.IO.File]::ReadAllBytes($racePath)
  [System.IO.File]::WriteAllText($racePath, 'after', $utf8NoBom)
  $raceRejected = $false
  try { Assert-DreamSkinFileUnchanged -Path $racePath -ExpectedBytes $raceExpected } catch { $raceRejected = $true }
  if (-not $raceRejected) { throw 'Concurrent config modification was not detected.' }
  $conditionalWriteRejected = $false
  try {
    Write-DreamSkinUtf8FileAtomically -Path $racePath -Content 'replacement' -ExpectedBytes $raceExpected
  } catch {
    $conditionalWriteRejected = $true
  }
  if (-not $conditionalWriteRejected -or (Read-DreamSkinUtf8File -Path $racePath) -cne 'after') {
    throw 'Conditional atomic write replaced newer config content.'
  }

  if (-not (Test-DreamSkinWebSocketUrl -Value 'ws://127.0.0.1:9335/devtools/page/test' -Port 9335)) {
    throw 'PowerShell loopback WebSocket validation rejected a safe target.'
  }
  foreach ($unsafe in @(
    'ws://example.com:9335/devtools/page/test',
    'ws://127.0.0.1:9336/devtools/page/test',
    'wss://127.0.0.1:9335/devtools/page/test',
    'ws://user@127.0.0.1:9335/devtools/page/test',
    'ws://127.0.0.1:9335/unexpected/test',
    'ws://127.0.0.1:9335/devtools/page/test?query=1'
  )) {
    if (Test-DreamSkinWebSocketUrl -Value $unsafe -Port 9335) { throw "Accepted unsafe CDP target: $unsafe" }
  }
  $safePageTarget = [pscustomobject]@{
    id = 'page-123'
    type = 'page'
    url = 'app://codex/'
    webSocketDebuggerUrl = 'ws://127.0.0.1:9335/devtools/page/page-123'
  }
  if (-not (Test-DreamSkinCdpPageTarget -Target $safePageTarget -Port 9335)) {
    throw 'A valid same-ID CDP page target was rejected.'
  }
  foreach ($unsafePageTarget in @(
    [pscustomobject]@{ id = 'page-123'; type = 'page'; url = 'app://codex/'; webSocketDebuggerUrl = 'ws://127.0.0.1:9335/devtools/browser/page-123' },
    [pscustomobject]@{ id = 'other-page'; type = 'page'; url = 'app://codex/'; webSocketDebuggerUrl = 'ws://127.0.0.1:9335/devtools/page/page-123' },
    [pscustomobject]@{ id = 123; type = 'page'; url = 'app://codex/'; webSocketDebuggerUrl = 'ws://127.0.0.1:9335/devtools/page/123' },
    [pscustomobject]@{ id = 'page-123'; type = 'other'; url = 'app://codex/'; webSocketDebuggerUrl = 'ws://127.0.0.1:9335/devtools/page/page-123' }
  )) {
    if (Test-DreamSkinCdpPageTarget -Target $unsafePageTarget -Port 9335) {
      throw 'Accepted an inconsistent CDP page target.'
    }
  }
  $watchCommand = '"C:\Program Files\nodejs\node.exe" "C:\Dream Skin\injector.mjs" --watch --port 9335 --browser-id browser-123'
  if (-not (Test-DreamSkinCommandLineToken -CommandLine $watchCommand -Token 'C:\Dream Skin\injector.mjs') -or
    (Test-DreamSkinCommandLineToken -CommandLine $watchCommand -Token 'Dream Skin\injector.mjs')) {
    throw 'Injector command-line token validation is not boundary-safe.'
  }
  if (-not (Test-DreamSkinBrowserId -Value 'browser-123') -or
    (Test-DreamSkinBrowserId -Value 'browser 123')) {
    throw 'CDP browser ID validation is not boundary-safe.'
  }
  $quotedProfile = ConvertTo-DreamSkinProcessArgument -Value '--user-data-dir=C:\Dream Skin\Profile\'
  if ($quotedProfile -cne '"--user-data-dir=C:\Dream Skin\Profile\\"') {
    throw 'Process argument quoting did not protect spaces and a trailing backslash.'
  }
  if ((Get-DreamSkinInstanceStateRoot -InstanceId 'default') -cne (Join-Path $env:LOCALAPPDATA 'CodexDreamSkin') -or
    (Get-DreamSkinInstanceStateRoot -InstanceId 'anyrouter') -cne (Join-Path $env:LOCALAPPDATA 'CodexDreamSkin\instances\anyrouter')) {
    throw 'Instance state roots are not backward-compatible or isolated.'
  }
  $fakeRootProcess = [pscustomobject]@{
    ProcessId = 7001
    ParentProcessId = 0
    CommandLine = '"C:\Program Files\OpenAI\ChatGPT.exe" --user-data-dir="C:\Users\Test\.apicodex-desktop\anyrouter"'
    ExecutablePath = 'C:\Program Files\OpenAI\ChatGPT.exe'
  }
  $detectedProfile = Get-DreamSkinProcessUserDataDir -ProcessInfo $fakeRootProcess
  if (-not (Test-DreamSkinPathEqual -Left $detectedProfile -Right 'C:\Users\Test\.apicodex-desktop\anyrouter') -or
    -not (Test-DreamSkinProcessProfile -ProcessInfo $fakeRootProcess `
      -ProfilePath 'C:\Users\Test\.apicodex-desktop\anyrouter' -MatchProfile) -or
    (Test-DreamSkinProcessProfile -ProcessInfo $fakeRootProcess `
      -ProfilePath 'C:\Users\Test\.apicodex-desktop\muyuanpub' -MatchProfile)) {
    throw 'Process user-data-dir parsing or profile matching failed.'
  }

  $statePath = Join-Path $temporaryRoot 'state.json'
  $state = [pscustomobject]@{
    schemaVersion = 3
    platform = 'windows'
    port = 9335
    injectorPid = 1234
    injectorStartedAt = '2026-01-01T00:00:00.0000000Z'
    injectorPath = 'C:\Dream Skin\injector.mjs'
    nodePath = 'C:\Program Files\nodejs\node.exe'
    codexExe = 'C:\Program Files\WindowsApps\OpenAI.Codex\app\ChatGPT.exe'
    codexPackageRoot = 'C:\Program Files\WindowsApps\OpenAI.Codex'
    codexPackageFullName = 'OpenAI.Codex_1.2.3.4_x64__test'
    codexPackageFamilyName = 'OpenAI.Codex_test'
    browserId = 'browser-123'
  }
  Write-DreamSkinState -Path $statePath -State $state
  $loadedState = Read-DreamSkinState -Path $statePath
  if ($loadedState.schemaVersion -ne 3 -or $loadedState.port -ne 9335 -or
    $loadedState.browserId -cne 'browser-123' -or $loadedState.injectorStartedAt -isnot [string]) {
    throw 'State round-trip failed or timestamp normalization is missing.'
  }
  $missingIdentityState = [pscustomobject]@{ schemaVersion = 3; platform = 'windows'; port = 9335 }
  Write-DreamSkinState -Path $statePath -State $missingIdentityState
  $missingIdentityRejected = $false
  try { $null = Read-DreamSkinState -Path $statePath } catch { $missingIdentityRejected = $true }
  if (-not $missingIdentityRejected) { throw 'Schema 3 accepted a state missing process and package identity.' }
  $legacyState = [pscustomobject]@{ schemaVersion = 2; platform = 'windows'; port = 9335; injectorPid = 1234 }
  Write-DreamSkinState -Path $statePath -State $legacyState
  if ((Read-DreamSkinState -Path $statePath).schemaVersion -ne 2) {
    throw 'A supported schema 2 state was rejected.'
  }

  $fakePackageRoot = Join-Path $temporaryRoot 'OpenAI.Codex_1.2.3.4_x64__test'
  $fakeExecutable = Join-Path $fakePackageRoot 'app\ChatGPT.exe'
  New-Item -ItemType Directory -Path (Split-Path -Parent $fakeExecutable) -Force | Out-Null
  [System.IO.File]::WriteAllBytes($fakeExecutable, [byte[]]@())
  $fakePackage = [pscustomobject]@{
    Name = 'OpenAI.Codex'
    InstallLocation = $fakePackageRoot
    PackageFullName = 'OpenAI.Codex_1.2.3.4_x64__test'
    PackageFamilyName = 'OpenAI.Codex_test'
    SignatureKind = 'Store'
    IsDevelopmentMode = $false
    Version = [version]'1.2.3.4'
  }
  $fakeInstall = ConvertTo-DreamSkinCodexInstall -Package $fakePackage
  if ($null -eq $fakeInstall -or $fakeInstall.PackageFullName -cne $fakePackage.PackageFullName -or
    -not (Test-DreamSkinPathEqual -Left $fakeInstall.Executable -Right $fakeExecutable)) {
    throw 'Registered Appx package identity conversion failed.'
  }
  $fakePackage.SignatureKind = 'Developer'
  if ($null -ne (ConvertTo-DreamSkinCodexInstall -Package $fakePackage)) {
    throw 'A non-Store Appx package was accepted as official Codex.'
  }
  $fakePackage.SignatureKind = 'Store'
  $pathOnlyState = [pscustomobject]@{
    codexExe = $fakeExecutable
    codexPackageRoot = $fakePackageRoot
    codexVersion = '1.2.3.4'
  }
  if ($null -eq (Get-DreamSkinCodexStatePathCandidate -State $pathOnlyState)) {
    throw 'A structurally valid legacy Codex path was not recognized for read-only activity checks.'
  }
  if ($null -eq (Resolve-DreamSkinCodexInstallFromState -State $pathOnlyState `
    -RegisteredInstalls @($fakeInstall))) {
    throw 'A legacy state path was not revalidated against a registered Store package.'
  }
  $verifiedPackageState = [pscustomobject]@{
    codexExe = $fakeExecutable
    codexPackageRoot = $fakePackageRoot
    codexVersion = '1.2.3.4'
    codexPackageFullName = $fakePackage.PackageFullName
    codexPackageFamilyName = $fakePackage.PackageFamilyName
  }
  $resolvedInstall = Resolve-DreamSkinCodexInstallFromState -State $verifiedPackageState `
    -RegisteredInstalls @($fakeInstall)
  if ($null -eq $resolvedInstall -or -not $resolvedInstall.RegisteredPackageVerified) {
    throw 'State package identity did not resolve against the registered Appx package.'
  }
  $verifiedPackageState.codexPackageFamilyName = 'OpenAI.Codex_wrong'
  if ($null -ne (Resolve-DreamSkinCodexInstallFromState -State $verifiedPackageState `
    -RegisteredInstalls @($fakeInstall))) {
    throw 'A mismatched Appx package family was accepted from state.'
  }
  Write-DreamSkinUtf8FileAtomically -Path $statePath -Content '[]'
  $badStateRejected = $false
  try { $null = Read-DreamSkinState -Path $statePath } catch { $badStateRejected = $true }
  if (-not $badStateRejected) { throw 'A non-object state file was accepted.' }
  $staleStatePath = Archive-DreamSkinStateFile -Path $statePath
  if ((Test-Path -LiteralPath $statePath) -or -not (Test-Path -LiteralPath $staleStatePath)) {
    throw 'Stale state was not preserved under an archive name.'
  }

  $installerSource = Get-Content -LiteralPath (Join-Path $Root 'scripts\install-dream-skin.ps1') -Raw
  if ([regex]::Matches($installerSource, [regex]::Escape('foreach ($folder in @($desktop, $startMenu))')).Count -ne 1) {
    throw 'Installer must create only the main launch shortcut on Desktop and the Start menu.'
  }
  foreach ($requiredShortcutRule in @(
    "`$shortcutRoot = Join-Path `$SkillRoot 'shortcuts'",
    '$shell.CreateShortcut((Join-Path $shortcutRoot $utility.Name))',
    "`$shell.CreateShortcut((Join-Path `$shortcutRoot 'Codex Dream Skin - Restore.lnk'))"
  )) {
    if (-not $installerSource.Contains($requiredShortcutRule)) {
      throw "Installer is missing the repository-local shortcut rule: $requiredShortcutRule"
    }
  }
  foreach ($forbiddenDesktopShortcut in @(
    "Join-Path `$desktop 'Codex Dream Skin - Restore.lnk'",
    'Join-Path $desktop $utility.Name'
  )) {
    if ($installerSource.Contains($forbiddenDesktopShortcut)) {
      throw "Installer still creates a utility shortcut on Desktop: $forbiddenDesktopShortcut"
    }
  }
  foreach ($legacyShortcutName in @(
    '安装 Codex Dream Skin.lnk',
    'Codex Dream Skin - Restore.lnk',
    '切换 Codex Dream Skin 主题.lnk',
    '更换 Codex Dream Skin 图片.lnk',
    '恢复 Codex Dream Skin 默认图片.lnk'
  )) {
    if (-not $installerSource.Contains("'$legacyShortcutName'")) {
      throw "Installer does not migrate the legacy shortcut layout: $legacyShortcutName"
    }
  }

  $projectRoot = Split-Path -Parent $Root
  $customizer = Join-Path $projectRoot 'customize-dream-skin-image.ps1'
  $testLocalAppData = Join-Path $temporaryRoot 'local-app-data'
  $previousLocalAppData = $env:LOCALAPPDATA
  try {
    $env:LOCALAPPDATA = $testLocalAppData
    & $customizer -ImagePath (Join-Path $Root 'assets\dream-reference.png') `
      -Mode full-window -NoApply
    $testCustomRoot = Join-Path $testLocalAppData 'CodexDreamSkin\custom'
    $testModePath = Join-Path $testCustomRoot 'image-mode.txt'
    if ((Get-Content -LiteralPath $testModePath -Raw).Trim() -cne 'full-window' -or
      @(Get-ChildItem -LiteralPath $testCustomRoot -Filter 'custom-image.*' -File).Count -ne 1) {
      throw 'Image customizer did not persist full-window mode and one managed image.'
    }
    $modeTestNode = Get-DreamSkinNodeRuntime
    $fullWindowPayload = & $modeTestNode.Path (Join-Path $Root 'scripts\injector.mjs') --check-payload |
      ConvertFrom-Json
    if ($fullWindowPayload.presentation -cne 'full-window') {
      throw 'Injector did not load the persisted full-window image mode.'
    }
    & $customizer -ImagePath (Join-Path $Root 'assets\dream-reference.png') `
      -Mode home-card -NoApply
    if ((Get-Content -LiteralPath $testModePath -Raw).Trim() -cne 'home-card') {
      throw 'Image customizer did not preserve the optional home-card presentation.'
    }
    $homeCardPayload = & $modeTestNode.Path (Join-Path $Root 'scripts\injector.mjs') --check-payload |
      ConvertFrom-Json
    if ($homeCardPayload.presentation -cne 'home-card') {
      throw 'Injector did not load the persisted home-card image mode.'
    }
    Write-DreamSkinUtf8FileAtomically -Path (Join-Path $testCustomRoot 'active-theme.txt') -Content "pink-dream`n"
    $copyScript = Join-Path $Root 'scripts\copy-dream-skin-instance-appearance.ps1'
    & $copyScript -InstanceId anyrouter -SourceInstanceId default | Out-Null
    $instanceCustomRoot = Join-Path $testLocalAppData 'CodexDreamSkin\instances\anyrouter\custom'
    $sourceImage = Get-ChildItem -LiteralPath $testCustomRoot -File -Filter 'custom-image.*' | Select-Object -First 1
    $instanceImage = Get-ChildItem -LiteralPath $instanceCustomRoot -File -Filter 'custom-image.*' | Select-Object -First 1
    if ($null -eq $instanceImage -or
      (Get-FileHash -LiteralPath $sourceImage.FullName -Algorithm SHA256).Hash -cne
      (Get-FileHash -LiteralPath $instanceImage.FullName -Algorithm SHA256).Hash -or
      (Get-Content -LiteralPath (Join-Path $instanceCustomRoot 'active-theme.txt') -Raw).Trim() -cne 'pink-dream') {
      throw 'Instance appearance copy did not preserve the managed image and theme.'
    }
    $instancePayload = & $modeTestNode.Path (Join-Path $Root 'scripts\injector.mjs') --check-payload `
      --custom-root $instanceCustomRoot | ConvertFrom-Json
    if ($instancePayload.presentation -cne 'home-card') {
      throw 'Injector did not load appearance from the isolated instance custom root.'
    }

    $appearanceScript = Join-Path $Root 'scripts\set-dream-skin-instance-appearance.ps1'
    $appearance = & $appearanceScript -InstanceId launcher-test `
      -ImagePath (Join-Path $Root 'assets\dream-reference.png') -Mode full-window `
      -ThemeId crystal-clear | ConvertFrom-Json
    if ($appearance.instanceId -cne 'launcher-test' -or -not $appearance.hasCustomImage -or
      $appearance.mode -cne 'full-window' -or $appearance.themeId -cne 'crystal-clear') {
      throw 'Instance appearance setter did not persist the requested image, mode and theme.'
    }
    $launcherCustomRoot = Join-Path $testLocalAppData 'CodexDreamSkin\instances\launcher-test\custom'
    if (-not (Test-DreamSkinPathEqual -Left $appearance.customRoot -Right $launcherCustomRoot)) {
      throw 'Instance appearance setter wrote outside the requested instance root.'
    }
    $clearedAppearance = & $appearanceScript -InstanceId launcher-test -ClearImage `
      -Mode home-card | ConvertFrom-Json
    if ($clearedAppearance.hasCustomImage -or $clearedAppearance.mode -cne 'home-card' -or
      @(Get-ChildItem -LiteralPath $launcherCustomRoot -File -Filter 'custom-image.*').Count -ne 0) {
      throw 'Instance appearance setter did not clear only the managed custom image.'
    }
    $unsafeAppearanceRejected = $false
    try {
      & $appearanceScript -InstanceId '..\default' -Mode full-window *> $null
    } catch { $unsafeAppearanceRejected = $true }
    if (-not $unsafeAppearanceRejected) { throw 'Instance appearance setter accepted an unsafe instance ID.' }

    $statusScript = Join-Path $Root 'scripts\get-dream-skin-instance-status.ps1'
    $missingProfileRejected = $false
    try {
      & $statusScript -InstanceId launcher-test -Port 9340 *> $null
    } catch { $missingProfileRejected = $true }
    if (-not $missingProfileRejected) { throw 'Non-default status query accepted a missing profile path.' }

    $batchStatusScript = Join-Path $Root 'scripts\get-dream-skin-launcher-status.ps1'
    $batchPathRejected = $false
    try {
      & $batchStatusScript -RequestPath (Join-Path $temporaryRoot 'outside-batch-request.json') *> $null
    } catch { $batchPathRejected = $true }
    if (-not $batchPathRejected) { throw 'Batch status query accepted a request file outside its temp root.' }
  } finally {
    $env:LOCALAPPDATA = $previousLocalAppData
  }

  $rendererSource = Get-Content -LiteralPath (Join-Path $Root 'assets\renderer-inject.js') -Raw
  $skinCss = Get-Content -LiteralPath (Join-Path $Root 'assets\dream-skin.css') -Raw
  $injectorSource = Get-Content -LiteralPath (Join-Path $Root 'scripts\injector.mjs') -Raw
  $startSource = Get-Content -LiteralPath (Join-Path $Root 'scripts\start-dream-skin.ps1') -Raw
  if (-not $startSource.Contains('$StartupVerifyTimeoutMs = 60000') -or
    -not $startSource.Contains('--timeout-ms $StartupVerifyTimeoutMs')) {
    throw 'Startup verification must allow the current Codex renderer at least 60 seconds to mount.'
  }
  foreach ($profileScopedScript in @(
    'start-dream-skin.ps1',
    'restore-dream-skin.ps1',
    'verify-dream-skin.ps1'
  )) {
    $profileScopedSource = Get-Content -LiteralPath (Join-Path $Root "scripts\$profileScopedScript") -Raw
    if (-not $profileScopedSource.Contains('$MatchProfile = $true')) {
      throw "$profileScopedScript does not force profile matching for the default instance."
    }
  }
  $stopSource = Get-Content -LiteralPath (Join-Path $Root 'scripts\stop-codex-instance.ps1') -Raw
  foreach ($stopContract in @(
    'Get-DreamSkinCodexProcesses -Codex $codex -ProfilePath $ProfilePath -MatchProfile',
    'Stop-DreamSkinCodex -Codex $codex -ProfilePath $ProfilePath -MatchProfile',
    "A non-default stop requires an explicit -ProfilePath."
  )) {
    if (-not $stopSource.Contains($stopContract)) {
      throw "Precise Desktop stop is missing contract: $stopContract"
    }
  }
  $missingStopProfileRejected = $false
  try {
    & (Join-Path $Root 'scripts\stop-codex-instance.ps1') -InstanceId 'api-test' -Port 9340 *> $null
  } catch { $missingStopProfileRejected = $true }
  if (-not $missingStopProfileRejected) {
    throw 'Precise Desktop stop accepted a non-default instance without a profile path.'
  }
  foreach ($adaptiveContract in @(
    'dream-art-full-window',
    'dream-art-home-card',
    '--dream-art-position',
    'analyzeArt'
  )) {
    if (-not $rendererSource.Contains($adaptiveContract)) {
      throw "Renderer is missing the adaptive image contract: $adaptiveContract"
    }
  }
  foreach ($fullWindowRule in @(
    'html.codex-dream-skin.dream-art-full-window body',
    'background-image: var(--dream-art) !important',
    'main.main-surface.dream-home-shell',
    'main.main-surface:not(.dream-home-shell)'
  )) {
    if (-not $skinCss.Contains($fullWindowRule)) {
      throw "CSS is missing a full-window background rule: $fullWindowRule"
    }
  }
  foreach ($liveReloadContract in @(
    'readPayloadSourceStamp',
    'candidate.fingerprint !== loadedPayload.fingerprint',
    'live theme updated'
  )) {
    if (-not $injectorSource.Contains($liveReloadContract)) {
      throw "Injector is missing live image/theme reload behavior: $liveReloadContract"
    }
  }

  $node = Get-DreamSkinNodeRuntime
  & $node.Path (Join-Path $Root 'scripts\injector.mjs') --self-test *> $null
  if ($LASTEXITCODE -ne 0) { throw 'Injector CDP self-test failed.' }
  & $node.Path (Join-Path $Root 'scripts\injector.mjs') --check-payload *> $null
  if ($LASTEXITCODE -ne 0) { throw 'Injector self-test failed.' }
  & $node.Path (Join-Path $PSScriptRoot 'renderer-inject.test.mjs')
  if ($LASTEXITCODE -ne 0) { throw 'Renderer auxiliary-window regression test failed.' }

  Write-Host 'PASS: config transactions, restore scoping, state safety, argument quoting, and loopback CDP validation.'
} finally {
  Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}
