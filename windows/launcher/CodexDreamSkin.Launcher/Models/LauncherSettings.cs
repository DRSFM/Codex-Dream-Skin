using System.Text.Json.Serialization;

namespace CodexDreamSkin.Launcher.Models;

public sealed class LauncherSettings
{
    [JsonPropertyName("schemaVersion")]
    public int SchemaVersion { get; set; } = 1;

    [JsonPropertyName("refreshSeconds")]
    public int RefreshSeconds { get; set; } = 20;

    [JsonPropertyName("ports")]
    public Dictionary<string, int> Ports { get; set; } = new(StringComparer.Ordinal);
}
