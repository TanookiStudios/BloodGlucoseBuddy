using System.Globalization;

namespace BloodGlucoseBuddy.Core;

public enum DisplayMode { Number, Dot }
public enum GlucoseUnit { Mgdl, Mmol }
public enum StatusVerb { Watching, Playing }
public enum Band { Low, InRange, High }

public static class Labels
{
    public static string Label(this DisplayMode m) => m == DisplayMode.Number ? "Number" : "Colored dot only";
    public static string Label(this GlucoseUnit u) => u == GlucoseUnit.Mgdl ? "mg/dL" : "mmol/L";
    public static string Label(this StatusVerb v) => v == StatusVerb.Watching ? "Watching" : "Playing";
    public static int ActivityType(this StatusVerb v) => v == StatusVerb.Watching ? 3 : 0;
    public static string Word(this Band b) => b switch { Band.Low => "Low", Band.High => "High", _ => "In range" };
    public static string Asset(this Band b) => b switch { Band.Low => "dot_red", Band.High => "dot_yellow", _ => "dot_green" };
}

public static class Presence
{
    /// <summary>Older than this, show "No reading" rather than a number that isn't current.</summary>
    public static readonly TimeSpan StaleAfter = TimeSpan.FromMinutes(15);

    /// <summary>Just the number: "112", "6.2", "LOW" or "HIGH".</summary>
    public static string Value(int mgdl, GlucoseUnit unit)
    {
        if (mgdl <= 39) return "LOW";   // Dexcom reports anything under 40 as 39
        if (mgdl >= 401) return "HIGH"; // and anything over 400 as 401
        return unit == GlucoseUnit.Mgdl
            ? mgdl.ToString(CultureInfo.InvariantCulture)
            : (mgdl / 18.0182).ToString("0.0", CultureInfo.InvariantCulture);
    }

    public static string Format(int mgdl, GlucoseUnit unit)
    {
        var v = Value(mgdl, unit);
        return v is "LOW" or "HIGH" ? v : $"{v} {unit.Label()}";
    }

    public static Band BandOf(int mgdl, int low, int high) => mgdl < low ? Band.Low : mgdl > high ? Band.High : Band.InRange;

    public static bool IsFresh(Reading? r, DateTimeOffset now) => r is not null && now - r.Date <= StaleAfter;

    public static Dictionary<string, object> Activity(Reading? reading, DateTimeOffset now, DisplayMode mode, GlucoseUnit unit,
                                                      StatusVerb verb, int low, int high)
    {
        var activity = new Dictionary<string, object> { ["type"] = verb.ActivityType() };
        if (reading is null || !IsFresh(reading, now))
        {
            activity["details"] = "No reading";
            activity["assets"] = new Dictionary<string, string> { ["large_image"] = "dot_gray", ["large_text"] = "No recent reading" };
            return activity;
        }
        var band = BandOf(reading.Mgdl, low, high);
        if (mode == DisplayMode.Number)
        {
            activity["details"] = $"{Format(reading.Mgdl, unit)} {reading.Trend.Arrow()}".Trim();
            if (reading.Trend.Word() is { Length: > 0 } word) activity["state"] = word;
            activity["assets"] = new Dictionary<string, string> { ["large_image"] = reading.Trend.Asset() ?? band.Asset(), ["large_text"] = band.Word() };
        }
        else
        {
            activity["details"] = band.Word();
            activity["assets"] = new Dictionary<string, string> { ["large_image"] = band.Asset(), ["large_text"] = band.Word() };
        }
        // Discord shows this as "mm:ss elapsed", i.e. how old the reading is.
        activity["timestamps"] = new Dictionary<string, long> { ["start"] = reading.Date.ToUnixTimeMilliseconds() };
        return activity;
    }
}

public static class DiscordFrame
{
    /// <summary>Each Discord IPC message is: opcode (UInt32 LE), length (UInt32 LE), JSON.</summary>
    public static byte[] Build(uint opcode, byte[] payload)
    {
        var frame = new byte[8 + payload.Length];
        BitConverter.TryWriteBytes(frame.AsSpan(0, 4), opcode);
        BitConverter.TryWriteBytes(frame.AsSpan(4, 4), (uint)payload.Length);
        payload.CopyTo(frame, 8);
        if (!BitConverter.IsLittleEndian) { Array.Reverse(frame, 0, 4); Array.Reverse(frame, 4, 4); }
        return frame;
    }
}
