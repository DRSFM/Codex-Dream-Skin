# Current state

- Project: Codex Dream Skin 图形启动器
- Mode: code
- Last updated: 2026-07-26T11:38:00+08:00
- Overall status: review

## Current focus
统一托盘、窗口标记/聚焦、安全停止和后台生命周期已完成并通过实机验收；发布版正在运行，等待用户查看托盘菜单与最终视觉。

## Verified progress
- 用户参考图已检查，目标为 Windows 三栏实例管理器：账号/实例导航、状态列表、实例详情和外观维护。
- 用户要求通用逻辑，不预设或硬编码具体 API 上游名称；视觉为干净、现代、克制的微粉色。
- 当前机器有 .NET SDK 9.0.201、WindowsDesktop 8/9、PowerShell 7.6.3、Python 3.13.1、Node 24.18.0 和 npm 11.16.0。
- 现有 Dream Skin 已支持实例级 state/log/custom、profile 归属、独立 CDP、启动、验证和恢复。
- apicodex 已提供 schema v1 非敏感 `--api-list --json`，启动器通过安全的 profile ID 委托添加、编辑、移除和 Desktop 启动。
- WPF 启动器已发布为 `windows/launcher/release/CodexDreamSkin.Launcher.exe`，自包含 win-x64，动态实例列表和微粉色三栏 UI 已通过 UI Automation。
- 批量状态使用一次性 Windows PowerShell 进程/监听快照，实机状态查询约 6 秒且结果准确；避免 PowerShell 7 CIM 线程耗尽导致超时。
- Windows 回归、Node 检查、WPF 4 项测试、apicodex Python 23 项测试和发布构建均通过。
- 9335/9336 loopback PID、默认/anyrouter state injector PID、muyuanpub PID 在 GUI 只读与终端冒烟操作前后保持不变；敏感数据扫描无命中。
- `DesktopWindowService` 只接收批量状态已验证的 PID，并排除 owner、tool window、不可见窗口和非 `ChatGPT` 标题；账号标题固定为 `ChatGPT`，API 标题为 `ChatGPT (Profile名)`。
- `TrayIconController` 提供动态实例菜单、启动、聚焦、停止、重启、刷新、打开面板和退出管理器；主窗口关闭后隐藏，退出管理器不关闭 ChatGPT。
- 无 Dream Skin state 的 Desktop 使用 `stop-codex-instance.ps1`，仍要求官方 Store 可执行文件和精确 `--user-data-dir`；有 state 的实例继续走完整 restore 清理。
- 实机先以 PID 54728 验证关闭隐藏与二次启动唤回，最终重建后的发布版以 PID 55592 运行；anyrouter/prism/muyuanpub/wuming 标题正确，账号仍为 `ChatGPT`。
- WPF 6 项、Windows/Node 回归、11 个 PowerShell 脚本解析、ApiCodex 全套 80 项、py_compile/pyflakes 和两仓库 `git diff --check` 通过；自包含 win-x64 release 已重建。

## Observed but unverified
- 用户尚未对发布版视觉截图做最终主观确认；代码侧 UI Automation 已确认无错误对话框、4 行实例、搜索、刷新和操作按钮状态。
- 当前工作树保留并包含另一个 agent 的新版 Codex 慢启动兼容改动；本轮未覆盖或回退这些内容。

## Blockers and open questions
- 无代码阻塞项。本轮改动尚未提交或推送；发布版已启动供用户验收。

## Relevant artifacts
- `windows/scripts/start-dream-skin.ps1` - 已验证的实例启动入口。
- `windows/scripts/restore-dream-skin.ps1` - 已验证的实例停止和恢复入口。
- `windows/scripts/verify-dream-skin.ps1` - 已验证的实例检查入口。
- `windows/scripts/common-windows.ps1` - 进程、端口和 profile 归属安全逻辑。
- `windows/scripts/stop-codex-instance.ps1` - 无皮肤 state 实例的精确停止入口。
- `windows/launcher/CodexDreamSkin.Launcher/Services/DesktopWindowService.cs` - 标题与聚焦。
- `windows/launcher/CodexDreamSkin.Launcher/Services/TrayIconController.cs` - 统一托盘。
- `D:\codex项目\apiclaude-codex\apiagent.py` - profile 元数据和安全认证入口。
- `C:\Users\SFM\AppData\Local\Temp\codex-clipboard-73ffcc60-6e6f-497d-a4df-6a0527eed0cb.png` - 用户提供的界面参考。

## Failed approaches
- 发布脚本参数默认值在 PowerShell 参数绑定阶段使用 `$PSScriptRoot`，导致空路径；已改为脚本体内解析。
- PowerShell 7 批量重复 CIM/NetTCP 查询在实机偶发超时；已改为 Windows PowerShell 单次 WMI + netstat 快照并复用。
- Windows PowerShell 5 无 BOM 解析根图片工具的中文 here-string 失败；已改为普通字符串数组并给脚本加 UTF-8 BOM，Windows 回归恢复通过。

## Next action
用户查看当前运行的发布版托盘菜单；确认视觉后可按用户要求分别提交两个仓库，本轮不自动推送。
