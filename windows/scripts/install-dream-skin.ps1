[CmdletBinding()]
param(
  [int]$Port = 9335,
  [string]$InstanceId = 'default',
  [switch]$NoShortcuts
)

$ErrorActionPreference = 'Stop'
$PortExplicit = $PSBoundParameters.ContainsKey('Port')
$SkillRoot = Split-Path -Parent $PSScriptRoot
$ProjectRoot = Split-Path -Parent $SkillRoot
. (Join-Path $PSScriptRoot 'common-windows.ps1')

$operationLock = Enter-DreamSkinOperationLock
try {
  Assert-DreamSkinPort -Port $Port
  Assert-DreamSkinInstanceId -InstanceId $InstanceId
  if ($InstanceId -cne 'default') {
    throw 'Non-default API Desktop instances must not install into the default Codex config; use start-dream-skin.ps1 with -InstanceId and -ProfilePath.'
  }
  $null = Get-DreamSkinNodeRuntime
  $registeredInstalls = @(Get-DreamSkinRegisteredCodexInstalls)
  if ($registeredInstalls.Count -eq 0) {
    throw 'The official OpenAI.Codex Store package is not installed or its identity cannot be validated.'
  }
  foreach ($registeredCodex in $registeredInstalls) {
    if ((Get-DreamSkinCodexProcesses -Codex $registeredCodex).Count -gt 0) {
      throw 'Close Codex before installing Dream Skin so config.toml cannot change during the transaction.'
    }
  }

  $StateRoot = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'
  $StatePath = Join-Path $StateRoot 'state.json'
  $existingState = Read-DreamSkinState -Path $StatePath
  $savedPathCandidate = Get-DreamSkinCodexStatePathCandidate -State $existingState
  $savedCodex = Resolve-DreamSkinCodexInstallFromState -State $existingState -RegisteredInstalls $registeredInstalls
  if ($null -ne $savedPathCandidate -and $null -eq $savedCodex -and
    (Get-DreamSkinCodexProcesses -Codex $savedPathCandidate).Count -gt 0) {
    throw 'The saved Codex path is still running but no longer matches a registered Store package. Close it manually before installing.'
  }
  New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null
  $ConfigPath = Join-Path $HOME '.codex\config.toml'
  $BackupPath = Join-Path $StateRoot 'config.before-dream-skin.toml'
  Install-DreamSkinBaseTheme -ConfigPath $ConfigPath -BackupPath $BackupPath

  if (-not $NoShortcuts) {
    $shell = New-Object -ComObject WScript.Shell
    $desktop = [Environment]::GetFolderPath('Desktop')
    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    $shortcutRoot = Join-Path $SkillRoot 'shortcuts'
    $powershell = (Get-Command pwsh.exe -ErrorAction Stop).Source
    $startScript = Join-Path $PSScriptRoot 'start-dream-skin.ps1'
    $restoreScript = Join-Path $PSScriptRoot 'restore-dream-skin.ps1'
    $installScript = Join-Path $ProjectRoot 'install-and-start-dream-skin.ps1'
    $portArgument = if ($PortExplicit) { " -Port $Port" } else { '' }
    New-Item -ItemType Directory -Force -Path $shortcutRoot | Out-Null

    foreach ($folder in @($desktop, $startMenu)) {
      $shortcut = $shell.CreateShortcut((Join-Path $folder 'Codex Dream Skin.lnk'))
      $shortcut.TargetPath = $powershell
      $shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$startScript`"$portArgument -PromptRestart"
      $shortcut.WorkingDirectory = $SkillRoot
      $shortcut.Description = 'Launch the official Codex app with Codex Dream Skin'
      $shortcut.Save()
    }

    $utilities = @(
      [pscustomobject]@{
        Name = '安装 Codex Dream Skin.lnk'
        Script = $installScript
        Arguments = ''
        Sta = $false
        Description = 'Install Codex Dream Skin and launch Codex'
      },
      [pscustomobject]@{
        Name = '切换 Codex Dream Skin 主题.lnk'
        Script = Join-Path $ProjectRoot 'select-dream-skin-theme.ps1'
        Arguments = ''
        Sta = $true
        Description = 'Switch between Codex Dream Skin theme packs'
      },
      [pscustomobject]@{
        Name = '更换 Codex Dream Skin 图片.lnk'
        Script = Join-Path $ProjectRoot 'customize-dream-skin-image.ps1'
        Arguments = ''
        Sta = $true
        Description = 'Choose a local image for Codex Dream Skin'
      },
      [pscustomobject]@{
        Name = '恢复 Codex Dream Skin 默认图片.lnk'
        Script = Join-Path $ProjectRoot 'customize-dream-skin-image.ps1'
        Arguments = ' -Reset'
        Sta = $true
        Description = 'Restore the bundled Codex Dream Skin image'
      }
    )
    foreach ($utility in $utilities) {
      if (-not (Test-Path -LiteralPath $utility.Script)) { continue }
      $staArgument = if ($utility.Sta) { ' -STA' } else { '' }
      $shortcut = $shell.CreateShortcut((Join-Path $shortcutRoot $utility.Name))
      $shortcut.TargetPath = $powershell
      $shortcut.Arguments = "-NoProfile$staArgument -ExecutionPolicy Bypass -File `"$($utility.Script)`"$($utility.Arguments)"
      $shortcut.WorkingDirectory = $ProjectRoot
      $shortcut.Description = $utility.Description
      $shortcut.Save()
    }

    $restore = $shell.CreateShortcut((Join-Path $shortcutRoot 'Codex Dream Skin - Restore.lnk'))
    $restore.TargetPath = $powershell
    $restore.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$restoreScript`"$portArgument -RestoreBaseTheme -PromptRestart"
    $restore.WorkingDirectory = $SkillRoot
    $restore.Description = 'Restore the official Codex appearance and close the CDP session'
    $restore.Save()

    $legacyShortcutNames = @(
      '安装 Codex Dream Skin.lnk',
      'Codex Dream Skin - Restore.lnk',
      '切换 Codex Dream Skin 主题.lnk',
      '更换 Codex Dream Skin 图片.lnk',
      '恢复 Codex Dream Skin 默认图片.lnk'
    )
    foreach ($legacyFolder in @($desktop, $startMenu)) {
      foreach ($name in $legacyShortcutNames) {
        Remove-Item -LiteralPath (Join-Path $legacyFolder $name) -Force -ErrorAction SilentlyContinue
      }
    }
  }

  if ($NoShortcuts) {
    Write-Host 'Codex Dream Skin base theme installed. Run start-dream-skin.ps1 to launch it.'
  } else {
    Write-Host "Codex Dream Skin installed. Desktop keeps only the launch shortcut; utility shortcuts are in $shortcutRoot"
  }
} finally {
  Exit-DreamSkinOperationLock -Mutex $operationLock
}
