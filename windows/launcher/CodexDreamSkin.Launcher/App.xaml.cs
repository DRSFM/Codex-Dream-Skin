using System.Windows;

namespace CodexDreamSkin.Launcher;

public partial class App : System.Windows.Application
{
    private const string MutexName = @"Local\ApiCodexDesktopManager.Mutex.v1";
    private const string ActivationEventName = @"Local\ApiCodexDesktopManager.Activate.v1";
    private readonly CancellationTokenSource activationLifetime = new();
    private Mutex? instanceMutex;
    private EventWaitHandle? activationEvent;
    private bool ownsMutex;

    public bool ExitRequested { get; private set; }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        instanceMutex = new Mutex(initiallyOwned: true, MutexName, out var createdNew);
        ownsMutex = createdNew;
        if (!createdNew)
        {
            try
            {
                using var existingEvent = EventWaitHandle.OpenExisting(ActivationEventName);
                existingEvent.Set();
            }
            catch (WaitHandleCannotBeOpenedException)
            {
            }
            Shutdown();
            return;
        }

        activationEvent = new EventWaitHandle(false, EventResetMode.AutoReset, ActivationEventName);
        var window = new MainWindow();
        MainWindow = window;
        window.Show();
        _ = ListenForActivationAsync(activationLifetime.Token);
    }

    public void RequestExit()
    {
        if (ExitRequested)
        {
            return;
        }
        ExitRequested = true;
        MainWindow?.Close();
        Shutdown();
    }

    protected override void OnSessionEnding(SessionEndingCancelEventArgs e)
    {
        ExitRequested = true;
        base.OnSessionEnding(e);
    }

    protected override void OnExit(ExitEventArgs e)
    {
        activationLifetime.Cancel();
        activationEvent?.Set();
        activationEvent?.Dispose();
        if (ownsMutex)
        {
            try
            {
                instanceMutex?.ReleaseMutex();
            }
            catch (ApplicationException)
            {
            }
        }
        instanceMutex?.Dispose();
        activationLifetime.Dispose();
        base.OnExit(e);
    }

    private async Task ListenForActivationAsync(CancellationToken cancellationToken)
    {
        if (activationEvent is null)
        {
            return;
        }
        try
        {
            await Task.Run(() =>
            {
                var handles = new[] { activationEvent, cancellationToken.WaitHandle };
                while (WaitHandle.WaitAny(handles) == 0 && !cancellationToken.IsCancellationRequested)
                {
                    _ = Dispatcher.BeginInvoke(() =>
                    {
                        if (this.MainWindow is MainWindow window)
                        {
                            window.ShowManager();
                        }
                    });
                }
            }, cancellationToken);
        }
        catch (OperationCanceledException)
        {
        }
        catch (ObjectDisposedException)
        {
        }
    }
}
