# Progress log

## 2026-07-21T01:33:15.2599105+08:00 — tracking initialized

- Trigger: Created lightweight project-local progress state.
- Observed: .work-progress/ did not previously exist.
- Status changes: Project entered planning state.
- Next: Agree on goal, scope, tasks, and acceptance criteria.

## 2026-07-21T01:34:00+08:00 — anyrouter experiment started

- Trigger: 用户确认以 `anyrouter` 为实验对象开始执行。
- Observed: Git 基线为 `39e4748`；交接文档规定不得影响当前账号登录环境。
- Verified: 基线 Windows 测试此前通过；敏感凭据特征扫描无命中。
- Status changes: T001 `ready` -> `in_progress`；项目进入 active。
- Decisions: 先建立只读基线，再实现隔离；归属不明确的进程不得停止、重启或注入。
- Failures: Windows PowerShell 执行策略拦截测试脚本；PowerShell 7 运行同一测试通过。
- Next: 只读采集当前进程、端口、皮肤状态和 anyrouter 目录元数据。

## 2026-07-21T01:40:10+08:00 — immutable runtime baseline captured

- Observed: 当前有未显式 profile 的 9335 进程树和独立的 `muyuanpub` 进程树；anyrouter Desktop 目录尚不存在。
- Verified: 9335/PID 72796 与 state browser ID 一致；9336 空闲；muyuanpub 根 PID 65900；注入器 PID 38360；背景、state 与启动时间已记录。
- Status changes: T001 `in_progress` -> `done`；T002 `pending` -> `in_progress`。
- Decisions: 多实例归属必须校验官方可执行文件、loopback 端口和祖先进程中的规范化 user-data-dir；anyrouter 使用实例专属 state/log/custom 目录。
- Next: 实现实例目录、profile 过滤、认证环境清除和注入器 custom-root 参数。

## 2026-07-21T02:00:00+08:00 — skin isolation implemented and appearance copied

- Observed: apicodex Desktop 启动器目前直接启动官方 `ChatGPT.exe`，需要最小接入才能把 anyrouter 认证环境交给皮肤启动器。
- Verified: PowerShell/Node 语法通过；Windows 回归测试通过；9335 匹配默认 profile 且拒绝 muyuanpub；全局 state 哈希仍为基线值。
- Status changes: T002、T003、T004 -> `done`；T005 `pending` -> `in_progress`。
- Decisions: anyrouter 外观保存在皮肤实例目录，不写入 Chromium profile；接入层不得把 API Key放入参数、日志或 state。
- Next: 检查 apicodex Git 状态并实现可选 Dream Skin Desktop 启动路径。

## 2026-07-21T02:45:00+08:00 — anyrouter experiment accepted

- Observed: anyrouter 最终根 PID 64028、injector PID 73732；默认 9335 和 anyrouter 9336 均为 loopback；两仓库有未提交实现与文档改动。
- Verified: anyrouter 主页/任务页及默认实例 verify 通过；独立 restore 未改变 9335、PID 72796/65900/38360 或全局 state 哈希；背景哈希一致；敏感扫描无命中；两仓库自动化测试通过。
- Status changes: T005 `in_progress` -> `done`；项目整体进入 complete。
- Decisions: Dream Skin 委托同步等待启动验证；非默认实例不运行默认 installer；外观存放于实例皮肤目录。
- Failures: 旧 PATH apicodex 未加载源码；detached 启动吞错；PowerShell JSON 时间自动转换导致 injector 误判，均已记录并修复或明确后续安装动作。
- Next: 审阅并分别提交两个仓库，之后按需同步 `C:\tools` 安装副本。

## 2026-07-21T10:01:11+08:00 — installed copy synchronized and Git checkpoint started

