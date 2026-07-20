[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$installScript = Join-Path $root 'windows\scripts\install-dream-skin.ps1'
$startScript = Join-Path $root 'windows\scripts\start-dream-skin.ps1'

try {
  Write-Host '正在安装 Codex Dream Skin…' -ForegroundColor Cyan
  & $installScript

  Write-Host '安装完成，正在以 Dream Skin 模式启动 Codex…' -ForegroundColor Green
  & $startScript

  Write-Host 'Dream Skin 已启动。现在可以关闭此窗口。' -ForegroundColor Green
} catch {
  Write-Host ''
  Write-Host "安装或启动失败：$($_.Exception.Message)" -ForegroundColor Red
  Write-Host '请确认 Codex 已完全退出后重试。' -ForegroundColor Yellow
  Read-Host '按 Enter 关闭窗口'
  exit 1
}
