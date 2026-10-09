using BloodGlucoseBuddy.Core;

namespace BloodGlucoseBuddy;

sealed class SettingsForm : Form
{
    private const int TextWidth = 440;
    private readonly TrayApp app;
    private readonly FlowLayoutPanel signedOut, signedIn;
    private readonly Label signedInAs = Wrap(""), error = Wrap(""), note = Wrap(""), lowLabel = Caption(""), highLabel = Caption("");
    private readonly TextBox username = new() { Width = 300 };
    private readonly TextBox password = new() { Width = 300, UseSystemPasswordChar = true };
    private readonly ComboBox region = Combo(Enum.GetValues<DexcomRegion>().Select(r => r.Label()));
    private readonly ComboBox mode = Combo(Enum.GetValues<DisplayMode>().Select(m => m.Label()));
    private readonly ComboBox unit = Combo(Enum.GetValues<GlucoseUnit>().Select(u => u.Label()));
    private readonly ComboBox verb = Combo(Enum.GetValues<StatusVerb>().Select(v => $"{v.Label()} Blood Glucose"));
    private readonly NumericUpDown low = new() { Minimum = 40, Maximum = 150, Increment = 5, Width = 70 };
    private readonly NumericUpDown high = new() { Minimum = 120, Maximum = 400, Increment = 5, Width = 70 };
    private readonly Button signIn = new() { Text = "Sign In", AutoSize = true };
    private readonly Button find = new() { Text = "Find My Account ID…", AutoSize = true };
    private bool loading;
    private FlowLayoutPanel root = null!;

    public SettingsForm(TrayApp app)
    {
        this.app = app;
        Text = "Blood Glucose Buddy";
        Icon = app.AppIcon;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        AutoScaleMode = AutoScaleMode.Dpi;
        AcceptButton = signIn;
        error.ForeColor = Color.Firebrick;
        note.ForeColor = Color.ForestGreen;

        var signOutButton = new Button { Text = "Sign Out", AutoSize = true };
        signOutButton.Click += (_, _) => app.SignOut();
        signedIn = Column(signedInAs, signOutButton);

        signedOut = Column(
            Wrap("Use your own Dexcom login, not a follower's. Phone numbers need a + and country code, like +15551234567."),
            Row(Caption("Username, email or phone"), username),
            Row(Caption("Password"), password),
            Row(Caption("Region"), region),
            error, note,
            Row(signIn),
            Wrap("Email or phone not working? Lots of Dexcom accounts need their account ID instead. Sign in to Dexcom here and we'll fill it in."),
            Row(find));

        var root = Column(
            Group("Dexcom account", Column(signedIn, signedOut)),
            Group("On Discord", Column(
                Row(Caption("Show"), mode),
                Row(Caption("Units"), unit),
                Row(Caption("Status word"), verb))),
            Group("Colored dot mode", Column(Row(lowLabel, low), Row(highLabel, high))),
            Group("Not showing on Discord?", Wrap(
                "In Discord, click the gear at the bottom left to open User Settings, choose Activity Privacy, and turn on “Share your detected activities with others.” Discord keeps your status hidden until that's on.")),
            Muted(Wrap("Your status is visible to everyone in every Discord server you're in. To hide it from a server, right-click the server in Discord, choose Privacy Settings, and turn off Activity Status.")),
            Muted(Wrap("Not a medical device. Never make treatment decisions from Blood Glucose Buddy; use your Dexcom app or receiver. It reads Dexcom's unofficial Share feed, which can stop working without notice. Not affiliated with Dexcom or Discord.")));
        root.Padding = new Padding(12);
        this.root = root;
        // Every box the same width as the widest one.
        var boxes = root.Controls.OfType<GroupBox>().ToList();
        var widest = boxes.Max(b => b.GetPreferredSize(Size.Empty).Width);
        foreach (var b in boxes) b.MinimumSize = new Size(widest, 0);
        // Scrolls on short screens instead of cutting the bottom (and the disclaimer) off.
        Controls.Add(new Panel { Dock = DockStyle.Fill, AutoScroll = true, Controls = { root } });

        signIn.Click += async (_, _) => await SignInAsync();
        find.Click += (_, _) => FindAccountId();
        mode.SelectedIndexChanged += (_, _) => Apply(() => app.Settings.Mode = (DisplayMode)mode.SelectedIndex);
        unit.SelectedIndexChanged += (_, _) => Apply(() => app.Settings.Unit = (GlucoseUnit)unit.SelectedIndex);
        verb.SelectedIndexChanged += (_, _) => Apply(() => app.Settings.Verb = (StatusVerb)verb.SelectedIndex);
        low.ValueChanged += (_, _) => Apply(() => app.Settings.Low = (int)low.Value);
        high.ValueChanged += (_, _) => Apply(() => app.Settings.High = (int)high.Value);
        region.SelectedIndex = (int)app.Settings.Region;

        app.Changed += Reload;
        FormClosed += (_, _) => app.Changed -= Reload;
        Reload();
    }

