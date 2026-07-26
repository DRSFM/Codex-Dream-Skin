using System.Text.Json;
using System.Text.RegularExpressions;
using CodexDreamSkin.Launcher.Models;

namespace CodexDreamSkin.Launcher.Services;

public sealed partial class ApiCodexService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
    };

    private readonly ProcessRunner runner;
    private readonly string launcherPath;

    public ApiCodexService(ProcessRunner runner)
    {
        this.runner = runner;
        launcherPath = ResolveLauncherPath();
    }

    public string LauncherPath => launcherPath;

    public async Task<IReadOnlyList<ApiProfileMetadata>> ListProfilesAsync(
        CancellationToken cancellationToken = default)
    {
        var result = await RunCapturedAsync(["--api-list", "--json"], null, cancellationToken);
        EnsureSuccess(result, "读取 API profile");
        var payload = JsonSerializer.Deserialize<ApiProfileEnvelope>(result.StandardOutput, JsonOptions)
            ?? throw new InvalidDataException("apicodex 返回了空的 profile 数据。");
        if (payload.SchemaVersion != 1)
        {
            throw new InvalidDataException($"不支持的 apicodex profile schema：{payload.SchemaVersion}");
        }
        foreach (var profile in payload.Profiles)
        {
            ValidateProfile(profile);
        }
        return payload.Profiles;
    }

    public async Task LaunchDesktopAsync(
        ApiProfileMetadata profile,
        int port,
        string dreamSkinScript,
        CancellationToken cancellationToken = default)
    {
        ValidateProfile(profile);
        var environment = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["APICODEX_DREAM_SKIN_SCRIPT"] = dreamSkinScript,
            ["APICODEX_DREAM_SKIN_PORT"] = port.ToString(),
        };
        var result = await RunCapturedAsync(
            ["--desktop", "--api-profile", profile.Id],
            environment,
            cancellationToken,
            TimeSpan.FromMinutes(4));
        EnsureSuccess(result, $"启动 {profile.Name}");
    }

    public Task OpenAddProfileAsync(CancellationToken cancellationToken = default) =>
        RunInteractiveAsync(["--api-add"], cancellationToken);

    public Task OpenEditProfileAsync(ApiProfileMetadata profile, CancellationToken cancellationToken = default)
    {
        ValidateProfile(profile);
        return RunInteractiveAsync(["--api-add", "--api-profile", profile.Id], cancellationToken);
    }

    public Task OpenRemoveProfileAsync(ApiProfileMetadata profile, CancellationToken cancellationToken = default)
    {
        ValidateProfile(profile);
        return RunInteractiveAsync(["--api-remove", "--api-profile", profile.Id], cancellationToken);
    }

    private Task<ProcessResult> RunCapturedAsync(
        IReadOnlyList<string> arguments,
        IReadOnlyDictionary<string, string>? environment,
        CancellationToken cancellationToken,
        TimeSpan? timeout = null)
    {
        var invocation = BuildInvocation(arguments, keepOpen: false);
        return runner.RunAsync(
            invocation.FileName,
            invocation.Arguments,
            environment,
            timeout,
            cancellationToken);
    }

    private Task RunInteractiveAsync(IReadOnlyList<string> arguments, CancellationToken cancellationToken)
    {
        var invocation = BuildInvocation(arguments, keepOpen: true);
        return runner.RunInteractiveAsync(invocation.FileName, invocation.Arguments, cancellationToken);
    }

    private (string FileName, IReadOnlyList<string> Arguments) BuildInvocation(
        IReadOnlyList<string> arguments,
        bool keepOpen)
    {
        if (Path.GetExtension(launcherPath).Equals(".exe", StringComparison.OrdinalIgnoreCase))
        {
            return (launcherPath, arguments);
        }
        var apiAgent = Path.Combine(Path.GetDirectoryName(launcherPath)!, "apiagent.py");
        if (!File.Exists(apiAgent))
        {
            throw new FileNotFoundException("apicodex 批处理旁缺少 apiagent.py。", apiAgent);
        }
        return ("python.exe", new[] { apiAgent, "codex" }.Concat(arguments).ToArray());
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

    private static void ValidateProfile(ApiProfileMetadata profile)
    {
        if (!ProfileIdPattern().IsMatch(profile.Id) || !InstanceIdPattern().IsMatch(profile.InstanceId))
        {
            throw new InvalidDataException("apicodex 返回了不安全的 profile 标识。");
        }
        if (string.IsNullOrWhiteSpace(profile.Name) || string.IsNullOrWhiteSpace(profile.DesktopData))
        {
            throw new InvalidDataException("apicodex profile 缺少必需元数据。");
        }
    }

    private static string ResolveLauncherPath()
    {
        var configured = Environment.GetEnvironmentVariable("APICODEX_LAUNCHER");
        if (!string.IsNullOrWhiteSpace(configured) && File.Exists(configured))
        {
            return Path.GetFullPath(configured);
        }

        var candidates = new List<string>
        {
            @"C:\tools\apicodex.bat",
            @"C:\tools\apicodex.cmd",
            @"C:\tools\apicodex.exe",
        };
        var path = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (var directory in path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            foreach (var fileName in new[] { "apicodex.bat", "apicodex.cmd", "apicodex.exe" })
            {
                candidates.Add(Path.Combine(directory.Trim('"'), fileName));
            }
        }

        var resolved = candidates.FirstOrDefault(File.Exists);
        return resolved is null
            ? throw new FileNotFoundException("找不到 apicodex。可通过 APICODEX_LAUNCHER 指定启动器路径。")
            : Path.GetFullPath(resolved);
    }

    [GeneratedRegex(@"^[a-zA-Z0-9._-]{1,128}$", RegexOptions.CultureInvariant)]
    private static partial Regex ProfileIdPattern();

    [GeneratedRegex(@"^[a-z0-9][a-z0-9-]{0,63}$", RegexOptions.CultureInvariant)]
    private static partial Regex InstanceIdPattern();
}
