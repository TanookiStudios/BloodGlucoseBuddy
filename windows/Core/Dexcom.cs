using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace BloodGlucoseBuddy.Core;

public enum DexcomRegion { US, OutsideUS, Japan }

public static class DexcomRegions
{
    public static string Label(this DexcomRegion r) => r switch
    {
        DexcomRegion.US => "United States",
        DexcomRegion.OutsideUS => "Outside the US",
        _ => "Japan",
    };

    public static Uri BaseUri(this DexcomRegion r) => new(r switch
    {
        DexcomRegion.US => "https://share2.dexcom.com/ShareWebServices/Services/",
        DexcomRegion.OutsideUS => "https://shareous1.dexcom.com/ShareWebServices/Services/",
        _ => "https://share.dexcom.jp/ShareWebServices/Services/",
    });

    // Public Share application IDs, the same ones Dexcom's own apps send.
    public static string ApplicationId(this DexcomRegion r) =>
        r == DexcomRegion.Japan ? "d8665ade-9673-4e27-9ff6-92db4ce13d13" : "d89443d2-327c-4a6f-89e5-496bbb0317db";

    /// <summary>Dexcom's account website. After sign-in it lands on /profile/&lt;account ID&gt;.</summary>
    public static Uri? AccountSite(this DexcomRegion r) => r switch
    {
        DexcomRegion.US => new Uri("https://uam1.dexcom.com/"),
        DexcomRegion.OutsideUS => new Uri("https://uam2.dexcom.com/"),
        _ => null,
    };
}

// Order matters: older Share replies send the trend as this number.
public enum Trend { None, DoubleUp, SingleUp, FortyFiveUp, Flat, FortyFiveDown, SingleDown, DoubleDown, NotComputable, RateOutOfRange }

public static class Trends
{
    public static string Arrow(this Trend t) => t switch
    {
        Trend.DoubleUp => "⇈", Trend.SingleUp => "↑", Trend.FortyFiveUp => "↗", Trend.Flat => "→",
        Trend.FortyFiveDown => "↘", Trend.SingleDown => "↓", Trend.DoubleDown => "⇊", _ => "",
    };

    public static string Word(this Trend t) => t switch
    {
        Trend.DoubleUp => "Rising fast", Trend.SingleUp => "Rising", Trend.FortyFiveUp => "Rising slowly",
        Trend.Flat => "Steady", Trend.FortyFiveDown => "Falling slowly", Trend.SingleDown => "Falling",
        Trend.DoubleDown => "Falling fast", _ => "",
    };

    /// <summary>Discord art asset key, uploaded to the "Blood Glucose" application.</summary>
    public static string? Asset(this Trend t) => t switch
    {
        Trend.DoubleUp => "double_up", Trend.SingleUp => "up", Trend.FortyFiveUp => "up_45", Trend.Flat => "flat",
        Trend.FortyFiveDown => "down_45", Trend.SingleDown => "down", Trend.DoubleDown => "double_down", _ => null,
    };
}

public sealed record Reading(int Mgdl, Trend Trend, DateTimeOffset Date);

public enum DexcomErrorKind { BadCredentials, LockedOut, SessionExpired, Server }

public sealed class DexcomException(DexcomErrorKind kind, string message) : Exception(message)
{
    public DexcomErrorKind Kind { get; } = kind;

    public static DexcomException Of(DexcomErrorKind kind, string? serverMessage = null) => new(kind, kind switch
    {
        DexcomErrorKind.BadCredentials => "Dexcom didn't accept that username and password.",
        DexcomErrorKind.LockedOut => "Dexcom has locked the account after too many tries. Wait a while, then sign in again.",
        DexcomErrorKind.SessionExpired => "Dexcom session expired.",
        _ => serverMessage ?? "Dexcom returned an error.",
    });
}

public static partial class DexcomParser
{
    public static Reading? ParseReading(string json)
    {
        using var doc = JsonDocument.Parse(json);
        if (doc.RootElement.ValueKind != JsonValueKind.Array) throw DexcomException.Of(DexcomErrorKind.Server, "Unexpected reply from Dexcom.");
        if (doc.RootElement.GetArrayLength() == 0) return null;
        var row = doc.RootElement[0];
        if (!row.TryGetProperty("Value", out var value) || !value.TryGetInt32(out var mgdl) ||
            !row.TryGetProperty("WT", out var wt) || DateFromDexcom(wt.GetString()) is not { } date)
            throw DexcomException.Of(DexcomErrorKind.Server, "Unexpected reading format from Dexcom.");
        var trend = Trend.None;
        if (row.TryGetProperty("Trend", out var t))
        {
            if (t.ValueKind == JsonValueKind.String && Enum.TryParse<Trend>(t.GetString(), out var named)) trend = named;
            else if (t.ValueKind == JsonValueKind.Number && t.TryGetInt32(out var n) && Enum.IsDefined((Trend)n)) trend = (Trend)n;
        }
        return new Reading(mgdl, trend, date);
    }

