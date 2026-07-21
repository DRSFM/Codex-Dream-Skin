namespace CodexDreamSkin.Launcher.Services;

public static class RepositoryLocator
{
    public static string FindRoot()
    {
        var configured = Environment.GetEnvironmentVariable("CODEX_DREAM_SKIN_ROOT");
        if (IsRoot(configured))
        {
            return Path.GetFullPath(configured!);
        }

        foreach (var start in new[] { AppContext.BaseDirectory, Environment.CurrentDirectory })
        {
            var current = new DirectoryInfo(Path.GetFullPath(start));
            while (current is not null)
            {
                if (IsRoot(current.FullName))
                {
                    return current.FullName;
                }
                current = current.Parent;
            }
        }

        throw new DirectoryNotFoundException(
            "找不到 Codex Dream Skin 仓库。可通过 CODEX_DREAM_SKIN_ROOT 指定路径。");
    }

    private static bool IsRoot(string? path) =>
        !string.IsNullOrWhiteSpace(path) &&
        File.Exists(Path.Combine(path, "windows", "scripts", "start-dream-skin.ps1")) &&
        File.Exists(Path.Combine(path, "windows", "scripts", "common-windows.ps1"));
}
