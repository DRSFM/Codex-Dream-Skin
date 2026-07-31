[CmdletBinding()]
param(
  [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$scriptRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $scriptRoot 'release'
}
$projectRoot = Split-Path -Parent (Split-Path -Parent $scriptRoot)
$project = Join-Path $scriptRoot 'CodexDreamSkin.Launcher\CodexDreamSkin.Launcher.csproj'
$tests = Join-Path $scriptRoot 'CodexDreamSkin.Launcher.Tests\CodexDreamSkin.Launcher.Tests.csproj'
$output = [System.IO.Path]::GetFullPath($OutputPath)
$launcherRoot = $scriptRoot.TrimEnd('\') + '\'
if (-not $output.StartsWith($launcherRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'Release output must stay inside windows\launcher.'
}

dotnet test $tests -c Release
if ($LASTEXITCODE -ne 0) { throw 'Launcher tests failed.' }

if (Test-Path -LiteralPath $output) {
  [System.IO.Directory]::Delete($output, $true)
}
dotnet publish $project -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
  -p:DebugType=None -p:DebugSymbols=false -o $output
if ($LASTEXITCODE -ne 0) { throw 'Launcher publish failed.' }

$runtimeWindows = Join-Path $output 'windows'
New-Item -ItemType Directory -Force -Path $runtimeWindows | Out-Null
foreach ($directory in @('scripts', 'assets', 'themes', 'presets')) {
  Copy-Item -LiteralPath (Join-Path $projectRoot "windows\$directory") `
    -Destination (Join-Path $runtimeWindows $directory) -Recurse -Force
}

$readme = @'
Codex Dream Skin Launcher

1. Keep this directory structure intact.
2. Double-click CodexDreamSkin.Launcher.exe.
3. The launcher reads apicodex profile metadata but never displays or stores API keys.
'@
[System.IO.File]::WriteAllText(
  (Join-Path $output 'README.txt'),
  $readme,
  [System.Text.UTF8Encoding]::new($false, $true)
)

Get-ChildItem -LiteralPath $output | Select-Object Name, Length, LastWriteTime
