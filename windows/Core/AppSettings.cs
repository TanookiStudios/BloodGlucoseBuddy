using System.Text.Json;
using System.Text.Json.Serialization;

namespace BloodGlucoseBuddy.Core;

public sealed class AppSettings
{
    public DisplayMode Mode { get; set; } = DisplayMode.Number;
    public GlucoseUnit Unit { get; set; } = GlucoseUnit.Mgdl;
    public StatusVerb Verb { get; set; } = StatusVerb.Watching;
    public int Low { get; set; } = 70;
    public int High { get; set; } = 180;
    public DexcomRegion Region { get; set; } = DexcomRegion.US;
    public string Username { get; set; } = "";
    public bool StartupSetUp { get; set; }

    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true, Converters = { new JsonStringEnumConverter() } };

    public static AppSettings Load(string path)
    {
        try { return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(path), Options) ?? new(); }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return new(); }
    }

    public void Save(string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temp = path + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(this, Options));
        File.Move(temp, path, overwrite: true);  // never leave a half-written settings file
    }
}
