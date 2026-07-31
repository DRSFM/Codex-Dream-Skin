using System.Text.Json.Serialization;

namespace CodexDreamSkin.Launcher.Models;

public sealed class DreamSkinStatus
{
    [JsonPropertyName("schemaVersion")]
    public int SchemaVersion { get; set; }

    [JsonPropertyName("instanceId")]
    public string InstanceId { get; set; } = "";

    [JsonPropertyName("status")]
    public string Status { get; set; } = "stopped";

    [JsonPropertyName("isProtected")]
    public bool IsProtected { get; set; }

    [JsonPropertyName("desktopRunning")]
    public bool DesktopRunning { get; set; }

    [JsonPropertyName("desktopProcessIds")]
    public List<int> DesktopProcessIds { get; set; } = [];

    [JsonPropertyName("skinRunning")]
    public bool SkinRunning { get; set; }

    [JsonPropertyName("cdpVerified")]
    public bool CdpVerified { get; set; }

    [JsonPropertyName("injectorRunning")]
    public bool InjectorRunning { get; set; }

    [JsonPropertyName("injectorPid")]
    public int? InjectorPid { get; set; }

    [JsonPropertyName("port")]
    public int Port { get; set; }

    [JsonPropertyName("profilePath")]
    public string? ProfilePath { get; set; }

    [JsonPropertyName("statePath")]
    public string StatePath { get; set; } = "";

    [JsonPropertyName("customRoot")]
    public string CustomRoot { get; set; } = "";

    [JsonPropertyName("image")]
    public string Image { get; set; } = "";

    [JsonPropertyName("hasCustomImage")]
    public bool HasCustomImage { get; set; }

    [JsonPropertyName("mode")]
    public string Mode { get; set; } = "home-card";

    [JsonPropertyName("themeId")]
    public string ThemeId { get; set; } = "pink-dream";

    [JsonPropertyName("stateCreatedAt")]
    public string? StateCreatedAt { get; set; }

    [JsonPropertyName("lastVerifiedAt")]
    public string? LastVerifiedAt { get; set; }
}

public sealed class AppearanceResult
{
    [JsonPropertyName("schemaVersion")]
    public int SchemaVersion { get; set; }

    [JsonPropertyName("instanceId")]
    public string InstanceId { get; set; } = "";

    [JsonPropertyName("image")]
    public string Image { get; set; } = "";

    [JsonPropertyName("hasCustomImage")]
    public bool HasCustomImage { get; set; }

    [JsonPropertyName("mode")]
    public string Mode { get; set; } = "home-card";

    [JsonPropertyName("themeId")]
    public string ThemeId { get; set; } = "pink-dream";
}

public sealed class LauncherStatusEnvelope
{
    [JsonPropertyName("schemaVersion")]
    public int SchemaVersion { get; set; }

    [JsonPropertyName("instances")]
    public List<LauncherStatusItem> Instances { get; set; } = [];
}

public sealed class LauncherStatusItem
{
    [JsonPropertyName("instanceId")]
    public string InstanceId { get; set; } = "";

    [JsonPropertyName("error")]
    public string? Error { get; set; }

    [JsonPropertyName("status")]
    public DreamSkinStatus? Status { get; set; }
}

public sealed class ThemeOption
{
    [JsonPropertyName("schemaVersion")]
    public int SchemaVersion { get; set; }

    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("description")]
    public string Description { get; set; } = "";

    [JsonPropertyName("scheme")]
    public string Scheme { get; set; } = "light";
}
