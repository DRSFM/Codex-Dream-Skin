# apicodex anyrouter 背景复用实验交接

## 目标

在不复制当前账号登录状态、Cookie、会话记录或 API 凭据的前提下：

1. 保留当前 `muyuanpub` API Desktop 继续运行。
2. 新开 `anyrouter` API Desktop。
3. 让 `anyrouter` 复用当前 Dream Skin 的背景图片、背景显示模式和主题效果。
4. 让两个桌面实例使用不同的 Codex 配置目录、桌面数据目录、CDP 端口和注入器状态。

这次实验的核心是“复用外观资源”，不是复制登录环境。

## 当前工作区

- 皮肤仓库：`E:\新版codex工作区\codex皮肤`
- apicodex 仓库：`D:\codex项目\apiclaude-codex`
- 当前皮肤仓库存在用户未提交改动。不要执行 `git reset`、`git checkout` 或覆盖这些改动。

## 已确认的本机状态

- 官方 Store Codex 已安装，版本：`26.715.7063.0`
- Node.js：`v24.18.0`
- 当前 Dream Skin 注入器端口：`9335`
- 当前状态文件：`%LOCALAPPDATA%\CodexDreamSkin\state.json`
- 当前注入器 PID：`38360`（启动时记录值，使用前应重新检查）
- 当前活动主题：`crystal-clear`
- 当前背景模式：`full-window`
- 当前背景资源：`%LOCALAPPDATA%\CodexDreamSkin\custom\custom-image.jpg`

当前用户说明正在使用 `muyuanpub` 的 apicodex Desktop。但现有皮肤状态中的 `profilePath` 为空，说明这次皮肤启动没有记录显式 `--user-data-dir`。在修改前应重新确认当前窗口实际使用的数据目录，不要只根据状态文件推断。

## apicodex profile 路径

根据当前 `profiles.json`：

| profile | `CODEX_HOME` | Desktop 数据目录 |
|---|---|---|
| `anyrouter` | `C:\Users\SFM\.codex-api` | `C:\Users\SFM\.apicodex-desktop\anyrouter` |
| `muyuanpub` | `C:\Users\SFM\.codex-api\profiles\muyuanpub` | `C:\Users\SFM\.apicodex-desktop\muyuanpub` |

`anyrouter` 的 API 配置和密钥必须继续由 apicodex 管理。皮肤仓库不得读取、复制或写入 API Key、`auth.json`、Cookie 或完整浏览器数据目录。

## 为什么不能直接再次运行现有启动脚本

现有 Windows 启动器默认是单实例状态模型：

- 全局使用一个 `state.json`。
- 默认使用一个 CDP 端口 `9335`。
- 默认使用一套注入器日志和进程记录。
- 进程发现逻辑主要按官方 `ChatGPT.exe` 判断，尚未可靠按 `--user-data-dir` 区分多个 profile。

因此，在当前 `muyuanpub` 仍运行时，直接执行：

```powershell
windows\scripts\start-dream-skin.ps1 -Port 9336 -ProfilePath C:\Users\SFM\.apicodex-desktop\anyrouter
```

不能直接视为安全方案。它可能重新附着现有实例、误判已有 Codex 进程，或者覆盖全局皮肤状态。完成多实例改造前不要用这条命令做正式实验。

## 推荐改造边界

### 1. 先改本仓库

优先修改以下 Windows 皮肤代码：

- `windows/scripts/start-dream-skin.ps1`
  - 增加 profile 或 instance 标识。
  - 为 `muyuanpub` 和 `anyrouter` 使用不同 CDP 端口，例如 `9335`、`9336`。
  - 为每个实例使用独立状态、日志、备份和注入器记录。
- `windows/scripts/common-windows.ps1`
  - 进程发现、端口归属和停止逻辑必须同时校验可执行文件、端口和 `--user-data-dir`。
  - 停止 `anyrouter` 时不能匹配并停止 `muyuanpub`。
- `windows/scripts/install-dream-skin.ps1` 与 `restore-dream-skin.ps1`
  - 外观配置和备份按实例/profile 隔离。
  - 不得把 anyrouter 的外观安装写到普通账号的 `C:\Users\SFM\.codex\config.toml`。
- `windows/tests/`
  - 增加两个实例并行、独立停止、独立恢复和端口冲突测试。

背景图片本身可以继续从现有的 `%LOCALAPPDATA%\CodexDreamSkin\custom` 读取，两边共享只读外观资源即可，不需要复制图片到 API profile 目录。

### 2. 后改 apicodex 仓库

本次实验验证成功后，再修改 `D:\codex项目\apiclaude-codex`，让 `apicodex --desktop` 调用多实例皮肤启动器。apicodex 负责：

- 选择 profile。
- 准备对应 `CODEX_HOME`。
- 完成该 profile 的 keyring 登录。
- 传入对应的 Desktop 数据目录。

皮肤仓库负责：

- 启动带 CDP 的官方 Codex。
- 绑定指定实例的端口和数据目录。
- 注入 CSS、背景图和 DOM。
- 维护该实例的状态和恢复流程。

## API Key 进程边界

apicodex 当前会为 Desktop 进程设置 `CODEX_HOME` 和 `APICODEX_API_KEY`。联合时不能让 API Key 无限制地继承到 Node 注入器：

1. API Key 只应在启动对应 `ChatGPT.exe` 时使用。
2. 启动 Codex 后，启动 Node 注入器前清除 `APICODEX_API_KEY` 及相关认证变量。
3. API Key 不得出现在 PowerShell 命令行参数、注入器参数、日志或状态 JSON 中。

## 实验验收标准

完成后需要逐项确认：

- `muyuanpub` 窗口仍然打开，原背景和会话不受影响。
- `anyrouter` 使用自己的 API 配置和自己的 Desktop 数据目录。
- 两个实例分别监听不同的 loopback CDP 端口。
- `anyrouter` 显示与当前实例相同的 `custom-image.jpg` 背景。
- 关闭或恢复 `anyrouter` 时，`muyuanpub` 不被关闭、不重新注入、不改变状态。
- 任意状态文件中没有 API Key、Cookie 或完整登录数据。
- 皮肤测试和 apicodex 现有测试均通过。

## 暂不执行的操作

- 不复制 `C:\Users\SFM\.codex`。
- 不复制 `%APPDATA%` 或 `%LOCALAPPDATA%` 下的完整 Codex/Chromium 用户数据。
- 不复制 `auth.json`、Cookie、session、keyring 文件。
- 不直接关闭当前 `muyuanpub`，除非单实例兼容方案无法验证且用户明确同意。
- 不修改 apicodex 仓库，直到本仓库的双实例注入方案先验证通过。

## 相关入口

- `windows/scripts/start-dream-skin.ps1`
- `windows/scripts/common-windows.ps1`
- `windows/scripts/injector.mjs`
- `windows/assets/renderer-inject.js`
- `windows/assets/dream-skin.css`
- `windows/scripts/install-dream-skin.ps1`
- `windows/scripts/restore-dream-skin.ps1`
