using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using BloodGlucoseBuddy.Core;

namespace BloodGlucoseBuddy;

/// <summary>The whole app: a tray icon that shows your number, polls Dexcom, and keeps Discord up to date.</summary>
sealed class TrayApp : ApplicationContext
{
    /// <summary>The "Blood Glucose" application on Discord's developer site. Not a secret.</summary>
    private const string DiscordClientId = "1558184055437004933";
    private static readonly string SettingsPath =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Blood Glucose Buddy", "settings.json");

    public AppSettings Settings { get; }
    public Reading? Reading { get; private set; }
    public string? DexcomProblem { get; private set; }
    public bool IsSignedIn { get; private set; }
    public Icon AppIcon { get; }
    public event Action? Changed;

    private readonly DexcomClient dexcom = new();
    private readonly DiscordPipe discord = new(DiscordClientId);
    private readonly SemaphoreSlim discordLock = new(1, 1);
    private readonly NotifyIcon tray;
    private readonly System.Windows.Forms.Timer timer = new() { Interval = 30_000 };
    private Icon? numberIcon;
    private SettingsForm? settingsForm;
    private bool discordConnected;
    private string? discordProblem;
    private DateTimeOffset? lastFetch;
    /// <summary>Set after a wrong password or lockout so we stop retrying and don't get the Dexcom account locked.</summary>
    private bool authBlocked;
    private bool ticking;

    private ToolStripMenuItem readingItem = null!, ageItem = null!, dexcomItem = null!, discordItem = null!,
        modeMenu = null!, unitMenu = null!, verbMenu = null!, startupItem = null!, settingsItem = null!;

    public TrayApp()
    {
        Settings = AppSettings.Load(SettingsPath);
        IsSignedIn = Settings.Username.Length > 0 && CredentialStore.Password() is not null;
        using (var s = typeof(TrayApp).Assembly.GetManifestResourceStream("app.ico")!) AppIcon = new Icon(s);
        tray = new NotifyIcon { Icon = AppIcon, Text = "Blood Glucose Buddy", Visible = true, ContextMenuStrip = BuildMenu() };
        tray.MouseClick += (_, e) => { if (e.Button == MouseButtons.Left) ShowSettings(); };
        try { Startup.RefreshPath(); } catch (Exception e) when (e is UnauthorizedAccessException or System.Security.SecurityException) { }
        timer.Tick += async (_, _) => await TickAsync();
        timer.Start();
        _ = TickAsync();
        if (!IsSignedIn) ShowSettings();
    }

    // MARK: Menu

    private ContextMenuStrip BuildMenu()
    {
        var menu = new ContextMenuStrip();
        readingItem = new ToolStripMenuItem { Enabled = false };
        ageItem = new ToolStripMenuItem { Enabled = false };
        dexcomItem = new ToolStripMenuItem { Enabled = false };
        discordItem = new ToolStripMenuItem { Enabled = false };
        modeMenu = Choices("Show on Discord", Enum.GetValues<DisplayMode>(), m => m.Label(), m => Settings.Mode = m, () => Settings.Mode);
        unitMenu = Choices("Units", Enum.GetValues<GlucoseUnit>(), u => u.Label(), u => Settings.Unit = u, () => Settings.Unit);
        verbMenu = Choices("Status word", Enum.GetValues<StatusVerb>(), v => $"{v.Label()} Blood Glucose", v => Settings.Verb = v, () => Settings.Verb);
        startupItem = new ToolStripMenuItem("Start with Windows", null, (_, _) =>
        {
            try { Startup.Enabled = !Startup.Enabled; }
            catch (Exception e) { DexcomProblem = $"Couldn't change Start with Windows: {e.Message}"; }
        });
        settingsItem = new ToolStripMenuItem("Settings…", null, (_, _) => ShowSettings());
        menu.Items.AddRange([readingItem, ageItem, dexcomItem, discordItem, new ToolStripSeparator(),
            modeMenu, unitMenu, verbMenu, startupItem, new ToolStripSeparator(),
            settingsItem, new ToolStripMenuItem("Quit Blood Glucose Buddy", null, (_, _) => ExitThread())]);
        menu.Opening += (_, _) => RefreshMenu();
        return menu;
    }

    private ToolStripMenuItem Choices<T>(string title, T[] values, Func<T, string> label, Action<T> set, Func<T> current) where T : struct, Enum
    {
        var parent = new ToolStripMenuItem(title);
        foreach (var v in values)
            parent.DropDownItems.Add(new ToolStripMenuItem(label(v), null, (_, _) => { set(v); SettingsChanged(); }) { Tag = v });
        parent.DropDownOpening += (_, _) =>
        {
            foreach (ToolStripMenuItem item in parent.DropDownItems) item.Checked = item.Tag is T t && t.Equals(current());
        };
        return parent;
    }

