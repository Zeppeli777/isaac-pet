using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using IsaacPet.Windows.Core;

namespace IsaacPet.Windows.Platform;

/// <summary>
/// 使用 Windows DPAPI（CryptProtectData，CurrentUser 范围）保存凭据，
/// 对应 macOS 版的 Keychain 存储。密文落盘在应用数据目录下。
/// </summary>
public sealed class DpapiCredentialStore
{
    private readonly string _filePath;

    public DpapiCredentialStore(string fileName)
    {
        _filePath = Path.Combine(AppPaths.DataDirectory, fileName);
    }

    public string? Load()
    {
        if (!File.Exists(_filePath)) return null;
        var blob = File.ReadAllBytes(_filePath);
        if (blob.Length == 0) return null;
        try
        {
            var plain = Unprotect(blob);
            return Encoding.UTF8.GetString(plain);
        }
        catch (Exception)
        {
            // 机器/用户迁移后密文不可解，按未配置处理。
            return null;
        }
    }

    public void Save(string value)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_filePath)!);
        File.WriteAllBytes(_filePath, Protect(Encoding.UTF8.GetBytes(value)));
    }

    public void Delete()
    {
        if (File.Exists(_filePath)) File.Delete(_filePath);
    }

    private static byte[] Protect(byte[] data) => Crypt32.CryptProtect(data);

    private static byte[] Unprotect(byte[] data) => Crypt32.CryptUnprotect(data);

    private static class Crypt32
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct DATA_BLOB
        {
            public int cbData;
            public IntPtr pbData;
        }

        [DllImport("crypt32.dll", SetLastError = true)]
        private static extern bool CryptProtectData(
            ref DATA_BLOB pDataIn,
            IntPtr szDataDescr,
            IntPtr pOptionalEntropy,
            IntPtr pvReserved,
            IntPtr pPromptStruct,
            int dwFlags,
            out DATA_BLOB pDataOut);

        [DllImport("crypt32.dll", SetLastError = true)]
        private static extern bool CryptUnprotectData(
            ref DATA_BLOB pDataIn,
            IntPtr ppszDataDescr,
            IntPtr pOptionalEntropy,
            IntPtr pvReserved,
            IntPtr pPromptStruct,
            int dwFlags,
            out DATA_BLOB pDataOut);

        [DllImport("kernel32.dll")]
        private static extern IntPtr LocalFree(IntPtr hMem);

        private const int CryptProtectUiForbidden = 0x1;

        public static byte[] CryptProtect(byte[] data) => Run(data, protect: true);

        public static byte[] CryptUnprotect(byte[] data) => Run(data, protect: false);

        private static byte[] Run(byte[] data, bool protect)
        {
            var input = new DATA_BLOB { cbData = data.Length, pbData = Marshal.AllocHGlobal(data.Length) };
            try
            {
                Marshal.Copy(data, 0, input.pbData, data.Length);
                var ok = protect
                    ? CryptProtectData(ref input, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, CryptProtectUiForbidden, out var output)
                    : CryptUnprotectData(ref input, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, CryptProtectUiForbidden, out output);
                if (!ok) throw new InvalidOperationException($"DPAPI 调用失败（错误 {Marshal.GetLastWin32Error()}）。");
                try
                {
                    var result = new byte[output.cbData];
                    Marshal.Copy(output.pbData, result, 0, output.cbData);
                    return result;
                }
                finally
                {
                    LocalFree(output.pbData);
                }
            }
            finally
            {
                Marshal.FreeHGlobal(input.pbData);
            }
        }
    }
}
