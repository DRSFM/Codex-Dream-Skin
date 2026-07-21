# Codex Dream Skin 图形启动器

## Goal
按照用户提供的参考图，实现一个干净、现代、微粉色的 Windows 图形启动器，动态管理默认 Codex Desktop 与任意 apicodex API profile，并让每个实例拥有独立的背景、主题、显示模式、端口和运行控制。

## Scope
- In: WPF 三栏界面、动态 profile 发现、搜索与刷新、实例级启动/停止/重启/验证/恢复、背景预览与选择、主题和模式设置、API profile 添加/编辑/移除入口、状态和日志展示、Windows 构建与发布。
- In: apicodex 结构化只读 profile 元数据接口；Dream Skin 实例状态和外观脚本；自动化、视觉与实机隔离验证。
- Out: 在启动器中读取、展示或持久化 API Key、Cookie、`auth.json` 或 keyring 内容；修改官方 Store 包、`app.asar`、签名或 API Base URL；把具体 API 上游名称写死在界面代码中。

## Definition of done
- 启动器达到参考图的三栏信息架构和可用密度，在常用桌面尺寸中无重叠、裁切或空白主视图。
- 默认账号和 API profile 均从本地状态动态生成；代码和演示数据不绑定具体上游名称。
- 每个实例可独立设置背景、主题、模式和端口，并可执行启动、停止、重启、验证与恢复；危险操作有确认和错误反馈。
- 启动器不接触凭据；默认账号、各 API profile 的数据目录、进程、CDP、state、日志和外观保持严格隔离。
- .NET、PowerShell、Node、Python 自动化通过；GUI 截图和实际默认/API 实例隔离检查通过；可生成双击运行的 Windows 发布物。

## Tasks

| ID | Task | Status | Depends on | Acceptance criteria | Evidence |
| --- | --- | --- | --- | --- | --- |
| T101 | 审计现有能力与参考图需求 | done | - | 明确 UI、profile 契约、实例动作、安全边界、开发和验证环境 | 2026-07-21 只读确认参考图、现有脚本、.NET 8/9 WPF runtime、PowerShell/Python/Node 与干净 Git 基线 |
| T102 | 增加 apicodex 结构化 profile 接口 | done | T101 | JSON 只包含非敏感 profile 元数据；添加/编辑/移除可由 GUI 安全委托；测试通过 | `--api-list --json` schema v1、`--api-profile` 委托入口；Python 23 项测试通过 |
| T103 | 增加实例级外观与状态接口 | done | T101 | 任意安全实例 ID 可原子设置/清除图片、主题和模式；状态只读且按 profile/端口验证 | 实例状态/外观脚本、批量快照刷新；Windows 回归测试通过，实机 9335-9338 状态准确 |
| T104 | 实现 WPF 三栏启动器 | done | T102,T103 | 动态列表、详情、预览、搜索、刷新和全部实例动作可用；无硬编码上游 | Release WPF UI Automation：搜索 ID 命中、刷新完成、4 行实例、首行验证按钮可用；添加/编辑终端冒烟通过 |
| T105 | 自动化、视觉和发布验证 | done | T104 | .NET、Python、PowerShell、Node 自动化通过；GUI 实机检查通过；发布物可双击运行 | WPF 4 项、Python 23 项、Windows PowerShell/Node 回归通过；`launcher\release\CodexDreamSkin.Launcher.exe` 自包含发布成功 |
| T106 | 多实例登录安全验收 | done | T105 | 默认账号和至少两个 API profile 的 PID、profile、端口、state 和凭据边界在 GUI 操作前后保持正确 | 9335/9336 loopback PID 72796/64028 不变；state injector PID 38360/73732、muyuanpub PID 65900 不变；24 个数据文件敏感扫描 0 命中 |

## Notes
- 当前账号登录安全高于界面功能；任何无法同时确认官方可执行文件、loopback 端口和 profile 归属的操作必须失败关闭。
- 默认实例 ID 为 `default`；API profile ID 由 apicodex 提供并必须符合安全 slug 规则，端口不允许冲突。
- 启动器配置只保存 UI 偏好、实例端口和非敏感外观元数据，使用严格 UTF-8 和原子写入。
- 皮肤仓库基线 `273c2d4`；apicodex 仓库基线 `8c3fc96`；两个仓库开始时均干净且未推送。
