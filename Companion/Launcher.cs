using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Threading;
using System.Windows.Forms;

internal static class CompanionLauncher {
    private const string Setup = "http://127.0.0.1:48680/";
    private static bool Ready() {
        try {
            var request = (HttpWebRequest)WebRequest.Create(Setup);
            request.Timeout = 600; request.AllowAutoRedirect = false; request.Proxy = null;
            using (var response = request.GetResponse())
            using (var reader = new StreamReader(response.GetResponseStream())) {
                return reader.ReadToEnd().Contains("Personal Assistant · Computer");
            }
        } catch { return false; }
    }
    [STAThread] private static void Main(string[] args) {
        bool check = Array.IndexOf(args, "--check") >= 0;
        try {
            string root = AppDomain.CurrentDomain.BaseDirectory;
            if (!Ready()) {
                string node = Path.Combine(root, "Runtime", "node.exe");
                if (!File.Exists(node)) throw new Exception("The companion package is incomplete. Keep the Runtime folder beside this application.");
                if (!File.Exists(@"C:\Program Files\Git\usr\bin\openssl.exe")) throw new Exception("This computer needs Git for Windows (including OpenSSL) to create its private pairing certificate.");
                var start = new ProcessStartInfo(node, "src/server.mjs --no-open") {
                    WorkingDirectory = root, UseShellExecute = false, CreateNoWindow = true
                };
                var process = Process.Start(start);
                string logs = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PersonalAssistantCompanion", "logs");
                Directory.CreateDirectory(logs);
                string log = Path.Combine(logs, "startup.log");
                for (int attempt = 0; attempt < 80 && !Ready(); attempt++) {
                    if (process.HasExited) throw new Exception("The companion could not start. Its startup report is in " + log);
                    Thread.Sleep(250);
                }
                if (!Ready()) throw new Exception("The setup page has not become ready. Open the startup report in " + logs);
            }
            if (!check) Process.Start(new ProcessStartInfo(Setup) { UseShellExecute = true });
            Environment.ExitCode = 0;
        } catch (Exception error) {
            Environment.ExitCode = 1;
            if (!check) MessageBox.Show(error.Message, "Personal Assistant Computer", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
    }
}
