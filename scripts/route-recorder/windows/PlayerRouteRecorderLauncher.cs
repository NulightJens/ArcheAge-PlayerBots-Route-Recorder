using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("ArcheAge Standalone Route Recorder")]
[assembly: AssemblyDescription("Launches the local, privacy-preserving PlayerBots route recorder.")]
[assembly: AssemblyCompany("ArcheAge PlayerBots")]
[assembly: AssemblyProduct("Player Route Recorder")]
[assembly: AssemblyCopyright("GPL-3.0-or-later")]
[assembly: AssemblyVersion("1.6.0.0")]
[assembly: AssemblyFileVersion("1.6.0.0")]

namespace PlayerBots.RouteRecorder
{
    internal static class PlayerRouteRecorderLauncher
    {
        [STAThread]
        private static int Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            bool validateOnly = HasArgument(args, "--validate-only");
            string logPath = null;
            StringBuilder diagnostics = new StringBuilder();
            string scriptPath = FindRecorderScript(AppDomain.CurrentDomain.BaseDirectory);
            if (scriptPath == null)
            {
                if (!validateOnly)
                {
                    MessageBox.Show(
                        "Start-PlayerRouteRecorder.ps1 was not found beside the application. " +
                        "Extract the complete standalone recorder ZIP before launching, " +
                        "then read START-HERE.html in the extracted folder.",
                        "Player Route Recorder",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                }
                return 2;
            }

            string powershell = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                @"WindowsPowerShell\v1.0\powershell.exe");
            if (!File.Exists(powershell))
            {
                powershell = "powershell.exe";
            }

            string arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File \"" + scriptPath + "\"";
            arguments += " -LauncherPath \"" + Application.ExecutablePath + "\"";
            if (validateOnly)
            {
                arguments += " -ValidateOnly";
                foreach (string argument in args)
                {
                    if (argument.StartsWith("--screenshot=", StringComparison.OrdinalIgnoreCase))
                    {
                        string path = argument.Substring(13);
                        if (path.IndexOf('"') >= 0) return 2;
                        arguments += " -ScreenshotPath \"" + path + "\"";
                    }
                }
            }

            try
            {
                string logRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "ArcheAge Route Recorder", "logs");
                Directory.CreateDirectory(logRoot);
                logPath = Path.Combine(logRoot, "launch-" + DateTime.UtcNow.ToString("yyyyMMdd-HHmmss") +
                    "-" + Guid.NewGuid().ToString("N").Substring(0, 8) + ".log");
                ProcessStartInfo startInfo = new ProcessStartInfo();
                startInfo.FileName = powershell;
                startInfo.Arguments = arguments;
                startInfo.WorkingDirectory = Path.GetDirectoryName(scriptPath);
                startInfo.UseShellExecute = false;
                startInfo.CreateNoWindow = true;
                startInfo.WindowStyle = ProcessWindowStyle.Hidden;
                startInfo.RedirectStandardError = true;
                startInfo.RedirectStandardOutput = true;

                using (Process process = Process.Start(startInfo))
                {
                    if (process == null)
                    {
                        throw new InvalidOperationException("Windows PowerShell did not start.");
                    }
                    process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs e)
                    {
                        if (e.Data != null) lock (diagnostics) { diagnostics.AppendLine(e.Data); }
                    };
                    process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs e)
                    {
                        if (e.Data != null) lock (diagnostics) { diagnostics.AppendLine(e.Data); }
                    };
                    process.BeginOutputReadLine();
                    process.BeginErrorReadLine();
                    // Keep the launcher alive: a hidden PowerShell failure must never look like success.
                    process.WaitForExit();
                    File.WriteAllText(logPath, "Exit code: " + process.ExitCode + Environment.NewLine + diagnostics);
                    if (process.ExitCode != 0 && !validateOnly)
                    {
                        MessageBox.Show("The recorder could not open. Extract the entire ZIP to a normal folder, " +
                            "then open PlayerRouteRecorder.exe.\r\n\r\nDetails were saved to:\r\n" + logPath +
                            "\r\n\r\nOpen START-HERE.html for setup help.", "Recorder startup failed",
                            MessageBoxButtons.OK, MessageBoxIcon.Error);
                    }
                    return process.ExitCode;
                }
            }
            catch (Exception exception)
            {
                if (!validateOnly)
                {
                    MessageBox.Show(
                        "The recorder could not start.\r\n\r\n" + exception.Message +
                        "\r\n\r\nExtract the complete ZIP and read START-HERE.html.",
                        "Player Route Recorder",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error);
                }
                return 3;
            }
        }

        private static bool HasArgument(string[] args, string expected)
        {
            foreach (string argument in args)
            {
                if (string.Equals(argument, expected, StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
            }
            return false;
        }

        private static string FindRecorderScript(string executableDirectory)
        {
            string besideExecutable = Path.Combine(executableDirectory, "Start-PlayerRouteRecorder.ps1");
            if (File.Exists(besideExecutable))
            {
                return besideExecutable;
            }

            string packagedLayout = Path.Combine(
                executableDirectory,
                "scripts",
                "route-recorder",
                "Start-PlayerRouteRecorder.ps1");
            if (File.Exists(packagedLayout))
            {
                return packagedLayout;
            }

            DirectoryInfo parent = Directory.GetParent(executableDirectory.TrimEnd(Path.DirectorySeparatorChar));
            if (parent != null)
            {
                string developmentLayout = Path.Combine(parent.FullName, "Start-PlayerRouteRecorder.ps1");
                if (File.Exists(developmentLayout))
                {
                    return developmentLayout;
                }
            }
            return null;
        }
    }
}
