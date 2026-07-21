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