    private void RefreshMenu()
    {
        readingItem.Text = IsSignedIn ? ReadingLine : "Not signed in to Dexcom";
        ageItem.Text = AgeLine ?? "";
        ageItem.Visible = IsSignedIn && AgeLine is not null;
        dexcomItem.Text = DexcomProblem ?? "";
        dexcomItem.Visible = DexcomProblem is not null;
        discordItem.Text = DiscordLine;
        startupItem.Checked = Startup.Enabled;
        settingsItem.Text = IsSignedIn ? "Settings…" : "Sign In…";
    }

    public string ReadingLine
    {
        get
        {
            if (Reading is not { } r) return "Waiting for first reading…";
            if (!Presence.IsFresh(r, DateTimeOffset.UtcNow)) return "No recent reading";
            return $"{Presence.Format(r.Mgdl, Settings.Unit)} {r.Trend.Arrow()} {r.Trend.Word()}".Trim();
        }
    }

    public string? AgeLine
    {
        get
        {
            if (Reading is not { } r) return null;
            var minutes = (int)(DateTimeOffset.UtcNow - r.Date).TotalMinutes;
            return minutes < 1 ? "Reading from just now" : $"Reading from {minutes} min ago";
        }
    }

    public string DiscordLine => discordConnected
        ? (IsSignedIn ? "Discord: showing your status" : "Discord: connected")
        : discordProblem ?? "Discord: connecting…";

    public void ShowSettings()
    {
        if (settingsForm is null || settingsForm.IsDisposed) settingsForm = new SettingsForm(this);
        settingsForm.Show();
        if (settingsForm.WindowState == FormWindowState.Minimized) settingsForm.WindowState = FormWindowState.Normal;
        settingsForm.Activate();
    }

