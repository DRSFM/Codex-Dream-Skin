# Anyrouter Dream Skin 多实例实验

## Goal
在完全不复制或扰动当前账号登录环境的前提下，让 `anyrouter` API Desktop 使用独立的 Desktop 数据目录、CDP 端口、状态和注入器，并复用当前 Dream Skin 的背景图片、显示模式和主题效果。

## Scope
- In: Windows 皮肤启动、进程发现、端口归属、实例状态、日志、外观资源、停止/恢复和双实例测试；以 `anyrouter` 做实机实验。
- Out: 复制 Cookie、会话、`auth.json`、keyring、API Key 或完整浏览器数据；修改官方 Store 包、`app.asar`、签名、Base URL；在皮肤侧改写 apicodex 认证配置；未经验证修改 apicodex 仓库。

## Definition of done
- 当前账号窗口、登录会话、Desktop 数据目录、CDP 会话和皮肤状态在实验前后保持不受影响。
- `anyrouter` 使用 `C:\Users\SFM\.apicodex-desktop\anyrouter`、独立 loopback CDP 端口和独立皮肤运行状态，并显示当前背景、显示模式和主题。
- 停止或恢复 `anyrouter` 不会停止、重启、重新注入或改写当前账号实例，状态和日志中不含认证数据。
- Windows 自动化测试与双实例实机检查通过。

## Tasks

| ID | Task | Status | Depends on | Acceptance criteria | Evidence |
| --- | --- | --- | --- | --- | --- |
| T001 | 建立当前账号和皮肤运行基线 | done | - | 只读确认当前 Codex PID、命令行、用户数据目录、CDP 端口、状态文件和外观资源，并记录不可变基线 | 2026-07-21 只读基线：9335/PID 72796、muyuanpub/PID 65900、injector/PID 38360；state 与图片 SHA-256 已记录 |
| T002 | 实现实例级状态、日志、端口、进程和外观隔离 | done | T001 | 启动/停止/恢复按实例标识和规范化 user-data-dir 归属；认证变量不传给注入器 | 实现实例 state/log/custom；9335 实机只读验证默认=true、muyuanpub=false；全局 state 哈希未变 |
| T003 | 增加双实例安全回归测试 | done | T002 | 覆盖并行实例、端口冲突、错误 profile 拒绝、独立停止/恢复、状态无凭据；Windows 测试通过 | `pwsh -NoProfile -File windows/tests/run-tests.ps1` 通过；Node/PowerShell 语法通过 |
| T004 | 复制当前外观到 anyrouter 专属资源 | done | T003 | 图片、模式和主题复制到 anyrouter 独立目录，哈希/内容与源一致且未读取登录数据 | anyrouter custom-image SHA-256 `45EA...C3D9`；full-window；crystal-clear |
| T005 | 启动 anyrouter 并验证互不干扰 | done | T004 | anyrouter 实机注入成功；前后基线对比证明当前账号窗口和状态未被改变 | 9336 verify 主页/任务页通过；独立 restore 后 9335/PID/state 基线不变；重新启动成功 |

## Notes
- 当前账号登录安全高于实验进度；任何归属不明确的进程都不得停止、重启或注入。
- CDP 必须仅绑定 loopback；状态、日志和命令行不得出现 API Key、Cookie 或认证内容。
- 当前账号 profile 不能仅根据旧 `state.json` 的空 `profilePath` 推断，必须从实时进程和 CDP 信息交叉确认。
- 当前 Git 基线为 `39e4748`；实验改动保持可审查，不覆盖用户已有工作。
