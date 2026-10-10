using BloodGlucoseBuddy.Core;
using Xunit;

public class CoreTests
{
    [Fact]
    public void ParsesShareReading()
    {
        var r = DexcomParser.ParseReading("""[{"WT":"Date(1691455258000)","ST":"Date(1691455258000)","DT":"Date(1691455258000-0400)","Value":123,"Trend":"FortyFiveUp"}]""");
        Assert.NotNull(r);
        Assert.Equal(123, r!.Mgdl);
        Assert.Equal(Trend.FortyFiveUp, r.Trend);
        Assert.Equal(1691455258000, r.Date.ToUnixTimeMilliseconds());
    }

    [Fact]
    public void ParsesNumericTrend() =>
        Assert.Equal(Trend.Flat, DexcomParser.ParseReading("""[{"WT":"Date(1691455258000)","Value":99,"Trend":4}]""")!.Trend);

    [Fact]
    public void EmptyReplyMeansNoReading() => Assert.Null(DexcomParser.ParseReading("[]"));

    [Theory]
    [InlineData("AccountPasswordInvalid", DexcomErrorKind.BadCredentials)]
    [InlineData("SSO_AuthenticateMaxAttemptsExceeded", DexcomErrorKind.LockedOut)]
    [InlineData("SessionIdNotFound", DexcomErrorKind.SessionExpired)]
    [InlineData("SomethingElse", DexcomErrorKind.Server)]
    public void ErrorCodes(string code, DexcomErrorKind kind) =>
        Assert.Equal(kind, DexcomParser.ErrorFrom($$"""{"Code":"{{code}}","Message":"x"}""", 500).Kind);

    [Fact]
    public void FindsAccountIdInPastedText()
    {
        const string id = "12345678-90ab-cdef-1234-567890abcdef";
        Assert.Equal(id, DexcomParser.AccountIdIn(id));
        Assert.Equal(id, DexcomParser.AccountIdIn("1234567890ABCDEF1234567890abcdef"));
        Assert.Equal(id, DexcomParser.AccountIdIn($"https://uam1.dexcom.com/account/{id}/profile"));
        Assert.Null(DexcomParser.AccountIdIn("someone@example.com"));
        Assert.Null(DexcomParser.AccountIdIn("+15551234567"));
    }

    [Fact]
    public void AccountIdOnlyFromProfilePage()
    {
        Assert.Equal("12345678-90ab-cdef-1234-567890abcdef",
            DexcomParser.AccountIdFromProfileUrl(new Uri("https://myaccount.dexcom.com/profile/12345678-90ab-cdef-1234-567890abcdef")));
        // The sign-in page carries the website's own client ID; that must not be taken as the account ID.
        Assert.Null(DexcomParser.AccountIdFromProfileUrl(new Uri("https://signup.dexcom.com/connect/authorize?client_id=0b72c581-2e98-4644-989c-52c76e34842b&redirect_uri=https://myaccount.dexcom.com/profile")));
        Assert.Null(DexcomParser.AccountIdFromProfileUrl(new Uri("https://evil-dexcom.com/profile/12345678-90ab-cdef-1234-567890abcdef")));
    }

    [Fact]
    public void DiscordFrameIsLittleEndianHeaderThenJson() =>
        Assert.Equal(new byte[] { 1, 0, 0, 0, 2, 0, 0, 0, 123, 125 }, DiscordFrame.Build(1, "{}"u8.ToArray()));

    [Fact]
    public void NumberModeActivity()
    {
        var now = DateTimeOffset.UtcNow;
        var a = Presence.Activity(new Reading(123, Trend.FortyFiveUp, now.AddMinutes(-2)), now, DisplayMode.Number, GlucoseUnit.Mgdl, StatusVerb.Watching, 70, 180);
        Assert.Equal(3, a["type"]);
        Assert.Equal("123 mg/dL ↗", a["details"]);
        Assert.Equal("Rising slowly", a["state"]);
        Assert.Equal("v2_up_45", ((Dictionary<string, string>)a["assets"])["large_image"]);
    }

    [Fact]
    public void DotModeNeverShowsTheNumber()
    {
        var now = DateTimeOffset.UtcNow;
        var a = Presence.Activity(new Reading(250, Trend.SingleUp, now), now, DisplayMode.Dot, GlucoseUnit.Mgdl, StatusVerb.Playing, 70, 180);
        Assert.Equal(0, a["type"]);
        Assert.Equal("High", a["details"]);
        Assert.Equal("v2_dot_yellow", ((Dictionary<string, string>)a["assets"])["large_image"]);
        Assert.DoesNotContain("250", System.Text.Json.JsonSerializer.Serialize(a));
        Assert.False(a.ContainsKey("state"));
    }

    [Fact]
    public void StaleReadingShowsNoReading()
    {
        var now = DateTimeOffset.UtcNow;
        var a = Presence.Activity(new Reading(110, Trend.Flat, now.AddMinutes(-16)), now, DisplayMode.Number, GlucoseUnit.Mgdl, StatusVerb.Watching, 70, 180);
        Assert.Equal("No reading", a["details"]);
        Assert.False(a.ContainsKey("timestamps"));
    }

    [Fact]
    public void Formatting()
    {
        Assert.Equal("10.0 mmol/L", Presence.Format(180, GlucoseUnit.Mmol));
        Assert.Equal("LOW", Presence.Format(39, GlucoseUnit.Mgdl));
        Assert.Equal("HIGH", Presence.Format(401, GlucoseUnit.Mmol));
        Assert.Equal(Band.Low, Presence.BandOf(69, 70, 180));
        Assert.Equal(Band.High, Presence.BandOf(181, 70, 180));
    }

    [Fact]
    public void SettingsSurviveARoundTrip()
    {
        var path = Path.Combine(Path.GetTempPath(), $"bgb-{Guid.NewGuid()}", "settings.json");
        new AppSettings { Mode = DisplayMode.Dot, Unit = GlucoseUnit.Mmol, Low = 80, Username = "x" }.Save(path);
        var s = AppSettings.Load(path);
        Assert.Equal((DisplayMode.Dot, GlucoseUnit.Mmol, 80, "x"), (s.Mode, s.Unit, s.Low, s.Username));
        Directory.Delete(Path.GetDirectoryName(path)!, true);
    }

    [Fact]
    public void DiscordChoiceIsUnsetInOldSettingsAndSavedOnceMade()
    {
        var path = Path.Combine(Path.GetTempPath(), $"bgb-{Guid.NewGuid()}", "settings.json");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, """{ "Username": "x", "Mode": "Dot" }""");  // a 1.0 file: no Discord field
        Assert.Null(AppSettings.Load(path).Discord);
        new AppSettings { Discord = false }.Save(path);
        Assert.False(AppSettings.Load(path).Discord);
        Directory.Delete(Path.GetDirectoryName(path)!, true);
    }
}
