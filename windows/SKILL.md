---
name: codex-dream-skin
description: Apply, launch, verify, repair, update, or restore a full decorative skin for the Windows Codex desktop app. Use when the user asks for a Codex theme that goes beyond official color settings, wants the pink-purple Dream/Fiona-style interface, needs the skin reapplied after a Codex update, or needs a safe rollback without modifying WindowsApps or app.asar.
---

# Codex Dream Skin

Apply a reversible renderer skin through Chromium DevTools Protocol while launching the official Store-installed Codex executable. Never replace or take ownership of files under `WindowsApps`.

## Workflow

1. Install Node.js 22 or newer, close Codex, then run `scripts/install-dream-skin.ps1` once to set the matching official base colors. It creates only the main launch shortcut on the desktop and keeps install, restore, theme, and image shortcuts under `shortcuts/`.
2. Run `scripts/start-dream-skin.ps1`. The shortcut asks before restarting an already-open Codex app; CLI callers must explicitly add `-RestartExisting`.
3. Use the repository image shortcut to choose either `full-window` presentation or the backward-compatible `home-card` presentation. The watcher reapplies valid image, theme, and presentation changes to the live renderer.
4. Run `scripts/verify-dream-skin.ps1 -ScreenshotPath <absolute-path>` after launch. Treat a missing hero, native composer, sidebar skin, or injection marker as failure. The native suggestion count is responsive and may be two to four.
5. Inspect the screenshot against `references/qa-inventory.md`. Verify both the home screen and a normal task before signing off.
6. Run `scripts/restore-dream-skin.ps1` to remove the live skin, close the saved CDP session, and reopen Codex normally. Add `-RestoreBaseTheme` to restore only saved appearance keys, `-RecoverConfigBackup` for explicit byte-for-byte recovery of a damaged config, or `-Uninstall` to delete shortcuts. A completed config restore archives that install's backup so a later install captures a fresh baseline.

For an isolated API Desktop profile, do not run the default installer. Copy appearance with `scripts\copy-dream-skin-instance-appearance.ps1`, then let the profile launcher call `scripts\start-dream-skin.ps1 -InstanceId <id> -Port <loopback-port> -ProfilePath <desktop-data-dir>`. Restore with the same `-InstanceId`; non-default restore never edits the default Codex config.

For a graphical multi-instance workflow, run `launcher\start-launcher.ps1` during development or build the self-contained release with `launcher\build-launcher-release.ps1`. The release is `launcher\release\CodexDreamSkin.Launcher.exe` plus its copied `windows\` runtime directory. The launcher reads only the non-sensitive result of `apicodex --api-list --json`, protects the default account from profile management, and routes start, stop, verify, restore, port, background, theme, and display-mode operations through the instance-scoped scripts.

## Guardrails

- Preserve the official executable, package signature, user threads, pets, plugins, and authentication state.
- Do not use a screenshot containing UI as a fake whole-window overlay. Full-window mode accepts a pure background image and keeps all Codex controls live.
- Keep `home-card` as the compatibility path for the existing top banner and decorative crop. In `full-window`, paint the selected image once on the native window and use transparent readability layers instead of repeating it in every panel.
- Attach the "选择项目" treatment to Codex's real project-selector toolbar and keep the current project button clickable; never draw a disconnected replacement.
- Keep decorative layers `pointer-events: none` and keep real buttons, navigation, and composer above them.
- On app updates, rerun install and launch; the scripts discover the current Appx package dynamically. Saved paths are never trusted for process control unless they still match a registered package identity.
- For isolated instances, process control also requires the ancestor process tree's normalized `--user-data-dir` to match the saved profile path; a matching executable or port alone is insufficient.
- API credentials may be inherited only while launching the requested Codex Desktop. The injector is started after authentication variables are temporarily removed from its process environment, and those variables never enter arguments, logs, or state.
- The default launcher scans for a free port when `9335` is occupied. An explicitly requested occupied port fails closed.
- Keep the injection daemon running for navigation/reload resilience. Its state and logs live under `%LOCALAPPDATA%\CodexDreamSkin`.
- CDP targets must use a same-port loopback WebSocket, belong to the current Store package, retain the launch-time Browser ID, and expose expected Codex renderer markers.
- Loopback prevents LAN exposure, but Chromium CDP has no same-user authentication. Run only trusted local software while the skin is active, and use restore to close the debug session when it is no longer needed.
- Preserve `config.toml` as strict UTF-8. Never use encoding-dependent whole-file PowerShell reads/writes, silently transcode UTF-16, or overwrite a file that changed after it was read. Ambiguous TOML shapes must fail before writing rather than receive a best-effort rewrite.
- Keep install/start/restore/verify serialized with the per-user operation lock in `common-windows.ps1`.
- Treat `launcher\release` as a portable directory: keep the executable beside its `windows\scripts`, `windows\assets`, and `windows\themes` folders.

## Checks

```powershell
pwsh -NoProfile -File tests\run-tests.ps1
node --check scripts\injector.mjs
node --check assets\renderer-inject.js
```

## Resources

- `scripts/injector.mjs`: CDP connection, renderer injection, verification, screenshot, and removal.
- `scripts/common-windows.ps1`: Store-package discovery, Node validation, port ownership, state, and process identity safety.
- `scripts/config-utf8.ps1`: atomic UTF-8 configuration backup, selective restore, and explicit recovery.
- `assets/dream-skin.css`: full visual layer.
- `assets/renderer-inject.js`: idempotent DOM integration and cleanup.
- `assets/dream-reference.png`: bundled compatibility image used by the default home-card presentation.
- `references/qa-inventory.md`: required functional and visual signoff coverage.
- `references/runtime-notes.md`: troubleshooting and update behavior.
- `tests/run-tests.ps1`: configuration, state, recovery, payload, and CDP validation regression checks.
