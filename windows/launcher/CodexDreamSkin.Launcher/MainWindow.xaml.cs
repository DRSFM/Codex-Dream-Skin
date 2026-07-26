using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using CodexDreamSkin.Launcher.Services;
using CodexDreamSkin.Launcher.ViewModels;
using Microsoft.Win32;

namespace CodexDreamSkin.Launcher;

public partial class MainWindow : Window
{
    private readonly MainViewModel viewModel = new();
    private readonly CancellationTokenSource lifetime = new();
    private readonly TrayIconController tray;
    private DispatcherTimer? refreshTimer;

    public MainWindow()
    {
        InitializeComponent();
        DataContext = viewModel;
        tray = new TrayIconController(this, viewModel);
        Loaded += MainWindow_Loaded;
        Closing += MainWindow_Closing;
        Closed += MainWindow_Closed;
    }

    private async void MainWindow_Loaded(object sender, RoutedEventArgs e)
    {
        await RunUiActionAsync(() => viewModel.InitializeAsync(lifetime.Token));
        refreshTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(Math.Max(10, viewModel.RefreshSeconds)),
        };
        refreshTimer.Tick += async (_, _) => await RunUiActionAsync(
            () => viewModel.RefreshStatusesAsync(lifetime.Token), showError: false);
        refreshTimer.Start();
    }

    private async void ScanInstances_Click(object sender, RoutedEventArgs e) =>
        await RunUiActionAsync(() => viewModel.ReloadProfilesAsync(lifetime.Token));

    private async void RefreshStatus_Click(object sender, RoutedEventArgs e) =>
        await RunUiActionAsync(() => viewModel.RefreshStatusesAsync(lifetime.Token));

    public void ShowManager()
    {
        if (!Dispatcher.CheckAccess())
        {
            _ = Dispatcher.BeginInvoke(ShowManager);
            return;
        }
        Show();
        ShowInTaskbar = true;
        if (WindowState == WindowState.Minimized)
        {
            WindowState = WindowState.Normal;
        }
        Activate();
    }

    internal Task RefreshFromTrayAsync() =>
        RunUiActionAsync(() => viewModel.RefreshStatusesAsync(lifetime.Token));

    internal Task StartFromTrayAsync(InstanceViewModel instance) =>
        RunUiActionAsync(() => viewModel.StartAsync(instance, lifetime.Token));

    internal async Task FocusFromTrayAsync(InstanceViewModel instance)
    {
        viewModel.SelectedInstance = instance;
        if (viewModel.FocusDesktop(instance))
        {
            return;
        }
        await viewModel.RefreshStatusesAsync(lifetime.Token);
        if (!viewModel.FocusDesktop(instance))
        {
            throw new InvalidOperationException($"未找到“{instance.DesktopTitle}”的可聚焦主窗口。");
        }
    }

    internal async Task StopFromTrayAsync(InstanceViewModel instance)
    {
        if (MessageBox.Show(
                $"停止“{instance.DesktopTitle}”？不会影响其他实例。",
                "停止实例",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question) == MessageBoxResult.Yes)
        {
            await viewModel.StopAsync(instance, lifetime.Token);
        }
    }

    internal async Task RestartFromTrayAsync(InstanceViewModel instance)
    {
        if (MessageBox.Show(
                $"重启“{instance.DesktopTitle}”并应用当前皮肤设置？",
                "重启实例",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question) == MessageBoxResult.Yes)
        {
            await viewModel.StartAsync(instance, lifetime.Token);
        }
    }

    private async void AddProfile_Click(object sender, RoutedEventArgs e) =>
        await RunUiActionAsync(() => viewModel.AddProfileAsync(lifetime.Token));

    private void Settings_Click(object sender, RoutedEventArgs e) => viewModel.OpenSettingsFolder();

    private async void StartInstance_Click(object sender, RoutedEventArgs e) =>
        await StartInstanceFromSenderAsync(sender);

    private async void StopInstance_Click(object sender, RoutedEventArgs e) =>
        await StopInstanceFromSenderAsync(sender);

    private async void VerifyInstance_Click(object sender, RoutedEventArgs e) =>
        await VerifyInstanceFromSenderAsync(sender);

    private void OpenLogs_Click(object sender, RoutedEventArgs e)
    {
        if (GetInstance(sender) is { } instance)
        {
            viewModel.OpenLogs(instance);
        }
    }

    private async void StartSelected_Click(object sender, RoutedEventArgs e) =>
        await StartInstanceAsync(viewModel.SelectedInstance);

    private async void StopSelected_Click(object sender, RoutedEventArgs e) =>
        await StopInstanceAsync(viewModel.SelectedInstance);

    private async void RestoreSelected_Click(object sender, RoutedEventArgs e)
    {
        var instance = viewModel.SelectedInstance;
        if (instance is null)
        {
            return;
        }
        var result = MessageBox.Show(
            $"将关闭“{instance.Name}”的皮肤会话，并以无皮肤方式重新打开该实例。继续吗？",
            "恢复无皮肤状态",
            MessageBoxButton.YesNo,
            MessageBoxImage.Question);
        if (result == MessageBoxResult.Yes)
        {
            await RunUiActionAsync(() => viewModel.RestoreAsync(instance, lifetime.Token));
        }
    }

    private async void VerifySelected_Click(object sender, RoutedEventArgs e) =>
        await VerifyInstanceAsync(viewModel.SelectedInstance);

    private async void ChooseBackground_Click(object sender, RoutedEventArgs e)
    {
        var instance = viewModel.SelectedInstance;
        if (instance is null)
        {
            return;
        }
        var dialog = new OpenFileDialog
        {
            Title = "选择实例背景图",
            Filter = "支持的图片|*.png;*.jpg;*.jpeg;*.webp|所有文件|*.*",
            Multiselect = false,
            CheckFileExists = true,
        };
        if (dialog.ShowDialog(this) == true)
        {
            await RunUiActionAsync(() => viewModel.SetAppearanceAsync(
                instance, dialog.FileName, clearImage: false, lifetime.Token));
        }
    }

    private async void ClearBackground_Click(object sender, RoutedEventArgs e)
    {
        var instance = viewModel.SelectedInstance;
        if (instance is null)
        {
            return;
        }
        if (MessageBox.Show(
                $"清除“{instance.Name}”的自定义背景并恢复内置背景？",
                "清除背景",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question) == MessageBoxResult.Yes)
        {
            await RunUiActionAsync(() => viewModel.SetAppearanceAsync(
                instance, null, clearImage: true, lifetime.Token));
        }
    }

    private async void ApplyAppearance_Click(object sender, RoutedEventArgs e)
    {
        if (viewModel.SelectedInstance is { } instance)
        {
            await RunUiActionAsync(() => viewModel.SetAppearanceAsync(
                instance, null, clearImage: false, lifetime.Token));
        }
    }

    private async void EditProfile_Click(object sender, RoutedEventArgs e)
    {
        if (viewModel.SelectedInstance is { CanManageProfile: true } instance)
        {
            await RunUiActionAsync(() => viewModel.EditProfileAsync(instance, lifetime.Token));
        }
    }

    private async void RemoveProfile_Click(object sender, RoutedEventArgs e)
    {
        if (viewModel.SelectedInstance is not { CanManageProfile: true } instance)
        {
            return;
        }
        if (instance.DesktopRunning)
        {
            MessageBox.Show("请先停止该实例，再移除 API profile。", "实例仍在运行", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        if (MessageBox.Show(
                $"将进入 apicodex 安全移除流程：{instance.Name}。继续吗？",
                "移除实例",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning) == MessageBoxResult.Yes)
        {
            await RunUiActionAsync(() => viewModel.RemoveProfileAsync(instance, lifetime.Token));
        }
    }

    private void OpenSelectedLogs_Click(object sender, RoutedEventArgs e)
    {
        if (viewModel.SelectedInstance is { } instance)
        {
            viewModel.OpenLogs(instance);
        }
    }

    private async void ChangePort_Click(object sender, RoutedEventArgs e)
    {
        var instance = viewModel.SelectedInstance;
        if (instance is null)
        {
            return;
        }
        var port = ShowPortDialog(instance.Port);
        if (port is not null)
        {
            await RunUiActionAsync(() => viewModel.ChangePortAsync(instance, port.Value, lifetime.Token));
        }
    }

    private async Task StartInstanceFromSenderAsync(object sender) =>
        await StartInstanceAsync(GetInstance(sender));

    private async Task StopInstanceFromSenderAsync(object sender) =>
        await StopInstanceAsync(GetInstance(sender));

    private async Task VerifyInstanceFromSenderAsync(object sender) =>
        await VerifyInstanceAsync(GetInstance(sender));

    private async Task StartInstanceAsync(InstanceViewModel? instance)
    {
        if (instance is null)
        {
            return;
        }
        viewModel.SelectedInstance = instance;
        if (instance.DesktopRunning && MessageBox.Show(
                $"“{instance.Name}”正在运行。重新启动并应用当前皮肤设置？",
                "重启实例",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question) != MessageBoxResult.Yes)
        {
            return;
        }
        await RunUiActionAsync(() => viewModel.StartAsync(instance, lifetime.Token));
    }

    private async Task StopInstanceAsync(InstanceViewModel? instance)
    {
        if (instance is null)
        {
            return;
        }
        viewModel.SelectedInstance = instance;
        if (MessageBox.Show(
                $"停止“{instance.Name}”及其独立皮肤会话？不会影响其他实例。",
                "停止实例",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question) == MessageBoxResult.Yes)
        {
            await RunUiActionAsync(() => viewModel.StopAsync(instance, lifetime.Token));
        }
    }

    private async Task VerifyInstanceAsync(InstanceViewModel? instance)
    {
        if (instance is null)
        {
            return;
        }
        viewModel.SelectedInstance = instance;
        await RunUiActionAsync(() => viewModel.VerifyAsync(instance, lifetime.Token));
    }

    private static InstanceViewModel? GetInstance(object sender) =>
        sender is FrameworkElement { Tag: InstanceViewModel instance } ? instance : null;

    private void MainWindow_Closing(object? sender, CancelEventArgs e)
    {
        if (Application.Current is App { ExitRequested: true })
        {
            return;
        }
        e.Cancel = true;
        ShowInTaskbar = false;
        Hide();
        tray.ShowBackgroundNotice();
    }

    private void MainWindow_Closed(object? sender, EventArgs e)
    {
        refreshTimer?.Stop();
        lifetime.Cancel();
        tray.Dispose();
        lifetime.Dispose();
    }

    private async Task RunUiActionAsync(Func<Task> action, bool showError = true)
    {
        try
        {
            await action();
        }
        catch (OperationCanceledException) when (lifetime.IsCancellationRequested)
        {
        }
        catch (Exception exception)
        {
            if (showError)
            {
                MessageBox.Show(exception.Message, "操作失败", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }
    }

    private int? ShowPortDialog(int currentPort)
    {
        var dialog = new Window
        {
            Title = "修改实例端口",
            Owner = this,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            SizeToContent = SizeToContent.WidthAndHeight,
            ResizeMode = ResizeMode.NoResize,
            Background = System.Windows.Media.Brushes.White,
            FontFamily = FontFamily,
        };
        var input = new TextBox { Text = currentPort.ToString(), Width = 220, Margin = new Thickness(0, 8, 0, 14) };
        var ok = new Button { Content = "保存", Width = 82, Height = 34, IsDefault = true };
        var cancel = new Button { Content = "取消", Width = 82, Height = 34, IsCancel = true, Margin = new Thickness(8, 0, 0, 0) };
        ok.Click += (_, _) => dialog.DialogResult = true;
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        buttons.Children.Add(ok);
        buttons.Children.Add(cancel);
        var content = new StackPanel { Margin = new Thickness(22) };
        content.Children.Add(new TextBlock { Text = "监听端口", FontWeight = FontWeights.SemiBold });
        content.Children.Add(input);
        content.Children.Add(buttons);
        dialog.Content = content;
        input.SelectAll();
        input.Focus();
        return dialog.ShowDialog() == true && int.TryParse(input.Text, out var port) ? port : null;
    }
}
