# Current state

- Project: Anyrouter Dream Skin 多实例实验
- Mode: code
- Last updated: 2026-07-21T10:01:11+08:00
- Overall status: complete

## Current focus
实验、旧安装副本同步和本地 Git 整理已完成。anyrouter 当前使用独立 profile、9336、state/custom/log 和 injector 运行；默认 9335 与 muyuanpub 基线保持不变。

## Verified progress
- 当前改动前 Git 基线为 `39e4748 feat(windows): add themes and custom backgrounds`，工作区此前干净。
- 当前 Windows 回归测试已在基线提交前通过。
- 2026-07-21 01:40 基线：9335 监听 PID 72796，browser ID 与全局 state 一致；PID 72796 无显式 profile。
- `muyuanpub` 独立根进程 PID 65900，user-data-dir 为 `C:\Users\SFM\.apicodex-desktop\muyuanpub`，没有占用 9335。
- 当前注入器 PID 38360；全局 state SHA-256 为 `FC1DFB55A63135837E581EF565AAA3707ADC333D3FB4059EAE656850CCCBBBDA`。
- 当前背景 SHA-256 为 `45EAFFAE3A3ADBE39406C854EFCB4D41ED1631CCE8B54EC62FEE8F55A4F8C3D9`，模式 `full-window`，主题 `crystal-clear`。
- 实验前 9336 空闲，且 `C:\Users\SFM\.apicodex-desktop\anyrouter` 不存在；启动前终端没有 `APICODEX_API_KEY`。
- 实例隔离代码已实现并通过 Windows 回归测试、PowerShell/Node 语法和 9335 profile 归属实机只读验证。
- anyrouter 外观已复制到 `%LOCALAPPDATA%\CodexDreamSkin\instances\anyrouter\custom`，图片哈希与当前背景一致。
- anyrouter 主页和任务页 verify 均通过；独立 restore 后默认实例与 muyuanpub 未变化，随后已重新启动 anyrouter。
- 最终 anyrouter 根 PID 64028、injector PID 73732；9335/9336 均为 loopback；敏感扫描无命中。
- Windows 回归测试、Node/PowerShell 语法、默认/anyrouter 实机 verify 和 apicodex 16 项认证测试全部通过。
- 已将验证过的 `apiagent.py` 同步到 `C:\tools`；安装副本与源码 SHA-256 均为 `708FA7E07B95A7A1F53A8AE59B58F91C05E1E66A61BE3584034B3BD333A2ABDB`。
- 旧安装副本保存在 `C:\tools\apiagent.py.backup-20260721-095857`；安装副本编译和 `apicodex --api-help` 通过，未启动或重启 Desktop。
- apicodex 改动已提交为 `8c3fc96 feat(codex): delegate desktop launch to Dream Skin`。

## Observed but unverified
- 两个仓库的本地提交均未推送远端。

## Blockers and open questions
- 无阻塞项。远端推送不在本次范围内。

## Relevant artifacts
- `docs/APICODEX-ANYROUTER-HANDOFF.md` - 安全边界和实验验收标准。
- `windows/scripts/start-dream-skin.ps1` - Windows 启动和注入入口。
- `windows/scripts/common-windows.ps1` - 进程、端口和 Store 包公共逻辑。
- `windows/scripts/copy-dream-skin-instance-appearance.ps1` - 仅复制实例外观资源。
- `D:\codex项目\apiclaude-codex\apiagent.py` - apicodex 可选 Dream Skin 委托入口。
- `%LOCALAPPDATA%\CodexDreamSkin\state.json` - 当前单实例皮肤状态，只读基线来源。

## Failed approaches
- `powershell -NoProfile -File windows\tests\run-tests.ps1` 被本机执行策略拦截；改用 `pwsh -NoProfile` 后测试通过。
- PATH 中旧 `C:\tools\apicodex.bat` 未加载源码改动，只启动了无 CDP 的 anyrouter；改用源码入口后成功。
- 完全 detached 的 Dream Skin 委托吞掉启动错误；改为同步等待启动验证并返回真实退出码。
- PowerShell 7 将 state ISO 时间解析为 `DateTime`，导致 injector 启动时间误判；读取时规范化 UTC ISO 后修复，并清理了 anyrouter 孤立 watcher。

## Next action
保持两个仓库不推送，等待用户决定是否进入远端同步或下一轮 anyrouter 实验。
