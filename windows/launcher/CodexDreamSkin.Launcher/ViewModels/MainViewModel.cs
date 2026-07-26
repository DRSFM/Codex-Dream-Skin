using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Text.Json;
using System.Windows.Data;
using CodexDreamSkin.Launcher.Infrastructure;
using CodexDreamSkin.Launcher.Models;
using CodexDreamSkin.Launcher.Services;

namespace CodexDreamSkin.Launcher.ViewModels;

public sealed class MainViewModel : ObservableObject
{
    private readonly ApiCodexService apiCodex;
    private readonly DreamSkinService dreamSkin;
    private readonly LauncherSettingsStore settingsStore;
    private readonly ThemeCatalog themeCatalog;
    private readonly DesktopWindowService desktopWindows;
    private readonly SemaphoreSlim refreshGate = new(1, 1);
    private LauncherSettings settings = new();
    private IReadOnlyDictionary<string, string> themeNames = new Dictionary<string, string>();
    private InstanceViewModel? selectedInstance;
    private string searchText = "";
    private string statusMessage = "准备就绪";
    private string lastRefreshText = "尚未刷新";
    private bool isRefreshing;

    public MainViewModel(DesktopWindowService? desktopWindows = null)
    {
        var repositoryRoot = RepositoryLocator.FindRoot();
        var runner = new ProcessRunner();
        apiCodex = new ApiCodexService(runner);
        dreamSkin = new DreamSkinService(runner, apiCodex, repositoryRoot);
        settingsStore = new LauncherSettingsStore();
        themeCatalog = new ThemeCatalog(repositoryRoot);
        this.desktopWindows = desktopWindows ?? new DesktopWindowService();
        FilteredInstances = CollectionViewSource.GetDefaultView(Instances);
        FilteredInstances.Filter = FilterInstance;
    }

    public ObservableCollection<InstanceViewModel> Instances { get; } = [];

    public ObservableCollection<ThemeOption> Themes { get; } = [];

    public ICollectionView FilteredInstances { get; }

    public InstanceViewModel? SelectedInstance
    {
        get => selectedInstance;
        set => SetProperty(ref selectedInstance, value);
    }

    public string SearchText
    {
        get => searchText;
        set
        {
            if (SetProperty(ref searchText, value))
            {
                FilteredInstances.Refresh();
            }
        }
    }

    public string StatusMessage
    {
        get => statusMessage;
        private set => SetProperty(ref statusMessage, value);
    }

    public string LastRefreshText
    {
        get => lastRefreshText;
        private set => SetProperty(ref lastRefreshText, value);
    }

    public bool IsRefreshing
    {
        get => isRefreshing;
        private set => SetProperty(ref isRefreshing, value);
    }

    public int RefreshSeconds => settings.RefreshSeconds;

    public int RunningCount => Instances.Count(instance => instance.SkinRunning);

    public int AttentionCount => Instances.Count(instance => instance.StatusCode == "attention");

    public int ApiInstanceCount => Instances.Count(instance => !instance.IsDefault);

    public string ApiCodexPath => apiCodex.LauncherPath;

    public string SettingsPath => settingsStore.SettingsPath;

    public event EventHandler? InstanceStatesChanged;

    public async Task InitializeAsync(CancellationToken cancellationToken = default)
    {
        settings = await settingsStore.LoadAsync(cancellationToken);
        var themes = await themeCatalog.LoadAsync(cancellationToken);
        Themes.Clear();
        foreach (var theme in themes)
        {
            Themes.Add(theme);
        }
        themeNames = themes.ToDictionary(theme => theme.Id, theme => theme.Name, StringComparer.Ordinal);
        await ReloadProfilesAsync(cancellationToken);
    }

    public async Task ReloadProfilesAsync(CancellationToken cancellationToken = default)
    {
        var previousSelection = SelectedInstance?.InstanceId;
        IsRefreshing = true;
        StatusMessage = "正在扫描本地实例...";
        try
        {
            var profiles = await apiCodex.ListProfilesAsync(cancellationToken);
            var orderedProfiles = profiles
                .OrderByDescending(profile => ParseTimestamp(profile.LastUsedAt))
                .ThenBy(profile => profile.Name, StringComparer.CurrentCulture)
                .ToArray();
            var reservedPorts = new HashSet<int>();
            var rebuilt = new List<InstanceViewModel>();

            var defaultPort = ReadSavedStatePort("default") ?? 9335;
            settings.Ports["default"] = defaultPort;
            reservedPorts.Add(defaultPort);
            rebuilt.Add(new InstanceViewModel(null, "default", defaultPort));

            var nextPreferredPort = 9336;
            foreach (var profile in orderedProfiles)
            {
                var statePort = ReadSavedStatePort(profile.InstanceId);
                int port;
                if (statePort is not null && !reservedPorts.Contains(statePort.Value))
                {
                    port = statePort.Value;
                    settings.Ports[profile.InstanceId] = port;
                    reservedPorts.Add(port);
                }
                else
                {
                    port = LauncherSettingsStore.GetOrAssignPort(
                        settings, profile.InstanceId, nextPreferredPort, reservedPorts);
                }
                nextPreferredPort = Math.Max(nextPreferredPort, port + 1);
                rebuilt.Add(new InstanceViewModel(profile, profile.InstanceId, port));
            }

            Instances.Clear();
            foreach (var instance in rebuilt)
            {
                Instances.Add(instance);
            }
            await settingsStore.SaveAsync(settings, cancellationToken);
            SelectedInstance = Instances.FirstOrDefault(instance => instance.InstanceId == previousSelection)
                ?? Instances.FirstOrDefault();
            FilteredInstances.Refresh();
            await RefreshStatusesAsync(cancellationToken);
            StatusMessage = $"已发现 {Instances.Count} 个实例";
        }
        finally
        {
            IsRefreshing = false;
            RaiseSummaryProperties();
        }
    }