- Trigger: 用户要求更新旧副本并更新 Git 状态。
- Observed: `C:\tools\apiagent.py` 旧 SHA-256 为 `079E40FEC8E148332C846FB6B44581BFB01A472BD965321292F4926196FE1BA0`，与已验证源码不同。
- Verified: 旧文件备份到 `C:\tools\apiagent.py.backup-20260721-095857`；同步后安装副本与源码 SHA-256 均为 `708FA7E07B95A7A1F53A8AE59B58F91C05E1E66A61BE3584034B3BD333A2ABDB`；`python -m py_compile C:\tools\apiagent.py` 与 `apicodex --api-help` 通过。
- Verified: apicodex 16 项认证测试、皮肤 Windows 回归测试、Node 语法和两仓库 `git diff --check` 再次通过；9335/9336 监听 PID 与五个基线进程均未变化。
- Status changes: apicodex 改动已提交为 `8c3fc96`；皮肤仓库进入提交检查点。
- Decisions: 只同步 `apiagent.py` 源码，不复制 profile、凭据、`auth.json`、keyring 或 Desktop 数据；不推送远端。
- Next: 校验进度文件、保存工作区快照并提交皮肤仓库。

## 2026-07-21T10:47:40+08:00 — graphical launcher implementation started

- Trigger: 用户要求按照参考图完成通用图形启动器。
- Observed: 参考图采用账号侧栏、实例表格和详情配置三栏；用户明确不要预设上游名称，视觉要求干净、现代、微粉色。
- Verified: 本机已有 .NET Windows Desktop、PowerShell、Python、Node 和 Git；两个相关仓库工作区干净；现有实例隔离后端可复用。
- Status changes: 旧 anyrouter 实验保持完成证据；当前项目切换为 Codex Dream Skin 图形启动器，T101 完成，T102 开始。
- Decisions: 使用 .NET 8 WPF；GUI 只读取非敏感 JSON profile 元数据并调用受控 PowerShell/apicodex 入口；不读取凭据。
- Next: 实现 apicodex JSON profile 接口与对应测试。

## 2026-07-21T13:08:00+08:00 — graphical launcher verified

- Implemented: 完成 apicodex schema v1 `--api-list --json`、实例级外观/状态脚本、WPF 三栏启动器、搜索 ID、可执行发布脚本和文档。
- Verified: WPF 4 项测试、apicodex Python 23 项测试、Windows PowerShell 回归、Node 检查和自包含 release 构建通过。
- Verified: 发布版 UI Automation 确认搜索 `default` 命中 1 行、刷新完成、4 行实例、无错误对话框、首行验证按钮可用；添加/编辑均拉起新 Python 交互进程，未输入凭据即终止，未提交 profile 变更。
- Verified: 9335/9336 仍绑定 `127.0.0.1`，PID 72796/64028；默认/anyrouter injector PID 38360/73732；muyuanpub PID 65900；24 个启动器和皮肤数据文件敏感模式扫描 0 命中。
- Fixed: 批量状态改用一次 Windows PowerShell WMI + `netstat -ano` 快照，避免重复 CIM/NetTCP 查询超时；图片工具兼容 Windows PowerShell 5 的 UTF-8 BOM 和普通字符串提示。
- Fixed: 含下划线或点号的旧 profile ID 在 JSON 与 Desktop Dream Skin 委托中统一使用安全派生实例 ID，同时保留原 Desktop 数据目录；集成测试覆盖 `legacy_profile`。
- Verified: `C:\tools\apiagent.py` 已备份到 `apiagent.py.backup-20260721-131839` 并同步；源码/安装副本 SHA-256 均为 `499844142018A5A8BBD68DD3D8DFCC735996F5B99559D679F1BD96F0D6BE8B72`，schema v1 列表契约可用。
- Status changes: T102、T103、T104、T105、T106 -> `done`；项目进入 review，等待提交前 Git 审查。
- Next: 审查两个仓库 diff，分别创建本地提交，不推送。

## 2026-07-21T13:22:00+08:00 — local commits created

- Verified: 皮肤仓库提交信息为 `feat(windows): add multi-instance desktop launcher`，apicodex 提交为 `56ab400`；两个仓库均未推送。
- Verified: 发布物 `windows/launcher/release/CodexDreamSkin.Launcher.exe` 保留；9335/9336 仍为 loopback，PID 72796/64028 未变化。
- Status changes: 项目保持 `review`，剩余事项仅为用户对发布版视觉的最终确认。
