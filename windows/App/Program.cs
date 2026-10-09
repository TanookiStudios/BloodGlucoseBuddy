namespace BloodGlucoseBuddy;

static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        // Harness modes, used by the GitHub Actions build on a throwaway Windows machine.
        if (args is ["--self-test", var testDir]) { ApplicationConfiguration.Initialize(); return Harness.SelfTest(testDir); }
        if (args is ["--screenshots", var shotDir]) { ApplicationConfiguration.Initialize(); return Harness.Screenshots(shotDir); }

        // One copy at a time: a second launch just exits.
        using var mutex = new Mutex(true, @"Local\TanookiStudios.BloodGlucoseBuddy", out var first);
        if (!first) return 0;
        ApplicationConfiguration.Initialize();
        Application.Run(new TrayApp());
        return 0;
    }
}