    public async Task RefreshStatusesAsync(CancellationToken cancellationToken = default)
    {
        if (!await refreshGate.WaitAsync(0, cancellationToken))
        {
            return;
        }
        IsRefreshing = true;
        StatusMessage = "正在刷新运行状态...";
        try
        {
            var results = await dreamSkin.GetStatusesAsync(
                Instances.Select(instance => (instance.InstanceId, instance.Port, instance.ProfilePath)),
                cancellationToken);
            var byId = results.ToDictionary(item => item.InstanceId, StringComparer.Ordinal);
            foreach (var instance in Instances)
            {
                if (!byId.TryGetValue(instance.InstanceId, out var item))
                {
                    instance.MarkStatusError("状态结果中缺少该实例。");
                }
                else if (!string.IsNullOrWhiteSpace(item.Error) || item.Status is null)
                {
                    instance.MarkStatusError(item.Error ?? "实例状态不可用。");
                }
                else
                {
                    instance.ApplyStatus(item.Status, themeNames);
                    desktopWindows.LabelInstanceWindows(instance);
                }
            }
            LastRefreshText = DateTime.Now.ToString("HH:mm:ss");
            StatusMessage = "状态已刷新";
        }
        finally
        {
            IsRefreshing = false;
            refreshGate.Release();
            RaiseSummaryProperties();
            InstanceStatesChanged?.Invoke(this, EventArgs.Empty);
        }
    }

    public Task StartAsync(InstanceViewModel instance, CancellationToken cancellationToken = default) =>
        RunOperationAsync(
            instance,
            () => dreamSkin.StartAsync(instance.Profile, instance.InstanceId, instance.Port, cancellationToken),
            "实例已启动并应用皮肤",
            cancellationToken);

    public Task StopAsync(InstanceViewModel instance, CancellationToken cancellationToken = default) =>
        RunOperationAsync(
            instance,
            () => dreamSkin.StopAsync(
                instance.InstanceId,
                instance.Port,
                instance.ProfilePath,
                instance.HasManagedState,
                cancellationToken),
            "实例已停止",
            cancellationToken);

    public Task RestoreAsync(InstanceViewModel instance, CancellationToken cancellationToken = default) =>
        RunOperationAsync(
            instance,
            () => dreamSkin.RestoreWithoutSkinAsync(instance.InstanceId, instance.Port, cancellationToken),
            "实例已恢复为无皮肤状态",
            cancellationToken);

    public Task VerifyAsync(InstanceViewModel instance, CancellationToken cancellationToken = default) =>
        RunOperationAsync(
            instance,
            () => dreamSkin.VerifyAsync(instance.InstanceId, instance.Port, cancellationToken),
            "实例验证通过",
            cancellationToken);

    public Task SetAppearanceAsync(
        InstanceViewModel instance,
        string? imagePath,
        bool clearImage,
        CancellationToken cancellationToken = default) =>
        RunOperationAsync(
            instance,
            () => dreamSkin.SetAppearanceAsync(
                instance.InstanceId,
                imagePath,
                clearImage,
                instance.Mode,
                instance.ThemeId,
                cancellationToken),
            "外观已更新",
            cancellationToken);

    public async Task AddProfileAsync(CancellationToken cancellationToken = default)
    {
        await apiCodex.OpenAddProfileAsync(cancellationToken);
        await ReloadProfilesAsync(cancellationToken);
    }

    public async Task EditProfileAsync(InstanceViewModel instance, CancellationToken cancellationToken = default)
    {
        if (instance.Profile is null)
        {
            return;
        }
        await apiCodex.OpenEditProfileAsync(instance.Profile, cancellationToken);
        await ReloadProfilesAsync(cancellationToken);
    }

    public async Task RemoveProfileAsync(InstanceViewModel instance, CancellationToken cancellationToken = default)
    {
        if (instance.Profile is null)
        {
            return;
        }
        await apiCodex.OpenRemoveProfileAsync(instance.Profile, cancellationToken);
        await ReloadProfilesAsync(cancellationToken);
    }

    public void OpenLogs(InstanceViewModel instance) => dreamSkin.OpenLogs(instance.StatePath);

