using System.Text.Json;
using System.Text.RegularExpressions;
using CodexDreamSkin.Launcher.Models;

namespace CodexDreamSkin.Launcher.Services;

public sealed partial class ThemeCatalog
{
    private readonly string themesRoot;

    public ThemeCatalog(string repositoryRoot)
    {
        themesRoot = Path.Combine(repositoryRoot, "windows", "themes");
    }

    public async Task<IReadOnlyList<ThemeOption>> LoadAsync(CancellationToken cancellationToken = default)
    {
        var themes = new List<ThemeOption>();
        foreach (var path in Directory.EnumerateFiles(themesRoot, "theme.json", SearchOption.AllDirectories))
        {
            await using var stream = File.OpenRead(path);
            var theme = await JsonSerializer.DeserializeAsync<ThemeOption>(
                stream,
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true },
                cancellationToken);
            if (theme is null || theme.SchemaVersion != 1 || !ThemeIdPattern().IsMatch(theme.Id))
            {
                throw new InvalidDataException($"主题文件格式不受支持：{path}");
            }
            themes.Add(theme);
        }
        return themes.OrderBy(theme => theme.Name, StringComparer.CurrentCulture).ToArray();
    }

    [GeneratedRegex(@"^[a-z0-9][a-z0-9-]{0,79}$", RegexOptions.CultureInvariant)]
    private static partial Regex ThemeIdPattern();
}
