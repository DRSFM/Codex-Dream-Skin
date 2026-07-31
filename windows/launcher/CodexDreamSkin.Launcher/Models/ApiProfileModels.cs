using System.Text.Json.Serialization;

namespace CodexDreamSkin.Launcher.Models;

public sealed class ApiProfileEnvelope
{
    [JsonPropertyName("schemaVersion")]
    public int SchemaVersion { get; set; }

    [JsonPropertyName("profiles")]
    public List<ApiProfileMetadata> Profiles { get; set; } = [];
}

public sealed class ApiProfileMetadata
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    [JsonPropertyName("instanceId")]
    public string InstanceId { get; set; } = "";

    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("baseUrl")]
    public string BaseUrl { get; set; } = "";

    [JsonPropertyName("profileHome")]
    public string ProfileHome { get; set; } = "";

    [JsonPropertyName("desktopData")]
    public string DesktopData { get; set; } = "";

    [JsonPropertyName("createdAt")]
    public string? CreatedAt { get; set; }

    [JsonPropertyName("lastUsedAt")]
    public string? LastUsedAt { get; set; }
}
