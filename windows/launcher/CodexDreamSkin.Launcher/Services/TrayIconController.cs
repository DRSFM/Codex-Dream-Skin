using CodexDreamSkin.Launcher.ViewModels;
using Forms = System.Windows.Forms;

namespace CodexDreamSkin.Launcher.Services;

public sealed class TrayIconController : IDisposable
{
    private readonly MainWindow window;
    private readonly MainViewModel viewModel;
    private readonly Forms.NotifyIcon notifyIcon;
    private bool disposed;
    private bool backgroundNoticeShown;

    public TrayIconController(MainWindow window, MainViewModel viewModel)
    {
        this.window = window;
        this.viewModel = viewModel;
        notifyIcon = new Forms.NotifyIcon
        {
            Icon = LoadIcon(),
            Text = "ApiCodex Desktop",
            Visible = true,
        };
        notifyIcon.DoubleClick += (_, _) => window.ShowManager();
        viewModel.InstanceStatesChanged += ViewModel_InstanceStatesChanged;
        RebuildMenu();
    }

    public void ShowBackgroundNotice()
    {
        if (backgroundNoticeShown || disposed)
        {
            return;
        }
        backgroundNoticeShown = true;
        notifyIcon.ShowBalloonTip(
            2500,
            "ApiCodex Desktop",
            "管理面板已隐藏，实例仍可从系统托盘管理。",
            Forms.ToolTipIcon.Info);
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }
        disposed = true;
        viewModel.InstanceStatesChanged -= ViewModel_InstanceStatesChanged;
        notifyIcon.Visible = false;
        notifyIcon.ContextMenuStrip?.Dispose();
        notifyIcon.Dispose();
    }

    private void ViewModel_InstanceStatesChanged(object? sender, EventArgs e)
    {
        if (!window.Dispatcher.CheckAccess())
        {
            _ = window.Dispatcher.BeginInvoke(RebuildMenu);
            return;
        }
        RebuildMenu();
    }

    private void RebuildMenu()
    {
        if (disposed)
        {
            return;
        }

        var menu = new Forms.ContextMenuStrip();
        var openManager = new Forms.ToolStripMenuItem("打开管理面板");
        openManager.Click += (_, _) => window.ShowManager();
        menu.Items.Add(openManager);

        var refresh = new Forms.ToolStripMenuItem("刷新实例状态");
        refresh.Click += async (_, _) => await RunAsync(window.RefreshFromTrayAsync);
        menu.Items.Add(refresh);
        menu.Items.Add(new Forms.ToolStripSeparator());

        foreach (var instance in viewModel.Instances)
        {
            menu.Items.Add(BuildInstanceMenu(instance));
        }

        menu.Items.Add(new Forms.ToolStripSeparator());
        var exit = new Forms.ToolStripMenuItem("退出 ApiCodex 管理器");
        exit.Click += (_, _) => ((App)System.Windows.Application.Current).RequestExit();
        menu.Items.Add(exit);

        var previous = notifyIcon.ContextMenuStrip;
        notifyIcon.ContextMenuStrip = menu;
        previous?.Dispose();
        notifyIcon.Text = BuildToolTip(viewModel.Instances);
    }

    private Forms.ToolStripMenuItem BuildInstanceMenu(InstanceViewModel instance)
    {
        var state = instance.DesktopRunning ? "运行中" : "已停止";
        var item = new Forms.ToolStripMenuItem($"{instance.DesktopTitle}  [{state}]");
        if (instance.DesktopRunning)
        {
            var focus = new Forms.ToolStripMenuItem("聚焦窗口");
            focus.Click += async (_, _) => await RunAsync(() => window.FocusFromTrayAsync(instance));
            item.DropDownItems.Add(focus);

            var stop = new Forms.ToolStripMenuItem("停止");
            stop.Click += async (_, _) => await RunAsync(() => window.StopFromTrayAsync(instance));
            item.DropDownItems.Add(stop);

            var restart = new Forms.ToolStripMenuItem("重启并应用皮肤");
            restart.Click += async (_, _) => await RunAsync(() => window.RestartFromTrayAsync(instance));
            item.DropDownItems.Add(restart);
        }
        else
        {
            var start = new Forms.ToolStripMenuItem("启动并应用皮肤");
            start.Click += async (_, _) => await RunAsync(() => window.StartFromTrayAsync(instance));
            item.DropDownItems.Add(start);
        }
        return item;
    }

    private async Task RunAsync(Func<Task> action)
    {
        try
        {
            await action();
        }
        catch (Exception exception)
        {
            notifyIcon.ShowBalloonTip(
                4000,
                "ApiCodex 操作失败",
                exception.Message,
                Forms.ToolTipIcon.Error);
        }
    }

    private static string BuildToolTip(IEnumerable<InstanceViewModel> instances)
    {
        var all = instances.ToArray();
        var running = all.Count(instance => instance.DesktopRunning);
        var value = $"ApiCodex Desktop - {running}/{all.Length} 个实例运行";
        return value.Length <= 63 ? value : value[..63];
    }

    private static System.Drawing.Icon LoadIcon()
    {
        try
        {
            if (Environment.ProcessPath is { } path &&
                System.Drawing.Icon.ExtractAssociatedIcon(path) is { } icon)
            {
                return icon;
            }
        }
        catch
        {
        }
        return (System.Drawing.Icon)System.Drawing.SystemIcons.Application.Clone();
    }
}
