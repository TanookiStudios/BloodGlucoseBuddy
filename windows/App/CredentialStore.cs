using System.Runtime.InteropServices;
using System.Text;

namespace BloodGlucoseBuddy;

/// <summary>The Dexcom password, kept in Windows Credential Manager (never in a file).</summary>
static class CredentialStore
{
    private const string Target = "BloodGlucoseBuddy/Dexcom";
    private const uint CredTypeGeneric = 1, CredPersistLocalMachine = 2;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Credential
    {
        public uint Flags;
        public uint Type;
        public string TargetName;
        public string? Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public string? TargetAlias;
        public string UserName;
    }

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "CredWriteW")]
    private static extern bool CredWrite(ref Credential credential, uint flags);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "CredReadW")]
    private static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);
    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "CredDeleteW")]
    private static extern bool CredDelete(string target, uint type, uint flags);
    [DllImport("advapi32.dll")]
    private static extern void CredFree(IntPtr buffer);

    public static bool Save(string username, string password)
    {
        var blob = Encoding.Unicode.GetBytes(password);
        var ptr = Marshal.AllocHGlobal(blob.Length);
        try
        {
            Marshal.Copy(blob, 0, ptr, blob.Length);
            var c = new Credential
            {
                Type = CredTypeGeneric, TargetName = Target, UserName = username,
                CredentialBlob = ptr, CredentialBlobSize = (uint)blob.Length, Persist = CredPersistLocalMachine,
            };
            return CredWrite(ref c, 0);
        }
        finally
        {
            Marshal.Copy(new byte[blob.Length], 0, ptr, blob.Length);
            Marshal.FreeHGlobal(ptr);
        }
    }

    public static string? Password()
    {
        if (!CredRead(Target, CredTypeGeneric, 0, out var ptr)) return null;
        try
        {
            var c = Marshal.PtrToStructure<Credential>(ptr);
            return c.CredentialBlobSize == 0 ? null : Marshal.PtrToStringUni(c.CredentialBlob, (int)c.CredentialBlobSize / 2);
        }
        finally { CredFree(ptr); }
    }

    public static void Delete() => CredDelete(Target, CredTypeGeneric, 0);
}
