[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$project = Join-Path $PSScriptRoot 'CodexDreamSkin.Launcher\CodexDreamSkin.Launcher.csproj'
$executable = Join-Path $PSScriptRoot 'CodexDreamSkin.Launcher\bin\Release\net8.0-windows\CodexDreamSkin.Launcher.exe'
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
  dotnet build $project -c Release
  if ($LASTEXITCODE -ne 0) { throw 'Launcher build failed.' }
}
Start-Process -FilePath $executable -WorkingDirectory (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