    public bool FocusDesktop(InstanceViewModel instance) => desktopWindows.FocusInstanceWindow(instance);

    public async Task ChangePortAsync(
        InstanceViewModel instance,
        int port,
        CancellationToken cancellationToken = default)
    {
        if (port is < 1024 or > 65535)
        {
            throw new InvalidOperationException("端口必须在 1024 到 65535 之间。");
        }
        if (instance.DesktopRunning || instance.SkinRunning)
        {
            throw new InvalidOperationException("请先停止该实例，再修改监听端口。");
        }
        if (Instances.Any(other => other != instance && other.Port == port))
        {
            throw new InvalidOperationException($"端口 {port} 已分配给其他实例。");
        }
        settings.Ports[instance.InstanceId] = port;
        instance.UpdatePort(port);
        await settingsStore.SaveAsync(settings, cancellationToken);
        StatusMessage = $"{instance.Name} 的端口已更新为 {port}";
    }

    public void OpenSettingsFolder()
    {
        var directory = Path.GetDirectoryName(settingsStore.SettingsPath)!;
        Directory.CreateDirectory(directory);
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("explorer.exe", directory)
        {
            UseShellExecute = true,
        });
    }

    private async Task RunOperationAsync(
        InstanceViewModel instance,
        Func<Task> operation,
        string successMessage,
        CancellationToken cancellationToken)
    {
        if (instance.IsBusy)
        {
            return;
        }
        instance.IsBusy = true;
        SelectedInstance = instance;
        StatusMessage = $"正在处理 {instance.Name}...";
        try
        {
            await operation();
            await RefreshStatusAsync(instance, cancellationToken);
            StatusMessage = successMessage;
        }
        catch (Exception exception)
        {
            instance.LastError = exception.Message;
            StatusMessage = exception.Message;
            throw;
        }
        finally
        {
            instance.IsBusy = false;
            RaiseSummaryProperties();
        }
    }

    private async Task RefreshStatusAsync(
        InstanceViewModel instance,
        CancellationToken cancellationToken)
    {
        try
        {
            var status = await dreamSkin.GetStatusAsync(
                instance.InstanceId,
                instance.Port,
                instance.ProfilePath,
                cancellationToken);
            instance.ApplyStatus(status, themeNames);
            desktopWindows.LabelInstanceWindows(instance);
            InstanceStatesChanged?.Invoke(this, EventArgs.Empty);
        }
        catch (Exception exception)
        {
            instance.MarkStatusError(exception.Message);
            WriteDiagnostic(instance.InstanceId, exception);
        }
    }

    private bool FilterInstance(object item)
    {
        if (item is not InstanceViewModel instance || string.IsNullOrWhiteSpace(SearchText))
        {
            return true;
        }
        var query = SearchText.Trim();
        return instance.InstanceId.Contains(query, StringComparison.OrdinalIgnoreCase) ||
               instance.Name.Contains(query, StringComparison.CurrentCultureIgnoreCase) ||
               instance.BaseUrl.Contains(query, StringComparison.OrdinalIgnoreCase) ||
               instance.Port.ToString().Contains(query, StringComparison.Ordinal) ||
               instance.StatusCode.Contains(query, StringComparison.OrdinalIgnoreCase);
    }

    private static DateTimeOffset ParseTimestamp(string? value) =>
        DateTimeOffset.TryParse(value, out var timestamp) ? timestamp : DateTimeOffset.MinValue;

    private static int? ReadSavedStatePort(string instanceId)
    {
        try
        {
            var localData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var statePath = instanceId == "default"
                ? Path.Combine(localData, "CodexDreamSkin", "state.json")
                : Path.Combine(localData, "CodexDreamSkin", "instances", instanceId, "state.json");
            if (!File.Exists(statePath))
            {
                return null;
            }
            using var document = JsonDocument.Parse(File.ReadAllBytes(statePath));
            if (document.RootElement.TryGetProperty("port", out var port) &&
                port.TryGetInt32(out var value) && value is >= 1024 and <= 65535)
            {
                return value;
            }
        }
        catch
        {
            // The status script reports malformed state without letting the launcher overwrite it.
        }
        return null;
    }

    private void RaiseSummaryProperties()
    {
        OnPropertyChanged(nameof(RunningCount));
        OnPropertyChanged(nameof(AttentionCount));
        OnPropertyChanged(nameof(ApiInstanceCount));
    }

    private void WriteDiagnostic(string instanceId, Exception exception)
    {
        try
        {
            var directory = Path.GetDirectoryName(settingsStore.SettingsPath)!;
            Directory.CreateDirectory(directory);
            var line = $"{DateTimeOffset.Now:o} [{instanceId}] {exception.GetType().Name}: {exception.Message}{Environment.NewLine}";
            File.AppendAllText(Path.Combine(directory, "launcher-error.log"), line, new System.Text.UTF8Encoding(false));
        }
        catch
        {
            // Diagnostics must never replace the original status error.
        }
    }
}
