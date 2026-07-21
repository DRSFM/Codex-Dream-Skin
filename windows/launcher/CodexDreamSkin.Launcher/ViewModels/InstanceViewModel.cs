using System.Windows.Media.Imaging;
using CodexDreamSkin.Launcher.Infrastructure;
using CodexDreamSkin.Launcher.Models;

namespace CodexDreamSkin.Launcher.ViewModels;

public sealed class InstanceViewModel : ObservableObject
{
    private string statusCode = "stopped";
    private bool desktopRunning;
    private bool skinRunning;
    private bool cdpVerified;
    private bool injectorRunning;
    private bool hasCustomImage;
    private string mode = "home-card";
    private string themeId = "pink-dream";
    private string themeName = "粉系定制";
    private string imagePath = "";
    private BitmapImage? previewImage;
    private string statePath = "";
    private string customRoot = "";
    private string lastVerifiedText = "尚未验证";
    private string lastError = "";
    private bool isBusy;
    private int port;

    public InstanceViewModel(ApiProfileMetadata? profile, string instanceId, int port)
    {
        Profile = profile;
        InstanceId = instanceId;
        this.port = port;
        Name = profile?.Name ?? "默认账号";
        BaseUrl = profile?.BaseUrl ?? "Codex 账号登录环境";
        ProfilePath = profile?.DesktopData;
    }

    public ApiProfileMetadata? Profile { get; }

    public string InstanceId { get; }

    public string Name { get; }

    public string BaseUrl { get; }

    public string? ProfilePath { get; }

    public int Port
    {
        get => port;
        private set => SetProperty(ref port, value);
    }

    public bool IsDefault => Profile is null;

    public bool CanManageProfile => Profile is not null;

    public string TypeLabel => IsDefault ? "本地账号" : "API 实例";

    public string ProtectionLabel => IsDefault ? "受保护" : "独立配置";

    public string AvatarText => string.IsNullOrWhiteSpace(Name) ? "C" : Name[..1].ToUpperInvariant();

    public string DetailPath => IsDefault ? "默认 Codex Desktop 数据" : ProfilePath ?? "";

    public string StatusCode
    {
        get => IsBusy ? "busy" : statusCode;
        private set
        {
            if (SetProperty(ref statusCode, value))
            {
                OnPropertyChanged(nameof(StatusCode));
            }
        }
    }

    public bool DesktopRunning
    {
        get => desktopRunning;
        private set => SetProperty(ref desktopRunning, value);
    }

    public bool SkinRunning
    {
        get => skinRunning;
        private set
        {
            if (SetProperty(ref skinRunning, value))
            {
                OnPropertyChanged(nameof(SkinStatusText));
            }
        }
    }

    public bool CdpVerified
    {
        get => cdpVerified;
        private set => SetProperty(ref cdpVerified, value);
    }

    public bool InjectorRunning
    {
        get => injectorRunning;
        private set => SetProperty(ref injectorRunning, value);
    }

    public bool HasCustomImage
    {
        get => hasCustomImage;
        private set => SetProperty(ref hasCustomImage, value);
    }

    public string Mode
    {
        get => mode;
        set => SetProperty(ref mode, value);
    }

    public string ThemeId
    {
        get => themeId;
        set => SetProperty(ref themeId, value);
    }

    public string ThemeName
    {
        get => themeName;
        private set => SetProperty(ref themeName, value);
    }

    public string ImagePath
    {
        get => imagePath;
        private set => SetProperty(ref imagePath, value);
    }

    public BitmapImage? PreviewImage
    {
        get => previewImage;
        private set => SetProperty(ref previewImage, value);
    }

    public string StatePath
    {
        get => statePath;
        private set => SetProperty(ref statePath, value);
    }

    public string CustomRoot
    {
        get => customRoot;
        private set => SetProperty(ref customRoot, value);
    }

    public string LastVerifiedText
    {
        get => lastVerifiedText;
        private set => SetProperty(ref lastVerifiedText, value);
    }

    public string LastError
    {
        get => lastError;
        set => SetProperty(ref lastError, value);
    }

    public bool IsBusy
    {
        get => isBusy;
        set
        {
            if (SetProperty(ref isBusy, value))
            {
                OnPropertyChanged(nameof(StatusCode));
            }
        }
    }

    public string SkinStatusText => SkinRunning ? "已生效" : "未生效";

    public string CdpStatusText => CdpVerified ? "已验证" : "未验证";

    public void ApplyStatus(DreamSkinStatus status, IReadOnlyDictionary<string, string> themeNames)
    {
        StatusCode = status.Status;
        DesktopRunning = status.DesktopRunning;
        SkinRunning = status.SkinRunning;
        CdpVerified = status.CdpVerified;
        OnPropertyChanged(nameof(CdpStatusText));
        InjectorRunning = status.InjectorRunning;
        HasCustomImage = status.HasCustomImage;
        Mode = status.Mode;
        ThemeId = status.ThemeId;
        ThemeName = themeNames.GetValueOrDefault(status.ThemeId, status.ThemeId);
        StatePath = status.StatePath;
        CustomRoot = status.CustomRoot;
        ImagePath = status.Image;
        PreviewImage = LoadImage(status.Image);
        LastVerifiedText = FormatTimestamp(status.LastVerifiedAt);
        LastError = "";
    }

    public void MarkStatusError(string message)
    {
        StatusCode = "attention";
        LastError = message;
    }

    public void UpdatePort(int value) => Port = value;

    private static BitmapImage? LoadImage(string path)
    {
        try
        {
            if (!File.Exists(path))
            {
                return null;
            }
            using var stream = File.OpenRead(path);
            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.DecodePixelWidth = 640;
            image.StreamSource = stream;
            image.EndInit();
            image.Freeze();
            return image;
        }
        catch
        {
            return null;
        }
    }

    private static string FormatTimestamp(string? value)
    {
        if (!DateTimeOffset.TryParse(value, out var timestamp))
        {
            return "尚未验证";
        }
        var local = timestamp.ToLocalTime();
        if (local.Date == DateTimeOffset.Now.Date)
        {
            return $"今天 {local:HH:mm:ss}";
        }
        return local.ToString("yyyy-MM-dd HH:mm");
    }
}