    public void SettingsChanged()
    {
        try { Settings.Save(SettingsPath); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { DexcomProblem = $"Couldn't save settings: {e.Message}"; }
        UpdateTray();
        Changed?.Invoke();
        _ = PushToDiscordAsync();
    }

    // MARK: Account

    /// <summary>Returns an error message, or null on success.</summary>
    public async Task<string?> SignInAsync(string username, string password, DexcomRegion region)
    {
        username = username.Trim();
        dexcom.Reset();
        try
        {
            var r = await dexcom.LatestReadingAsync(username, password, region);
            if (!CredentialStore.Save(username, password)) return "Couldn't save the password to Windows Credential Manager.";
            Settings.Username = username;
            Settings.Region = region;
            IsSignedIn = true;
            authBlocked = false;
            lastFetch = DateTimeOffset.UtcNow;
            Reading = r;
            DexcomProblem = r is null ? "Signed in, but Dexcom has no readings from the last 24 hours. Is Share turned on?" : null;
            if (!Settings.StartupSetUp)
            {
                Settings.StartupSetUp = true;
                try { Startup.Enabled = true; } catch (Exception e) when (e is UnauthorizedAccessException or System.Security.SecurityException) { }
            }
            SettingsChanged();
            return null;
        }
        catch (DexcomException e)
        {
            dexcom.Reset();
            return e.Message;
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
        {
            dexcom.Reset();
            return $"Couldn't reach Dexcom. Check your internet connection. ({e.Message})";
        }
    }

    public void SignOut()
    {
        CredentialStore.Delete();
        Settings.Username = "";
        IsSignedIn = false;
        Reading = null;
        DexcomProblem = null;
        dexcom.Reset();
        SettingsChanged();
    }

    // MARK: Loop

    private async Task TickAsync()
    {
        if (ticking) return;
        ticking = true;
        try
        {
            if (IsSignedIn && !authBlocked && ShouldFetch(DateTimeOffset.UtcNow)) await FetchAsync();
            await PushToDiscordAsync();
            UpdateTray();
            Changed?.Invoke();
        }
        finally { ticking = false; }
    }

    private bool ShouldFetch(DateTimeOffset now)
    {
        if (lastFetch is not { } last) return true;
        var sinceFetch = now - last;
        if (sinceFetch >= TimeSpan.FromMinutes(5)) return true;
        // A new reading lands every 5 minutes; once ours is that old, check each minute so we catch it quickly.
        return Reading is { } r && now - r.Date > TimeSpan.FromSeconds(310) && sinceFetch >= TimeSpan.FromMinutes(1);
    }

    private async Task FetchAsync()
    {
        lastFetch = DateTimeOffset.UtcNow;
        if (CredentialStore.Password() is not { } password)
        {
            IsSignedIn = false;
            return;
        }
        try
        {
            if (await dexcom.LatestReadingAsync(Settings.Username, password, Settings.Region) is { } r)
            {
                Reading = r;
                DexcomProblem = null;
            }
            else DexcomProblem = "Dexcom has no readings from the last 24 hours.";
        }
        catch (DexcomException e) when (e.Kind is DexcomErrorKind.BadCredentials or DexcomErrorKind.LockedOut)
        {
            authBlocked = true;
            DexcomProblem = e.Message + " Open Settings to sign in again.";
        }
        catch (Exception e) when (e is DexcomException or HttpRequestException or TaskCanceledException or System.Text.Json.JsonException)
        {
            DexcomProblem = $"Couldn't reach Dexcom. Will keep trying. ({e.Message})";
        }
    }

    /// <summary>Sends the current status every tick, so a restarted Discord picks it up again within 30 seconds.</summary>
    private async Task PushToDiscordAsync()
    {
        var activity = IsSignedIn
            ? Presence.Activity(Reading, DateTimeOffset.UtcNow, Settings.Mode, Settings.Unit, Settings.Verb, Settings.Low, Settings.High)
            : null;
        await discordLock.WaitAsync();
        try
        {
            await Task.Run(() => discord.SetActivity(activity));
            discordConnected = true;
            discordProblem = null;
        }
        catch (Exception e)
        {
            discordConnected = false;
            discordProblem = "Discord: " + (e is DiscordException ? e.Message : "couldn't connect.");
        }
        finally { discordLock.Release(); }
    }

    // MARK: Tray icon

    private void UpdateTray()
    {
        if (IsSignedIn && Reading is { } r && Presence.IsFresh(r, DateTimeOffset.UtcNow))
        {
            var band = Presence.BandOf(r.Mgdl, Settings.Low, Settings.High);
            SetIcon(NumberIcon(Presence.Value(r.Mgdl, Settings.Unit), band));
            SetTip($"{ReadingLine}\n{AgeLine}");
        }
        else
        {
            SetIcon(null);
            SetTip(IsSignedIn ? "Blood Glucose Buddy: no recent reading" : "Blood Glucose Buddy: not signed in");
        }
    }

    private void SetTip(string text) => tray.Text = text.Length > 127 ? text[..127] : text;

    private void SetIcon(Icon? icon)
    {
        tray.Icon = icon ?? AppIcon;
        numberIcon?.Dispose();
        numberIcon = icon;
    }

    /// <summary>The number on a colored square, drawn at the tray's real pixel size so it stays sharp.</summary>
    private static Icon NumberIcon(string text, Band band)
    {
        var size = Math.Max(16, SystemInformation.SmallIconSize.Width);
        var (bg, fg) = band switch
        {
            Band.Low => (Color.FromArgb(0xED, 0x42, 0x45), Color.White),
            Band.High => (Color.FromArgb(0xFA, 0xA6, 0x1A), Color.Black),
            _ => (Color.FromArgb(0x3B, 0xA5, 0x5C), Color.White),
        };
        using var bmp = new Bitmap(size, size);
        using (var g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            using (var path = RoundedSquare(size, size / 5f))
            using (var brush = new SolidBrush(bg))
                g.FillPath(brush, path);
            using var format = new StringFormat(StringFormat.GenericTypographic)
            {
                Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center,
                FormatFlags = StringFormatFlags.NoWrap,
            };
            var em = (float)size;
            Font font = new("Segoe UI", em, FontStyle.Bold, GraphicsUnit.Pixel);
            while (em > 4 && g.MeasureString(text, font, PointF.Empty, format).Width > size - 1)
            {
                font.Dispose();
                em -= 0.5f;
                font = new Font("Segoe UI", em, FontStyle.Bold, GraphicsUnit.Pixel);
            }
            using (font)
            using (var textBrush = new SolidBrush(fg))
                g.DrawString(text, font, textBrush, new RectangleF(0, 0, size, size), format);
        }
        var handle = bmp.GetHicon();
        try { return (Icon)Icon.FromHandle(handle).Clone(); }
        finally { DestroyIcon(handle); }
    }

    private static GraphicsPath RoundedSquare(int size, float radius)
    {
        var d = radius * 2;
        var path = new GraphicsPath();
        path.AddArc(0, 0, d, d, 180, 90);
        path.AddArc(size - d - 1, 0, d, d, 270, 90);
        path.AddArc(size - d - 1, size - d - 1, d, d, 0, 90);
        path.AddArc(0, size - d - 1, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    [DllImport("user32.dll")]
    private static extern bool DestroyIcon(IntPtr handle);

    protected override void ExitThreadCore()
    {
        timer.Stop();
        tray.Visible = false;
        discord.Dispose();  // closing the pipe clears the status on Discord
        base.ExitThreadCore();
    }
}