    /// <summary>"Date(1691455258000-0400)": the number is UTC milliseconds; the offset is informational.</summary>
    public static DateTimeOffset? DateFromDexcom(string? s)
    {
        var m = s is null ? null : DexcomDate().Match(s);
        return m is { Success: true } && long.TryParse(m.Groups[1].Value, out var ms) ? DateTimeOffset.FromUnixTimeMilliseconds(ms) : null;
    }

    public static DexcomException ErrorFrom(string body, int status)
    {
        string code = "", message = $"Dexcom returned an error (HTTP {status}).";
        try
        {
            using var doc = JsonDocument.Parse(body);
            if (doc.RootElement.TryGetProperty("Code", out var c)) code = c.GetString() ?? "";
            if (doc.RootElement.TryGetProperty("Message", out var msg)) message = msg.GetString() ?? message;
        }
        catch (JsonException) { }
        if (code.StartsWith("Session")) return DexcomException.Of(DexcomErrorKind.SessionExpired);
        if (code.Contains("MaxAttempts")) return DexcomException.Of(DexcomErrorKind.LockedOut);
        if (code.Contains("PasswordInvalid") || code == "InvalidArgument" || code.Contains("AccountNotFound"))
            return DexcomException.Of(DexcomErrorKind.BadCredentials);
        return DexcomException.Of(DexcomErrorKind.Server, message);
    }

    /// <summary>Finds a Dexcom account ID anywhere in pasted text (a bare ID, one without hyphens, or a whole web address).</summary>
    public static string? AccountIdIn(string text)
    {
        var dashed = DashedId().Match(text);
        if (dashed.Success) return dashed.Value.ToLowerInvariant();
        var plain = PlainId().Match(text);
        if (!plain.Success) return null;
        var s = plain.Value.ToLowerInvariant();
        return $"{s[..8]}-{s[8..12]}-{s[12..16]}-{s[16..20]}-{s[20..]}";
    }

    /// <summary>The account ID from Dexcom's profile page address, and only from there: the sign-in pages
    /// carry other IDs (like the website's own client ID) that must not be mistaken for it.</summary>
    public static string? AccountIdFromProfileUrl(Uri? url)
    {
        if (url is null || !(url.Host == "dexcom.com" || url.Host.EndsWith(".dexcom.com")) || !url.AbsolutePath.StartsWith("/profile/")) return null;
        return AccountIdIn(url.AbsolutePath);
    }

    [GeneratedRegex(@"Date\((\d+)")] private static partial Regex DexcomDate();
    [GeneratedRegex("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")] private static partial Regex DashedId();
    [GeneratedRegex("(?<![0-9a-fA-F])[0-9a-fA-F]{32}(?![0-9a-fA-F])")] private static partial Regex PlainId();
}

public sealed class DexcomClient
{
    private const string NullId = "00000000-0000-0000-0000-000000000000";
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(20) };
    private string? sessionId;

    public void Reset() => sessionId = null;

    public async Task<Reading?> LatestReadingAsync(string username, string password, DexcomRegion region)
    {
        sessionId ??= await LoginAsync(username, password, region);
        try
        {
            return await FetchLatestAsync(region);
        }
        catch (DexcomException e) when (e.Kind == DexcomErrorKind.SessionExpired)
        {
            sessionId = await LoginAsync(username, password, region);
            return await FetchLatestAsync(region);
        }
    }

    private async Task<string> LoginAsync(string username, string password, DexcomRegion region)
    {
        var accountId = DexcomParser.AccountIdIn(username)  // user pasted their Account ID (or the page address containing it)
            ?? await PostStringAsync("General/AuthenticatePublisherAccount", region, new()
            {
                ["accountName"] = username, ["password"] = password, ["applicationId"] = region.ApplicationId(),
            });
        var session = await PostStringAsync("General/LoginPublisherAccountById", region, new()
        {
            ["accountId"] = accountId, ["password"] = password, ["applicationId"] = region.ApplicationId(),
        });
        if (session == NullId) throw DexcomException.Of(DexcomErrorKind.BadCredentials);
        return session;
    }

    private async Task<Reading?> FetchLatestAsync(DexcomRegion region)
    {
        if (sessionId is null) throw DexcomException.Of(DexcomErrorKind.SessionExpired);
        var body = await PostAsync($"Publisher/ReadPublisherLatestGlucoseValues?sessionId={Uri.EscapeDataString(sessionId)}&minutes=1440&maxCount=1",
            region, new());
        return DexcomParser.ParseReading(body);
    }

    private async Task<string> PostStringAsync(string path, DexcomRegion region, Dictionary<string, string> body)
    {
        var json = await PostAsync(path, region, body);
        return JsonSerializer.Deserialize<string>(json) ?? throw DexcomException.Of(DexcomErrorKind.Server, "Unexpected reply from Dexcom.");
    }

    private static async Task<string> PostAsync(string path, DexcomRegion region, Dictionary<string, string> body)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(region.BaseUri(), path))
        {
            Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json"),
        };
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        using var response = await Http.SendAsync(request);
        var text = await response.Content.ReadAsStringAsync();
        if (!response.IsSuccessStatusCode) throw DexcomParser.ErrorFrom(text, (int)response.StatusCode);
        return text;
    }
}