    private void Apply(Action change)
    {
        if (loading) return;
        change();
        app.SettingsChanged();
    }

    private void Reload()
    {
        if (IsDisposed) return;
        loading = true;
        signedIn.Visible = app.IsSignedIn;
        signedOut.Visible = !app.IsSignedIn;
        signedInAs.Text = $"Signed in as {app.Settings.Username} ({app.Settings.Region.Label()}).\n{app.ReadingLine}\n{app.DiscordLine}"
            + (app.DexcomProblem is { } p ? $"\n{p}" : "");
        mode.SelectedIndex = (int)app.Settings.Mode;
        unit.SelectedIndex = (int)app.Settings.Unit;
        verb.SelectedIndex = (int)app.Settings.Verb;
        low.Value = Math.Clamp(app.Settings.Low, (int)low.Minimum, (int)low.Maximum);
        high.Value = Math.Clamp(app.Settings.High, (int)high.Minimum, (int)high.Maximum);
        lowLabel.Text = $"Low below {Presence.Format(app.Settings.Low, app.Settings.Unit)}";
        highLabel.Text = $"High above {Presence.Format(app.Settings.High, app.Settings.Unit)}";
        error.Visible = error.Text.Length > 0;
        note.Visible = note.Text.Length > 0;
        loading = false;
        FitToScreen();
    }

    private void FitToScreen()
    {
        var content = root.GetPreferredSize(Size.Empty);
        var room = Screen.FromControl(this).WorkingArea.Height - (Height - ClientSize.Height) - 40;
        var scrolls = content.Height > room;
        ClientSize = new Size(content.Width + (scrolls ? SystemInformation.VerticalScrollBarWidth : 0), Math.Min(content.Height, room));
    }

    /// <summary>The whole window's contents at full height, for the screenshot harness.</summary>
    public Bitmap RenderContents()
    {
        var size = root.GetPreferredSize(Size.Empty);
        root.Size = size;
        var bmp = new Bitmap(size.Width, size.Height);
        root.DrawToBitmap(bmp, new Rectangle(Point.Empty, size));
        return bmp;
    }

    private async Task SignInAsync()
    {
        if (username.Text.Trim().Length == 0 || password.Text.Length == 0)
        {
            error.Text = "Type your Dexcom username (or account ID) and password first.";
            error.Visible = true;
            FitToScreen();
            return;
        }
        signIn.Enabled = false;
        signIn.Text = "Signing In…";
        error.Text = note.Text = "";
        error.Visible = note.Visible = false;
        var problem = await app.SignInAsync(username.Text, password.Text, (DexcomRegion)region.SelectedIndex);
        signIn.Enabled = true;
        signIn.Text = "Sign In";
        if (problem is null) password.Clear();
        else { error.Text = problem; error.Visible = true; FitToScreen(); }
    }

    private void FindAccountId()
    {
        if (((DexcomRegion)region.SelectedIndex).AccountSite() is not { } site)
        {
            error.Text = "Find My Account ID isn't available for Japan accounts yet.";
            error.Visible = true;
            FitToScreen();
            return;
        }
        using var finder = new AccountFinderForm(site);
        if (finder.ShowDialog(this) == DialogResult.OK && finder.FoundId is { } id)
        {
            username.Text = id;
            error.Text = "";
            error.Visible = false;
            note.Text = "Found your account ID. Now type your Dexcom password and click Sign In.";
            note.Visible = true;
            FitToScreen();
            password.Focus();
        }
    }

    // MARK: Layout helpers

    private static FlowLayoutPanel Column(params Control[] children)
    {
        var p = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, WrapContents = false, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, Margin = new Padding(0) };
        p.Controls.AddRange(children);
        return p;
    }

    private static FlowLayoutPanel Row(params Control[] children)
    {
        var p = new FlowLayoutPanel { FlowDirection = FlowDirection.LeftToRight, WrapContents = false, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, Margin = new Padding(0, 3, 0, 3) };
        p.Controls.AddRange(children);
        return p;
    }

    private static GroupBox Group(string title, Control content)
    {
        var g = new GroupBox { Text = title, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, Padding = new Padding(10, 6, 10, 10), Margin = new Padding(0, 0, 0, 10), MinimumSize = new Size(TextWidth + 24, 0) };
        content.Dock = DockStyle.Fill;
        g.Controls.Add(content);
        return g;
    }

    private static Label Caption(string text) =>
        new() { Text = text, AutoSize = false, Width = 190, TextAlign = ContentAlignment.MiddleLeft, Height = 24 };

    private static Label Wrap(string text) =>
        new() { Text = text, AutoSize = true, MaximumSize = new Size(TextWidth, 0), Margin = new Padding(0, 3, 0, 3) };

    private static Label Muted(Label l)
    {
        l.ForeColor = SystemColors.GrayText;
        return l;
    }

    private static ComboBox Combo(IEnumerable<string> items)
    {
        var c = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 300 };
        c.Items.AddRange(items.Cast<object>().ToArray());
        return c;
    }
}
