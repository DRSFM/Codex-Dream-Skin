# Codex Dream Skin Launcher

Windows 原生 WPF 控制台，用于动态管理默认 Codex Desktop 和本地 apicodex API profile。实例名称来自本机 profile 数据，不在界面代码中预设上游。

## 功能

- 三栏实例界面：账号导航、状态表格、外观与维护详情。
- 每个实例独立端口、Desktop 数据目录、Dream Skin state/log/custom 目录。
- 独立背景图、主题和整窗/主页卡片模式。
- 启动或重启、停止、验证、恢复无皮肤状态。
- 统一系统托盘按 `ChatGPT`、`ChatGPT (Profile名)` 展示实例，并提供启动、聚焦、停止和重启操作。
- API Desktop 主窗口按 Profile 自动标记；账号窗口保持 `ChatGPT`，不会修改官方安装包或签名。
- 调用 apicodex 的交互流程添加、编辑或移除 API profile。
- 启动器只读取非敏感 profile 元数据，不读取或持久化 API Key、Cookie、`auth.json` 或 keyring 内容。

关闭管理面板只会把它隐藏到系统托盘，ChatGPT 实例继续运行。托盘中的“退出 ApiCodex 管理器”只退出启动器本身，也不会关闭任何 ChatGPT；要停止实例必须在对应实例菜单中显式操作。

窗口标题、聚焦和停止都只作用于状态脚本已验证的官方 `ChatGPT.exe` 与精确 `--user-data-dir` 所属进程。无法同时确认这些条件时，操作会拒绝执行。

## 开发运行

```powershell
dotnet run --project windows\launcher\CodexDreamSkin.Launcher\CodexDreamSkin.Launcher.csproj
```

也可以运行：

```powershell
pwsh -NoProfile -File windows\launcher\start-launcher.ps1
```

## 测试与发布

```powershell
dotnet test windows\launcher\CodexDreamSkin.Launcher.Tests\CodexDreamSkin.Launcher.Tests.csproj
pwsh -NoProfile -File windows\launcher\build-launcher-release.ps1
```

发布物位于 `windows\launcher\release`，保留其中目录结构后可直接双击 `CodexDreamSkin.Launcher.exe`。默认发布为自包含 `win-x64`，目标机器无需预装 .NET Desktop Runtime。
