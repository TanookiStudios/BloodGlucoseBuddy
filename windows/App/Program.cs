namespace BloodGlucoseBuddy;

static class Program
{
    [STAThread]
    static void Main()
    {
        // One copy at a time: a second launch just exits.
        using var mutex = new Mutex(true, @"Local\TanookiStudios.BloodGlucoseBuddy", out var first);
        if (!first) return;
        ApplicationConfiguration.Initialize();
        Application.Run(new TrayApp());
    }
}
