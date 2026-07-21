using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using CodexDreamSkin.Launcher.Models;

namespace CodexDreamSkin.Launcher.Services;

public sealed partial class DreamSkinService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private readonly ProcessRunner runner;
    private readonly ApiCodexService apiCodex;
    private readonly string scriptsRoot;

    public DreamSkinService(ProcessRunner runner, ApiCodexService apiCodex, string repositoryRoot)
    {
        this.runner = runner;
        this.apiCodex = apiCodex;
        scriptsRoot = Path.Combine(repositoryRoot, "windows", "scripts");
    }

    public string StartScript => Path.Combine(scriptsRoot, "start-dream-skin.ps1");

    public async Task<DreamSkinStatus> GetStatusAsync(
        string instanceId,
        int port,
        string? profilePath,
        CancellationToken cancellationToken = default)
    {
        ValidateInstance(instanceId, port, profilePath);
        var arguments = new List<string>
        {
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
            Path.Combine(scriptsRoot, "get-dream-skin-instance-status.ps1"),
            "-InstanceId", instanceId,
            "-Port", port.ToString(),
        };
        if (!string.IsNullOrWhiteSpace(profilePath))
        {
            arguments.AddRange(["-ProfilePath", profilePath]);
        }
        var result = await runner.RunAsync("pwsh.exe", arguments, cancellationToken: cancellationToken);
        EnsureSuccess(result, "读取实例状态");
        var status = JsonSerializer.Deserialize<DreamSkinStatus>(result.StandardOutput, JsonOptions)
            ?? throw new InvalidDataException("状态脚本返回了空数据。");
        if (status.SchemaVersion != 1 || status.InstanceId != instanceId)
        {
            throw new InvalidDataException("状态脚本返回了不匹配的实例数据。");
        }
        return status;
    }

    public async Task<IReadOnlyList<LauncherStatusItem>> GetStatusesAsync(
        IEnumerable<(string InstanceId, int Port, string? ProfilePath)> instances,
        CancellationToken cancellationToken = default)
    {
        var requested = instances.ToArray();
        foreach (var instance in requested)
        {
            ValidateInstance(instance.InstanceId, instance.Port, instance.ProfilePath);
        }
        var requestRoot = Path.Combine(Path.GetTempPath(), "CodexDreamSkinLauncher");
        Directory.CreateDirectory(requestRoot);
        var requestPath = Path.Combine(requestRoot, $"status.{Environment.ProcessId}.{Guid.NewGuid():N}.json");
        try
        {
            var payload = new
            {
                schemaVersion = 1,
                instances = requested.Select(instance => new
                {
                    instanceId = instance.InstanceId,
                    port = instance.Port,
                    profilePath = instance.ProfilePath,
                }),
            };
            var json = JsonSerializer.Serialize(payload) + Environment.NewLine;
            await File.WriteAllTextAsync(requestPath, json, new UTF8Encoding(false, true), cancellationToken);
            var result = await runner.RunAsync(
                "pwsh.exe",
                [
                    "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                    Path.Combine(scriptsRoot, "get-dream-skin-launcher-status.ps1"),
                    "-RequestPath", requestPath,
                ],
                timeout: TimeSpan.FromSeconds(75),
                cancellationToken: cancellationToken);
            EnsureSuccess(result, "批量读取实例状态");
            var envelope = JsonSerializer.Deserialize<LauncherStatusEnvelope>(result.StandardOutput, JsonOptions)
                ?? throw new InvalidDataException("批量状态脚本返回了空数据。");
            if (envelope.SchemaVersion != 1 || envelope.Instances.Count != requested.Length)
            {
                throw new InvalidDataException("批量状态脚本返回了不完整的数据。");
            }
            return envelope.Instances;
        }
        finally
        {
            if (File.Exists(requestPath))
            {
                File.Delete(requestPath);
            }
        }
    }

    public async Task SetAppearanceAsync(
        string instanceId,
        string? imagePath,
        bool clearImage,
        string mode,
        string themeId,
        CancellationToken cancellationToken = default)
    {
        ValidateInstanceId(instanceId);
        if (mode is not ("full-window" or "home-card") || !ThemeIdPattern().IsMatch(themeId))
        {
            throw new InvalidOperationException("外观参数不安全。");
        }
        var arguments = new List<string>
        {
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
            Path.Combine(scriptsRoot, "set-dream-skin-instance-appearance.ps1"),
            "-InstanceId", instanceId,
            "-Mode", mode,
            "-ThemeId", themeId,
        };
        if (!string.IsNullOrWhiteSpace(imagePath))
        {
            arguments.AddRange(["-ImagePath", imagePath]);
        }
        if (clearImage)
        {
            arguments.Add("-ClearImage");
        }
        var result = await runner.RunAsync("pwsh.exe", arguments, cancellationToken: cancellationToken);
        EnsureSuccess(result, "更新实例外观");
        var appearance = JsonSerializer.Deserialize<AppearanceResult>(result.StandardOutput, JsonOptions)
            ?? throw new InvalidDataException("外观脚本返回了空数据。");
        if (appearance.SchemaVersion != 1 || appearance.InstanceId != instanceId)
        {
            throw new InvalidDataException("外观脚本返回了不匹配的实例数据。");
        }
    }

    public async Task StartAsync(
        ApiProfileMetadata? profile,
        string instanceId,
        int port,
        CancellationToken cancellationToken = default)
    {
        ValidateInstance(instanceId, port, profile?.DesktopData);
        if (profile is not null)
        {
            await apiCodex.LaunchDesktopAsync(profile, port, StartScript, cancellationToken);
            return;
        }
        var result = await RunScriptAsync(
            "start-dream-skin.ps1",
            ["-InstanceId", "default", "-Port", port.ToString(), "-RestartExisting"],
            cancellationToken);
        EnsureSuccess(result, "启动默认实例");
    }

    public async Task StopAsync(
        string instanceId,
        int port,
        CancellationToken cancellationToken = default)
    {
        ValidateInstanceId(instanceId);
        var result = await RunScriptAsync(
            "restore-dream-skin.ps1",
            ["-InstanceId", instanceId, "-Port", port.ToString(), "-ForceRestart", "-NoRelaunch"],
            cancellationToken);
        EnsureSuccess(result, "停止实例");
    }

    public async Task RestoreWithoutSkinAsync(
        string instanceId,
        int port,
        CancellationToken cancellationToken = default)
    {
        ValidateInstanceId(instanceId);
        var result = await RunScriptAsync(
            "restore-dream-skin.ps1",
            ["-InstanceId", instanceId, "-Port", port.ToString(), "-ForceRestart"],
            cancellationToken);
        EnsureSuccess(result, "恢复无皮肤实例");
    }

    public async Task VerifyAsync(
        string instanceId,
        int port,
        CancellationToken cancellationToken = default)
    {
        ValidateInstanceId(instanceId);
        var result = await RunScriptAsync(
            "verify-dream-skin.ps1",
            ["-InstanceId", instanceId, "-Port", port.ToString()],
            cancellationToken);
        EnsureSuccess(result, "验证实例皮肤");
    }

    public void OpenLogs(string statePath)
    {
        var directory = Path.GetDirectoryName(statePath);
        if (string.IsNullOrWhiteSpace(directory))
        {
            return;
        }
        Directory.CreateDirectory(directory);
        Process.Start(new ProcessStartInfo("explorer.exe", directory) { UseShellExecute = true });
    }

    private Task<ProcessResult> RunScriptAsync(
        string scriptName,
        IReadOnlyList<string> scriptArguments,
        CancellationToken cancellationToken)
    {
        var arguments = new List<string>
        {
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", Path.Combine(scriptsRoot, scriptName),
        };
        arguments.AddRange(scriptArguments);
        return runner.RunAsync("pwsh.exe", arguments, cancellationToken: cancellationToken);
    }

    private static void EnsureSuccess(ProcessResult result, string operation)
    {
        if (result.ExitCode == 0)
        {
            return;
        }
        var message = string.IsNullOrWhiteSpace(result.StandardError)
            ? result.StandardOutput.Trim()
            : result.StandardError.Trim();
        throw new InvalidOperationException($"{operation}失败：{message}");
    }

    private static void ValidateInstance(string instanceId, int port, string? profilePath)
    {
        ValidateInstanceId(instanceId);
        if (port is < 1024 or > 65535)
        {
            throw new InvalidOperationException("实例端口超出安全范围。");
        }
        if (instanceId != "default" && string.IsNullOrWhiteSpace(profilePath))
        {
            throw new InvalidOperationException("API 实例缺少 Desktop 数据目录。");
        }
    }

    private static void ValidateInstanceId(string instanceId)
    {
        if (!InstanceIdPattern().IsMatch(instanceId))
        {
            throw new InvalidOperationException("实例 ID 不安全。");
        }
    }

    [GeneratedRegex(@"^[a-z0-9][a-z0-9-]{0,63}$", RegexOptions.CultureInvariant)]
    private static partial Regex InstanceIdPattern();

    [GeneratedRegex(@"^[a-z0-9][a-z0-9-]{0,79}$", RegexOptions.CultureInvariant)]
    private static partial Regex ThemeIdPattern();
}
