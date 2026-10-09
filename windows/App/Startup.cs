using Microsoft.Win32;

namespace BloodGlucoseBuddy;

/// <summary>"Start with Windows", via the per-user Run key. No admin rights needed.</summary>
static class Startup
{
    private const string Key = @"Software\Microsoft\Windows\CurrentVersion\Run";
    /// <summary>Changeable only so the self-test can use its own entry.</summary>
    public static string Name { get; set; } = "Blood Glucose Buddy";
    private static string Command => $"\"{Environment.ProcessPath}\"";

    public static bool Enabled
    {
        get { using var k = Registry.CurrentUser.OpenSubKey(Key); return k?.GetValue(Name) is string; }
        set
        {
            using var k = Registry.CurrentUser.CreateSubKey(Key);
            if (value) k.SetValue(Name, Command); else k.DeleteValue(Name, false);
        }
    }

    /// <summary>If the .exe was moved since it was turned on, point Windows at where it is now.</summary>
    public static void RefreshPath()
    {
        if (Enabled) Enabled = true;
    }
}
