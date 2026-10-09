using System.Drawing.Imaging;
using BloodGlucoseBuddy.Core;

namespace BloodGlucoseBuddy;

/// <summary>Run by the GitHub Actions build on a throwaway Windows machine, never by users:
///   --self-test &lt;dir&gt;    exercises the Windows-only parts for real and writes self-test.txt
///   --screenshots &lt;dir&gt;  renders the app's screens from made-up data into PNGs</summary>
static class Harness
{
    public static int SelfTest(string dir)
    {
        Directory.CreateDirectory(dir);
        var log = new List<string>();
        var failed = 0;
        void Check(string name, Func<string> test)
        {
            try { log.Add($"PASS  {name}: {test()}"); }
            catch (Exception e) { failed++; log.Add($"FAIL  {name}: {e.GetType().Name}: {e.Message}"); }
        }

        Check("Credential Manager round trip", () =>
        {
            CredentialStore.Target = "BloodGlucoseBuddy/SelfTest";  // its own entry, never the real one
            const string secret = "p@ss wörd ✓";
            if (!CredentialStore.Save("self-test", secret)) throw new Exception("CredWrite failed");
            if (CredentialStore.Password() != secret) throw new Exception("read back a different password");
            CredentialStore.Delete();
            if (CredentialStore.Password() is not null) throw new Exception("still there after delete");
            return "saved, read back, deleted";
        });

        Check("Start with Windows", () =>
        {
            Startup.Name = "Blood Glucose Buddy SelfTest";
            Startup.Enabled = true;
            if (!Startup.Enabled) throw new Exception("not on after turning on");
            Startup.Enabled = false;
            if (Startup.Enabled) throw new Exception("still on after turning off");
            return "turned on and off";
        });

        Check("Discord pipe", () =>
        {
            using var pipe = new DiscordPipe("1558184055437004933");
            try
            {
                pipe.SetActivity(null);
                return "Discord is running here; cleared the status";
            }
            catch (DiscordException e) when (e.Message == "Discord isn't open.")
            {
                return "no Discord on this machine, reported as \"Discord isn't open.\"";
            }
        });

        Check("Dexcom Share over HTTPS", () =>
        {
            try
            {
                new DexcomClient().LatestReadingAsync("bgb-self-test@example.invalid", "not-a-password", DexcomRegion.US).GetAwaiter().GetResult();
                throw new Exception("a made-up account was accepted");
            }
            catch (DexcomException e) when (e.Kind == DexcomErrorKind.BadCredentials)
            {
                return "reached Dexcom; made-up account turned down as expected";
            }
        });

        Check("Tray number icons", () =>
        {
            foreach (var (text, band) in new[] { ("112", Band.InRange), ("6.2", Band.InRange), ("HIGH", Band.High), ("LOW", Band.Low) })
                using (var icon = TrayApp.NumberIcon(text, band, 32))
                    if (icon.Width != 32) throw new Exception($"{text} came out {icon.Width}px");
            return "drew 4 icons";
        });

        Check("Settings window builds", () =>
        {
            TrayApp.Demo = true;
            using var app = new TrayApp();
            using var form = new SettingsForm(app);
            form.CreateControl();
            return "built";
        });

        log.Add(failed == 0 ? "ALL PASSED" : $"{failed} FAILED");
        File.WriteAllLines(Path.Combine(dir, "self-test.txt"), log);
        return failed == 0 ? 0 : 1;
    }

    public static int Screenshots(string dir)
    {
        Directory.CreateDirectory(dir);
        TrayApp.Demo = true;
        TrayApp.DemoReading = new Reading(112, Trend.FortyFiveUp, DateTimeOffset.UtcNow.AddMinutes(-2));
        var log = new List<string>();
        var failed = 0;
        void Shot(string name, Func<Bitmap> render)
        {
            try
            {
                using var bmp = render();
                var path = Path.Combine(dir, $"{name}.png");
                bmp.Save(path, ImageFormat.Png);
                if (new FileInfo(path).Length == 0) throw new Exception("empty file");
                log.Add($"OK    {name} ({bmp.Width}x{bmp.Height})");
            }
            catch (Exception e) { failed++; log.Add($"FAIL  {name}: {e.GetType().Name}: {e.Message}"); }
        }

        using var app = new TrayApp();
        Shot("01-sign-in", () => Capture(new SettingsForm(app)));
        app.DemoSignIn("you@example.com");
        Shot("02-settings-signed-in", () => Capture(new SettingsForm(app)));
        Shot("03-menu", () => CaptureMenu(app.Menu));
        Shot("04-tray-icons", TrayStrip);

        log.Add(failed == 0 ? "ALL CAPTURED" : $"{failed} FAILED");
        File.WriteAllLines(Path.Combine(dir, "screenshots.txt"), log);
        return failed == 0 ? 0 : 1;
    }

    private static Bitmap Capture(Form form)
    {
        using (form)
        {
            form.StartPosition = FormStartPosition.Manual;
            form.Location = new Point(40, 40);
            form.Show();
            Application.DoEvents();
            var bmp = new Bitmap(form.Width, form.Height);
            form.DrawToBitmap(bmp, new Rectangle(Point.Empty, form.Size));
            form.Close();
            return bmp;
        }
    }

    private static Bitmap CaptureMenu(ContextMenuStrip menu)
    {
        menu.Show(new Point(40, 40));
        Application.DoEvents();
        var bmp = new Bitmap(menu.Width, menu.Height);
        menu.DrawToBitmap(bmp, new Rectangle(Point.Empty, menu.Size));
        menu.Close();
        return bmp;
    }

    /// <summary>The tray icon in each state, at 3x so the README can show them clearly.</summary>
    private static Bitmap TrayStrip()
    {
        var icons = new[] { ("112", Band.InRange), ("64", Band.Low), ("245", Band.High), ("6.2", Band.InRange) };
        const int size = 96, gap = 24;
        var bmp = new Bitmap(gap + icons.Length * (size + gap), size + 2 * gap);
        using var g = Graphics.FromImage(bmp);
        g.Clear(Color.FromArgb(0x20, 0x20, 0x20));
        for (var i = 0; i < icons.Length; i++)
            using (var icon = TrayApp.NumberIcon(icons[i].Item1, icons[i].Item2, size))
                g.DrawIcon(icon, new Rectangle(gap + i * (size + gap), gap, size, size));
        return bmp;
    }
}
