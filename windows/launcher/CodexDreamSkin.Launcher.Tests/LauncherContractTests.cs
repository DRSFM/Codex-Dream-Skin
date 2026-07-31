using System.Text.Json;
using CodexDreamSkin.Launcher.Models;
using CodexDreamSkin.Launcher.Services;
using CodexDreamSkin.Launcher.ViewModels;
using Xunit;

namespace CodexDreamSkin.Launcher.Tests;

public sealed class LauncherContractTests
{
    [Fact]
    public void ProfileContractIgnoresCredentialFields()
    {
        const string json = """
            {
              "schemaVersion": 1,
              "profiles": [{
                "id": "relay",
                "instanceId": "relay",
                "name": "通用实例",
                "baseUrl": "https://example.test/v1",
                "profileHome": "C:\\profiles\\relay",
                "desktopData": "C:\\desktop\\relay",
                "credentialId": "must-not-enter-the-model",
                "apiKey": "must-not-enter-the-model"
              }]
            }
            """;

        var payload = JsonSerializer.Deserialize<ApiProfileEnvelope>(json);

        Assert.NotNull(payload);
        Assert.Equal(1, payload.SchemaVersion);
        var profile = Assert.Single(payload.Profiles);
        Assert.Equal("relay", profile.Id);
        Assert.DoesNotContain(
            typeof(ApiProfileMetadata).GetProperties(),
            property => property.Name.Contains("Credential", StringComparison.OrdinalIgnoreCase) ||
                        property.Name.Contains("Key", StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public void PortAssignmentHonorsSavedAndReservedPorts()
    {
        var settings = new LauncherSettings
        {
            Ports = new Dictionary<string, int>(StringComparer.Ordinal)
            {
                ["saved"] = 62001,
                ["conflict"] = 62001,
            },
        };
        var reserved = new HashSet<int>();

        var saved = LauncherSettingsStore.GetOrAssignPort(settings, "saved", 62000, reserved);
        var conflict = LauncherSettingsStore.GetOrAssignPort(settings, "conflict", 62000, reserved);

        Assert.Equal(62001, saved);
        Assert.NotEqual(saved, conflict);
        Assert.Contains(conflict, reserved);
    }

    [Fact]
    public void InstanceViewModelAppliesIndependentStatusMetadata()
    {
        var profile = new ApiProfileMetadata
        {
            Id = "relay",
            InstanceId = "relay",
            Name = "通用实例",
            BaseUrl = "https://example.test/v1",
            DesktopData = @"C:\desktop\relay",
        };
        var instance = new InstanceViewModel(profile, profile.InstanceId, 9340);
        var status = new DreamSkinStatus
        {
            SchemaVersion = 1,
            InstanceId = "relay",
            Status = "running",
            DesktopRunning = true,
            SkinRunning = true,
            CdpVerified = true,
            InjectorRunning = true,
            Port = 9340,
            Image = @"C:\missing\preview.png",
            Mode = "full-window",
            ThemeId = "pink-dream",
            DesktopProcessIds = [120, 120, -1],
            StateCreatedAt = "2026-07-26T03:00:00Z",
        };

        instance.ApplyStatus(status, new Dictionary<string, string> { ["pink-dream"] = "粉系定制" });

        Assert.Equal("running", instance.StatusCode);
        Assert.True(instance.SkinRunning);
        Assert.Equal("已验证", instance.CdpStatusText);
        Assert.Equal("整窗背景", instance.Mode == "full-window" ? "整窗背景" : "主页卡片");
        Assert.Equal("粉系定制", instance.ThemeName);
        Assert.Null(instance.PreviewImage);
        Assert.Equal([120], instance.DesktopProcessIds);
        Assert.True(instance.HasManagedState);
        Assert.Equal("ChatGPT (通用实例)", instance.DesktopTitle);
    }

    [Fact]
    public void SearchMatchesInstanceId()
    {
        var viewModel = new MainViewModel();
        viewModel.Instances.Add(new InstanceViewModel(null, "default", 9335));
        viewModel.SearchText = "default";

        var match = Assert.Single(viewModel.FilteredInstances.Cast<InstanceViewModel>());

        Assert.Equal("default", match.InstanceId);
    }

    [Fact]
    public void DesktopWindowServiceLabelsOnlyVerifiedMainWindows()
    {
        var native = new FakeDesktopWindowNative(
        [
            new(1, 120, "ChatGPT", true, false, false),
            new(2, 120, "ChatGPT", true, true, false),
            new(3, 120, "ChatGPT", true, false, true),
            new(4, 120, "Other window", true, false, false),
            new(5, 999, "ChatGPT", true, false, false),
        ]);
        var service = new DesktopWindowService(native);
        var profile = new ApiProfileMetadata
        {
            Id = "relay",
            InstanceId = "relay",
            Name = "通用实例",
            DesktopData = @"C:\desktop\relay",
        };
        var instance = new InstanceViewModel(profile, "relay", 9340);
        instance.ApplyStatus(new DreamSkinStatus
        {
            InstanceId = "relay",
            DesktopRunning = true,
            DesktopProcessIds = [120],
        }, new Dictionary<string, string>());

        var labeled = service.LabelInstanceWindows(instance);

        Assert.Equal(1, labeled);
        Assert.Equal((nint)1, Assert.Single(native.Titles).Handle);
        Assert.Equal("ChatGPT (通用实例)", Assert.Single(native.Titles).Title);
    }

    [Fact]
    public void DesktopWindowServiceFocusesOnlyVerifiedPid()
    {
        var native = new FakeDesktopWindowNative(
        [
            new(1, 999, "ChatGPT", true, false, false),
            new(2, 120, "ChatGPT (relay)", true, false, false),
        ]);
        var service = new DesktopWindowService(native);
        var instance = new InstanceViewModel(null, "default", 9335);
        instance.ApplyStatus(new DreamSkinStatus
        {
            InstanceId = "default",
            DesktopRunning = true,
            DesktopProcessIds = [120],
        }, new Dictionary<string, string>());

        Assert.True(service.FocusInstanceWindow(instance));
        Assert.Equal((nint)2, Assert.Single(native.Activated));
        Assert.Equal("ChatGPT", instance.DesktopTitle);
    }

    private sealed class FakeDesktopWindowNative(
        IReadOnlyList<DesktopWindowSnapshot> windows) : IDesktopWindowNative
    {
        public List<(nint Handle, string Title)> Titles { get; } = [];

        public List<nint> Activated { get; } = [];

        public IReadOnlyList<DesktopWindowSnapshot> EnumerateTopLevelWindows() => windows;

        public bool SetTitle(nint handle, string title)
        {
            Titles.Add((handle, title));
            return true;
        }

        public bool ShowAndActivate(nint handle)
        {
            Activated.Add(handle);
            return true;
        }
    }
}
