using System.Runtime.InteropServices;
using System.Text;
using CodexDreamSkin.Launcher.ViewModels;

namespace CodexDreamSkin.Launcher.Services;

public readonly record struct DesktopWindowSnapshot(
    nint Handle,
    int ProcessId,
    string Title,
    bool IsVisible,
    bool HasOwner,
    bool IsToolWindow);

public interface IDesktopWindowNative
{
    IReadOnlyList<DesktopWindowSnapshot> EnumerateTopLevelWindows();

    bool SetTitle(nint handle, string title);

    bool ShowAndActivate(nint handle);
}

public sealed class DesktopWindowService
{
    private readonly IDesktopWindowNative native;

    public DesktopWindowService()
        : this(new Win32DesktopWindowNative())
    {
    }

    public DesktopWindowService(IDesktopWindowNative native)
    {
        this.native = native;
    }

    public int LabelInstanceWindows(InstanceViewModel instance)
    {
        var title = NormalizeTitle(instance.DesktopTitle);
        var labeled = 0;
        foreach (var window in FindMainWindows(instance.DesktopProcessIds))
        {
            if (window.Title == title || native.SetTitle(window.Handle, title))
            {
                labeled++;
            }
        }
        return labeled;
    }

    public bool FocusInstanceWindow(InstanceViewModel instance)
    {
        var window = FindMainWindows(instance.DesktopProcessIds).FirstOrDefault();
        return window.Handle != nint.Zero && native.ShowAndActivate(window.Handle);
    }

    private IEnumerable<DesktopWindowSnapshot> FindMainWindows(IEnumerable<int> processIds)
    {
        var allowed = processIds.Where(processId => processId > 0).ToHashSet();
        if (allowed.Count == 0)
        {
            return [];
        }
        return native.EnumerateTopLevelWindows().Where(window =>
            allowed.Contains(window.ProcessId) &&
            window.IsVisible &&
            !window.HasOwner &&
            !window.IsToolWindow &&
            window.Title.StartsWith("ChatGPT", StringComparison.OrdinalIgnoreCase));
    }

    private static string NormalizeTitle(string value)
    {
        var sanitized = new string(value.Where(character => !char.IsControl(character)).ToArray()).Trim();
        return sanitized.Length <= 120 ? sanitized : sanitized[..120];
    }
}

internal sealed class Win32DesktopWindowNative : IDesktopWindowNative
{
    private const uint GwOwner = 4;
    private const int GwlExStyle = -20;
    private const long WsExToolWindow = 0x00000080L;
    private const int SwRestore = 9;

    public IReadOnlyList<DesktopWindowSnapshot> EnumerateTopLevelWindows()
    {
        var windows = new List<DesktopWindowSnapshot>();
        EnumWindows((handle, parameter) =>
        {
            try
            {
                _ = GetWindowThreadProcessId(handle, out var processId);
                var length = GetWindowTextLength(handle);
                var title = new StringBuilder(Math.Max(length + 1, 1));
                _ = GetWindowText(handle, title, title.Capacity);
                var exStyle = GetWindowLongPtr(handle, GwlExStyle).ToInt64();
                windows.Add(new DesktopWindowSnapshot(
                    handle,
                    unchecked((int)processId),
                    title.ToString(),
                    IsWindowVisible(handle),
                    GetWindow(handle, GwOwner) != nint.Zero,
                    (exStyle & WsExToolWindow) != 0));
            }
            catch
            {
                // A window can disappear while EnumWindows is walking the desktop.
            }
            return true;
        }, nint.Zero);
        return windows;
    }

    public bool SetTitle(nint handle, string title) => SetWindowText(handle, title);

    public bool ShowAndActivate(nint handle)
    {
        _ = ShowWindowAsync(handle, SwRestore);
        return SetForegroundWindow(handle);
    }

    private static nint GetWindowLongPtr(nint handle, int index) =>
        nint.Size == 8 ? GetWindowLongPtr64(handle, index) : new nint(GetWindowLong32(handle, index));

    private delegate bool EnumWindowsProc(nint handle, nint parameter);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool EnumWindows(EnumWindowsProc callback, nint parameter);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(nint handle);

    [DllImport("user32.dll")]
    private static extern nint GetWindow(nint handle, uint command);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(nint handle, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(nint handle, StringBuilder text, int maximumCount);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextLength(nint handle);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowText(nint handle, string text);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShowWindowAsync(nint handle, int command);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(nint handle);

    [DllImport("user32.dll", EntryPoint = "GetWindowLong")]
    private static extern int GetWindowLong32(nint handle, int index);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtr")]
    private static extern nint GetWindowLongPtr64(nint handle, int index);
}
