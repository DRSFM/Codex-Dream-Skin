using System.Diagnostics;

namespace CodexDreamSkin.Launcher.Services;

public sealed record ProcessResult(int ExitCode, string StandardOutput, string StandardError);

public sealed class ProcessRunner
{
    private static readonly string[] AuthenticationEnvironmentNames =
    [
        "APICODEX_API_KEY",
        "OPENAI_API_KEY",
        "CODEX_API_KEY",
        "CODEX_AUTH_TOKEN",
        "OPENAI_AUTH_TOKEN",
        "OPENAI_BASE_URL",
    ];

    public async Task<ProcessResult> RunAsync(
        string fileName,
        IEnumerable<string> arguments,
        IReadOnlyDictionary<string, string>? environment = null,
        TimeSpan? timeout = null,
        CancellationToken cancellationToken = default)
    {
        var startInfo = CreateStartInfo(fileName, arguments, environment);
        startInfo.RedirectStandardOutput = true;
        startInfo.RedirectStandardError = true;
        startInfo.CreateNoWindow = true;
        startInfo.WindowStyle = ProcessWindowStyle.Hidden;

        using var process = new Process { StartInfo = startInfo };
        if (!process.Start())
        {
            throw new InvalidOperationException($"无法启动进程：{fileName}");
        }

        var outputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);
        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutSource.CancelAfter(timeout ?? TimeSpan.FromMinutes(2));
        try
        {
            await process.WaitForExitAsync(timeoutSource.Token);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            TryKill(process);
            throw new TimeoutException($"进程执行超时：{Path.GetFileName(fileName)}");
        }

        return new ProcessResult(process.ExitCode, await outputTask, await errorTask);
    }

    public async Task RunInteractiveAsync(
        string fileName,
        IEnumerable<string> arguments,
        CancellationToken cancellationToken = default)
    {
        var startInfo = CreateStartInfo(fileName, arguments, null);
        startInfo.CreateNoWindow = false;
        startInfo.WindowStyle = ProcessWindowStyle.Normal;
        using var process = new Process { StartInfo = startInfo };
        if (!process.Start())
        {
            throw new InvalidOperationException($"无法打开交互窗口：{fileName}");
        }
        await process.WaitForExitAsync(cancellationToken);
    }

    private static ProcessStartInfo CreateStartInfo(
        string fileName,
        IEnumerable<string> arguments,
        IReadOnlyDictionary<string, string>? environment)
    {
        var startInfo = new ProcessStartInfo(fileName)
        {
            UseShellExecute = false,
            WorkingDirectory = Environment.CurrentDirectory,
        };
        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }
        foreach (var name in AuthenticationEnvironmentNames)
        {
            startInfo.Environment.Remove(name);
        }
        if (environment is not null)
        {
            foreach (var pair in environment)
            {
                startInfo.Environment[pair.Key] = pair.Value;
            }
        }
        return startInfo;
    }

    private static void TryKill(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
        catch
        {
            // The timeout remains the actionable failure if the process exited concurrently.
        }
    }
}
