using BloodGlucoseBuddy.Core;
using Microsoft.Web.WebView2.WinForms;

namespace BloodGlucoseBuddy;

/// <summary>Shows Dexcom's own sign-in page. When it lands on the profile page, reads the account ID from the address.
/// Only the address is read; what the user types on Dexcom's page never reaches this app.</summary>
sealed class AccountFinderForm : Form
{
    public string? FoundId { get; private set; }
    private readonly WebView2 web;
    private readonly string dataFolder = Path.Combine(Path.GetTempPath(), $"BloodGlucoseBuddy-finder-{Guid.NewGuid():N}");

    public AccountFinderForm(Uri start)
    {
        Text = "Sign in to Dexcom to find your account ID";
        StartPosition = FormStartPosition.CenterParent;
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(560, 720);
        // Private mode in a throwaway folder: nothing from this sign-in is kept.
        web = new WebView2
        {
            Dock = DockStyle.Fill,
            CreationProperties = new CoreWebView2CreationProperties { UserDataFolder = dataFolder, IsInPrivateModeEnabled = true },
        };
        Controls.Add(web);
        // The profile page is a single-page app, so watch the address itself, not just page loads.
        web.SourceChanged += (_, _) => Check(web.Source);
        web.NavigationCompleted += (_, _) => Check(web.Source);
        Load += async (_, _) =>
        {
            try
            {
                await web.EnsureCoreWebView2Async();
                web.CoreWebView2.HistoryChanged += (_, _) => Check(web.Source);
                web.Source = start;
            }
            catch (Exception e)
            {
                MessageBox.Show(this, $"Couldn't open Dexcom's sign-in page.\n\n{e.Message}\n\nThis needs Microsoft Edge WebView2, which comes with Windows 11.",
                    Text, MessageBoxButtons.OK, MessageBoxIcon.Warning);
                Close();
            }
        };
        FormClosed += (_, _) =>
        {
            web.Dispose();
            try { Directory.Delete(dataFolder, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        };
    }

    private void Check(Uri? url)
    {
        if (FoundId is not null || DexcomParser.AccountIdFromProfileUrl(url) is not { } id) return;
        FoundId = id;
        DialogResult = DialogResult.OK;
        BeginInvoke(Close);
    }
}
