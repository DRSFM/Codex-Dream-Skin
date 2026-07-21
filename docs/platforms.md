# 平台对照

## 运行模型（两边相同）

```text
用户本机主题工具
    │  启动官方 Codex + 本机 CDP
    ▼
官方 Codex Desktop（不改 asar / 签名）
    │  注入 CSS + 装饰 DOM
    ▼
仍用原生侧栏 / 输入框 / 建议卡
```

## 路径速查

### macOS

| 用途 | 路径 |
|------|------|
| 源码（本整理包） | `Codex-Dream-Skin/macos/` |
| 安装后引擎 | `~/.codex/codex-dream-skin-studio` |
| 状态 / 日志 | `~/Library/Application Support/CodexDreamSkinStudio` |
| Codex 配置 | `~/.codex/config.toml`（仅外观相关项可能被改，可恢复） |

### Windows

| 用途 | 路径 |
|------|------|
| 源码（本整理包） | `Codex-Dream-Skin/windows/` |
| 工具快捷方式 | `Codex-Dream-Skin/windows/shortcuts/`（桌面仅保留主启动入口） |
| 默认实例状态 / 日志 | `%LOCALAPPDATA%\CodexDreamSkin` |
| 非默认实例状态 / 日志 | `%LOCALAPPDATA%\CodexDreamSkin\instances\<id>` |
| 默认实例主题 / 自定义图 | `%LOCALAPPDATA%\CodexDreamSkin\custom` |
| 非默认实例主题 / 自定义图 | `%LOCALAPPDATA%\CodexDreamSkin\instances\<id>\custom` |
| 图形启动器设置 | `%LOCALAPPDATA%\CodexDreamSkin\launcher\settings.json`（仅刷新间隔和实例端口） |
| 图形启动器源码 / 发布物 | `windows\launcher\` / `windows\launcher\release\` |
| 图片显示模式 | `%LOCALAPPDATA%\CodexDreamSkin\custom\image-mode.txt`（`full-window` / `home-card`） |
| Codex 配置 | `%USERPROFILE%\.codex\config.toml` |
| 默认 CDP 端口 | 首选 `9335`，冲突时自动选空闲口（Mac 包默认从 `9341` 起） |

## 能力矩阵

| 功能 | macOS | Windows |
|------|:-----:|:-------:|
| 安装脚本 | ✅ | ✅ |
| 启动 + 注入 | ✅ | ✅ |
| 一键恢复 | ✅ | ✅ |
| 实机 verify / 截图 | ✅ | ✅ |
| 用户选图定制 | ✅ | ✅ PNG/JPEG/WebP，≤16 MB；整窗或主页卡片 |
| 多主题热切换 | ✅ | ✅ 8 套内置主题 |
| 官方签名校验 | ✅ | Store 签名类型 + 包身份 |
| 客户部署提示词 | ✅ | ❌（可用 Mac 文案改写） |
| 打客户 ZIP | ✅ `build-client-release.sh` | 手动压缩 `windows/` |
| 多实例图形启动器 | ❌ | ✅ WPF，自包含 `win-x64` |

Windows API Desktop profile 由 apicodex 管理 `CODEX_HOME`、keyring 和 Desktop 数据目录；皮肤只接收实例标识、CDP 端口与 `--user-data-dir`，不安装或恢复默认 `C:\Users\<user>\.codex\config.toml`。

## 不要放进这个目录的东西

- API Key、`.codex/auth.json`
- 中转站密钥、服务器私钥
- 含客户隐私的实机截图（若要公开）
