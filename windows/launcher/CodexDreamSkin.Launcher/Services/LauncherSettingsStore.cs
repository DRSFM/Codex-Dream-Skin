using System.Net.NetworkInformation;
using System.Text;
using System.Text.Json;
using CodexDreamSkin.Launcher.Models;

namespace CodexDreamSkin.Launcher.Services;

public sealed class LauncherSettingsStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
    };

    public string SettingsPath { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "CodexDreamSkin",
        "launcher",
        "settings.json");

    public async Task<LauncherSettings> LoadAsync(CancellationToken cancellationToken = default)
    {
        if (!File.Exists(SettingsPath))
        {
            return new LauncherSettings();
        }

        await using var stream = File.OpenRead(SettingsPath);
        var settings = await JsonSerializer.DeserializeAsync<LauncherSettings>(
            stream, JsonOptions, cancellationToken);
        if (settings is null || settings.SchemaVersion != 1)
        {
            throw new InvalidDataException("启动器设置格式不受支持，原文件未被修改。");
        }
        settings.RefreshSeconds = Math.Clamp(settings.RefreshSeconds, 10, 120);
        settings.Ports = new Dictionary<string, int>(settings.Ports, StringComparer.Ordinal);
        return settings;
    }

    public async Task SaveAsync(LauncherSettings settings, CancellationToken cancellationToken = default)
    {
        var directory = Path.GetDirectoryName(SettingsPath)!;
        Directory.CreateDirectory(directory);
        var temporary = Path.Combine(directory, $".settings.{Environment.ProcessId}.{Guid.NewGuid():N}.tmp");
        try
        {
            var json = JsonSerializer.Serialize(settings, JsonOptions) + Environment.NewLine;
            await File.WriteAllTextAsync(temporary, json, new UTF8Encoding(false, true), cancellationToken);
            File.Move(temporary, SettingsPath, overwrite: true);
        }
        finally
        {
            if (File.Exists(temporary))
            {
                File.Delete(temporary);
            }
        }
    }

    public static int GetOrAssignPort(
        LauncherSettings settings,
        string instanceId,
        int preferredPort,
        ISet<int> reservedPorts)
    {
        if (settings.Ports.TryGetValue(instanceId, out var saved) &&
            saved is >= 1024 and <= 65535 &&
            !reservedPorts.Contains(saved))
        {
            reservedPorts.Add(saved);
            return saved;
        }

        var activePorts = IPGlobalProperties.GetIPGlobalProperties()
            .GetActiveTcpListeners()
            .Select(endpoint => endpoint.Port)
            .ToHashSet();
        var candidate = preferredPort;
        while (candidate <= 65535 && (reservedPorts.Contains(candidate) || activePorts.Contains(candidate)))
        {
            candidate++;
        }
        if (candidate > 65535)
        {
            throw new InvalidOperationException("没有可用于新实例的本地端口。");
        }
        settings.Ports[instanceId] = candidate;
        reservedPorts.Add(candidate);
        return candidate;
    }
}
