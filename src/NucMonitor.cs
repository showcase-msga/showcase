// ============================================================
// Showcase NUC Monitor - NucMonitor.exe source (v2.0-beta)
//
// Build (no SDK needed, uses the .NET Framework compiler on every Windows PC):
//   build.bat
//
// Usage:
//   NucMonitor.exe <webhookUrl> <nucName>        capture, annotate, upload
//   NucMonitor.exe --dry-run <outFile.jpg> <nucName>   capture and annotate only, no upload
//
// v2.0 changes:
//   - DPI aware: captures every screen at its real resolution. v1.x read the scaled
//     bounds (1920x1080 on a 4K screen at 200%) and captured only the top-left quarter.
//   - Stats panel beside the screenshot: uptime, CPU, RAM, disk, network, displays,
//     Chrome, and every open window (foreground marked).
//   - Stats also sent as JSON fields ("version", "stats"); the payload keeps
//     nuc_name / timestamp / screenshot so the existing Apps Script is unchanged.
//   - If the screen can't be captured (locked, no desktop), still uploads the panel.
// ============================================================
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("Showcase NUC Monitor")]
[assembly: AssemblyProduct("Showcase NUC Monitor")]
[assembly: AssemblyVersion("2.0.0.0")]
[assembly: AssemblyFileVersion("2.0.0.0")]
[assembly: AssemblyInformationalVersion("2.0-beta")]

static class NucMonitor
{
    const string Version = "2.0-beta";
    static string LogFile = @"C:\ProgramData\showcase-monitor\monitor.log";
    const long MaxLogBytes = 500 * 1024;
    const int MaxShotWidth = 1920, MaxShotHeight = 1080;   // the screen area of the upload
    const int PanelWidth = 560;
    const long JpegQuality = 60;

    // ---------------------------------------------------------------- entry
    [STAThread]
    static int Main(string[] args)
    {
        MakeDpiAware();   // must run before anything touches Screen or Graphics
        bool dryRun = args.Length >= 1 && args[0] == "--dry-run";
        if (args.Length < 2 || (dryRun && args.Length < 3))
        {
            Log("ERROR", "Missing args. Usage: NucMonitor.exe <webhookUrl> <nucName>  |  --dry-run <out.jpg> <nucName>");
            return 1;
        }
        string target = dryRun ? args[1] : args[0];
        if (dryRun) LogFile = Path.ChangeExtension(Path.GetFullPath(target), ".log");   // never touch the real log when testing
        string nucName = dryRun ? args[2] : args[1];
        Log("INFO", "Run started | NUC: " + nucName + " | v" + Version + (dryRun ? " | DRY RUN" : ""));

        try
        {
            var stats = Stats.Collect();
            Bitmap shot = null;
            string captureError = null;
            try { shot = CaptureAllScreens(); }
            catch (Exception ex) { captureError = ex.Message; Log("ERROR", "Screen capture failed: " + ex.Message); }
            stats.Add("capture", captureError == null ? "ok" : "failed: " + captureError);

            using (var final = Compose(shot, stats, nucName, captureError))
            {
                if (shot != null) shot.Dispose();
                byte[] jpeg = EncodeJpeg(final, JpegQuality);
                Log("INFO", "Encoded JPEG | " + final.Width + "x" + final.Height + " | Size: " + (jpeg.Length / 1024) + " KB");

                if (dryRun)
                {
                    File.WriteAllBytes(target, jpeg);
                    File.WriteAllText(Path.ChangeExtension(target, ".json"), stats.ToJson(), Encoding.UTF8);
                    Log("INFO", "Dry run saved to " + target);
                    return 0;
                }

                string payload = "{\"nuc_name\":\"" + Json.Esc(nucName) +
                                 "\",\"timestamp\":\"" + DateTime.Now.ToString("yyyy-MM-dd HH-mm") +
                                 "\",\"version\":\"" + Version +
                                 "\",\"stats\":" + stats.ToJson() +
                                 ",\"screenshot\":\"" + Convert.ToBase64String(jpeg) + "\"}";
                Log("INFO", "Posting to webhook | Payload: " + (payload.Length / 1024) + " KB");
                Post(target, payload);
            }
            Log("INFO", "Run completed successfully");
            return 0;
        }
        catch (Exception ex)
        {
            Log("ERROR", "Run failed: " + ex.GetType().Name + ": " + ex.Message);
            return 2;
        }
    }

    // ---------------------------------------------------------------- DPI
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("shcore.dll")] static extern int SetProcessDpiAwareness(int value);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();

    static void MakeDpiAware()
    {
        try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return; } catch { }   // per-monitor v2 (Win10 1703+)
        try { if (SetProcessDpiAwareness(2) == 0) return; } catch { }                 // per-monitor (Win8.1+)
        try { SetProcessDPIAware(); } catch { }                                        // system aware
    }

    // ---------------------------------------------------------------- capture
    static Bitmap CaptureAllScreens()
    {
        Rectangle all = SystemInformation.VirtualScreen;   // physical pixels once DPI aware
        foreach (var s in Screen.AllScreens)
            Log("INFO", "Screen " + s.DeviceName + " | " + s.Bounds.Width + "x" + s.Bounds.Height + " at " + s.Bounds.X + "," + s.Bounds.Y + (s.Primary ? " | primary" : ""));
        var bmp = new Bitmap(all.Width, all.Height, PixelFormat.Format24bppRgb);
        using (var g = Graphics.FromImage(bmp))
            g.CopyFromScreen(all.X, all.Y, 0, 0, all.Size, CopyPixelOperation.SourceCopy);
        Log("INFO", "Screenshot captured | " + all.Width + "x" + all.Height);
        return bmp;
    }

    // ---------------------------------------------------------------- compose
    static Bitmap Compose(Bitmap shot, Stats stats, string nucName, string captureError)
    {
        int sw = MaxShotWidth, sh = MaxShotHeight;
        if (shot != null)
        {
            double scale = Math.Min(1.0, Math.Min((double)MaxShotWidth / shot.Width, (double)MaxShotHeight / shot.Height));
            sw = Math.Max(1, (int)Math.Round(shot.Width * scale));
            sh = Math.Max(1, (int)Math.Round(shot.Height * scale));
        }
        int height = Math.Max(sh, 720);
        var canvas = new Bitmap(sw + PanelWidth, height, PixelFormat.Format24bppRgb);
        using (var g = Graphics.FromImage(canvas))
        {
            g.Clear(Color.FromArgb(18, 18, 20));
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.SmoothingMode = SmoothingMode.HighQuality;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            if (shot != null) g.DrawImage(shot, new Rectangle(0, 0, sw, sh));
            else using (var f = new Font("Segoe UI", 22f, FontStyle.Bold, GraphicsUnit.Pixel))
                g.DrawString("Screen capture failed\n" + captureError, f, Brushes.OrangeRed, new RectangleF(40, 40, sw - 80, sh - 80));
            if (shot != null) Log("INFO", "Resized to: " + sw + "x" + sh);
            Panel.Draw(g, new Rectangle(sw, 0, PanelWidth, height), stats, nucName, Version);
        }
        return canvas;
    }

    static byte[] EncodeJpeg(Bitmap bmp, long quality)
    {
        var codec = ImageCodecInfo.GetImageEncoders().First(c => c.MimeType == "image/jpeg");
        using (var p = new EncoderParameters(1))
        using (var ms = new MemoryStream())
        {
            p.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, quality);
            bmp.Save(ms, codec, p);
            return ms.ToArray();
        }
    }

    // ---------------------------------------------------------------- upload
    static void Post(string url, string payload)
    {
        ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;   // TLS 1.2
        var req = (HttpWebRequest)WebRequest.Create(url);
        req.Method = "POST";
        req.ContentType = "application/json";
        req.Timeout = 120000;
        req.AllowAutoRedirect = true;
        byte[] body = Encoding.UTF8.GetBytes(payload);
        req.ContentLength = body.Length;
        using (var s = req.GetRequestStream()) s.Write(body, 0, body.Length);
        try
        {
            using (var resp = (HttpWebResponse)req.GetResponse())
                Log("INFO", "Webhook response: " + (int)resp.StatusCode + " " + resp.StatusCode);
        }
        catch (WebException ex)
        {
            var r = ex.Response as HttpWebResponse;
            Log("ERROR", "Webhook failed: " + ex.Message + (r != null ? " | Response: " + (int)r.StatusCode : ""));
            throw;
        }
    }

    // ---------------------------------------------------------------- log
    internal static void Log(string level, string msg)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(LogFile));
            var fi = new FileInfo(LogFile);
            if (fi.Exists && fi.Length > MaxLogBytes)
            {
                string archive = Path.Combine(fi.DirectoryName, "monitor-archive.log");
                if (File.Exists(archive)) File.Delete(archive);
                File.Move(LogFile, archive);
            }
            File.AppendAllText(LogFile, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " | " + level + " | " + msg + Environment.NewLine);
        }
        catch { }
    }
}

// ==================================================================== stats
class Stats
{
    // Ordered key/value pairs, grouped by section, so the panel and the JSON read the same way.
    public readonly List<KeyValuePair<string, string>> Items = new List<KeyValuePair<string, string>>();
    public readonly List<string> Warnings = new List<string>();
    public readonly List<WindowInfo> Windows = new List<WindowInfo>();

    public void Add(string key, string value) { Items.Add(new KeyValuePair<string, string>(key, value ?? "")); }
    public string Get(string key) { foreach (var kv in Items) if (kv.Key == key) return kv.Value; return ""; }

    public static Stats Collect()
    {
        var s = new Stats();
        Safe(s, "computer", () => Environment.MachineName);
        Safe(s, "windows", WindowsVersion);
        Safe(s, "uptime", () => { var up = TimeSpan.FromMilliseconds(Native.GetTickCount64()); if (up.TotalDays > 14) s.Warnings.Add("Up " + (int)up.TotalDays + " days without a restart"); return Fmt(up); });
        Safe(s, "cpu", () => { int c = CpuPercent(); if (c >= 90) s.Warnings.Add("CPU at " + c + "%"); return c + "%"; });
        Safe(s, "ram", () =>
        {
            var m = new Native.MEMORYSTATUSEX(); m.dwLength = (uint)Marshal.SizeOf(m); Native.GlobalMemoryStatusEx(ref m);
            double used = (m.ullTotalPhys - m.ullAvailPhys) / 1073741824.0, total = m.ullTotalPhys / 1073741824.0;
            if (m.dwMemoryLoad >= 90) s.Warnings.Add("RAM at " + m.dwMemoryLoad + "%");
            return m.dwMemoryLoad + "% (" + used.ToString("0.0") + " of " + total.ToString("0.0") + " GB)";
        });
        Safe(s, "disk_c", () =>
        {
            var d = new DriveInfo("C");
            double free = d.AvailableFreeSpace / 1073741824.0, total = d.TotalSize / 1073741824.0;
            if (free / total < 0.10) s.Warnings.Add("Disk C: only " + free.ToString("0.0") + " GB free");
            return free.ToString("0.0") + " GB free of " + total.ToString("0") + " GB";
        });
        Safe(s, "network", () => Network(s));
        Safe(s, "wifi", WifiSummary);
        Safe(s, "displays", () => Displays(s));
        Safe(s, "chrome", () =>
        {
            var ps = Process.GetProcessesByName("chrome");
            if (ps.Length == 0) { s.Warnings.Add("Chrome is not running"); return "not running"; }
            long ws = 0; foreach (var p in ps) { try { ws += p.WorkingSet64; } catch { } }
            return ps.Length + " processes, " + (ws / 1048576) + " MB";
        });
        Safe(s, "foreground", () =>
        {
            var w = WindowInfo.Foreground();
            if (w == null) return "none";
            if (!w.Process.Equals("chrome", StringComparison.OrdinalIgnoreCase) && !w.Process.Equals("msedge", StringComparison.OrdinalIgnoreCase))
                s.Warnings.Add("Foreground is " + w.Process + ": " + Trim(w.Title, 40));
            return w.Process + ": " + w.Title;
        });
        try { s.Windows.AddRange(WindowInfo.All()); } catch { }
        return s;
    }

    static void Safe(Stats s, string key, Func<string> f)
    {
        try { s.Add(key, f()); } catch (Exception ex) { s.Add(key, "n/a (" + ex.GetType().Name + ")"); }
    }

    static string WindowsVersion()
    {
        using (var k = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion"))
        {
            string name = (string)k.GetValue("ProductName", "Windows"), disp = (string)k.GetValue("DisplayVersion", "");
            string build = (string)k.GetValue("CurrentBuild", "");
            // ProductName still says Windows 10 on Windows 11; the build number settles it.
            int b; if (int.TryParse(build, out b) && b >= 22000) name = name.Replace("Windows 10", "Windows 11");
            return name + (disp != "" ? " " + disp : "") + " (build " + build + ")";
        }
    }

    static int CpuPercent()
    {
        long i1, k1, u1, i2, k2, u2;
        Native.GetSystemTimes(out i1, out k1, out u1);
        System.Threading.Thread.Sleep(1000);
        Native.GetSystemTimes(out i2, out k2, out u2);
        long idle = i2 - i1, total = (k2 - k1) + (u2 - u1);   // kernel time includes idle
        return total <= 0 ? 0 : (int)Math.Round(100.0 * (total - idle) / total);
    }

    static string Network(Stats s)
    {
        var parts = new List<string>();
        foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (ni.OperationalStatus != OperationalStatus.Up) continue;
            if (ni.NetworkInterfaceType == NetworkInterfaceType.Loopback || ni.NetworkInterfaceType == NetworkInterfaceType.Tunnel) continue;
            var ip = ni.GetIPProperties();
            var v4 = ip.UnicastAddresses.FirstOrDefault(a => a.Address.AddressFamily == AddressFamily.InterNetwork);
            if (v4 == null || ip.GatewayAddresses.Count == 0) continue;   // skip virtual adapters with no route out
            string kind = ni.NetworkInterfaceType == NetworkInterfaceType.Wireless80211 ? "WiFi" : "Ethernet";
            parts.Add(kind + " " + v4.Address + " (" + (ni.Speed / 1000000) + " Mbps)");
        }
        if (parts.Count == 0) { s.Warnings.Add("No network with a gateway"); return "none"; }
        return string.Join("; ", parts.ToArray());
    }

    static string WifiSummary()
    {
        var psi = new ProcessStartInfo("netsh", "wlan show interfaces") { UseShellExecute = false, RedirectStandardOutput = true, CreateNoWindow = true };
        string outp;
        using (var p = Process.Start(psi)) { outp = p.StandardOutput.ReadToEnd(); p.WaitForExit(5000); }
        string ssid = Field(outp, "SSID"), signal = Field(outp, "Signal");
        return ssid == "" ? "not connected" : ssid + (signal != "" ? " (" + signal + ")" : "");
    }

    static string Field(string text, string name)
    {
        foreach (var line in text.Split('\n'))
        {
            int c = line.IndexOf(':');
            if (c > 0 && line.Substring(0, c).Trim() == name) return line.Substring(c + 1).Trim();
        }
        return "";
    }

    static string Displays(Stats s)
    {
        var parts = new List<string>();
        foreach (var sc in Screen.AllScreens)
        {
            string scaling = "";
            try
            {
                var mon = Native.MonitorFromPoint(new Point(sc.Bounds.X + 1, sc.Bounds.Y + 1), 2);
                uint dx, dy;
                if (Native.GetDpiForMonitor(mon, 0, out dx, out dy) == 0) scaling = " @" + (dx * 100 / 96) + "%";
            }
            catch { }
            parts.Add(sc.Bounds.Width + "x" + sc.Bounds.Height + scaling + (sc.Primary ? " (main)" : ""));
        }
        return Screen.AllScreens.Length + ": " + string.Join(", ", parts.ToArray());
    }

    public static string Fmt(TimeSpan t)
    {
        return t.TotalDays >= 1 ? (int)t.TotalDays + "d " + t.Hours + "h" : t.Hours + "h " + t.Minutes + "m";
    }

    public static string Trim(string s, int n) { return s.Length <= n ? s : s.Substring(0, n - 1) + "…"; }

    public string ToJson()
    {
        var sb = new StringBuilder("{");
        foreach (var kv in Items) sb.Append("\"" + Json.Esc(kv.Key) + "\":\"" + Json.Esc(kv.Value) + "\",");
        sb.Append("\"warnings\":[" + string.Join(",", Warnings.Select(w => "\"" + Json.Esc(w) + "\"").ToArray()) + "],");
        sb.Append("\"windows\":[" + string.Join(",", Windows.Select(w =>
            "{\"process\":\"" + Json.Esc(w.Process) + "\",\"title\":\"" + Json.Esc(w.Title) + "\",\"foreground\":" +
            (w.IsForeground ? "true" : "false") + ",\"minimised\":" + (w.Minimised ? "true" : "false") + "}").ToArray()) + "]");
        return sb.Append("}").ToString();
    }
}

// ==================================================================== windows
class WindowInfo
{
    public string Title, Process;
    public bool IsForeground, Minimised;

    public static WindowInfo Foreground()
    {
        var h = Native.GetForegroundWindow();
        return h == IntPtr.Zero ? null : From(h, h);
    }

    // Every visible, titled, top-level app window, in z-order (top first), as the taskbar would list it.
    public static List<WindowInfo> All()
    {
        var list = new List<WindowInfo>();
        var fg = Native.GetForegroundWindow();
        Native.EnumWindows((h, l) =>
        {
            if (!Native.IsWindowVisible(h)) return true;
            if (Native.GetWindowTextLength(h) == 0) return true;
            int ex = Native.GetWindowLong(h, -20);
            if ((ex & 0x80) != 0) return true;                       // WS_EX_TOOLWINDOW
            if (Native.GetWindow(h, 4) != IntPtr.Zero && (ex & 0x40000) == 0) return true;   // owned, not WS_EX_APPWINDOW
            int cloaked; Native.DwmGetWindowAttribute(h, 14, out cloaked, 4);
            if (cloaked != 0) return true;                           // hidden UWP / other-desktop windows
            var w = From(h, fg);
            if (w != null && w.Process != "TextInputHost" && w.Process != "ApplicationFrameHost") list.Add(w);
            return true;
        }, IntPtr.Zero);
        return list;
    }

    static WindowInfo From(IntPtr h, IntPtr fg)
    {
        var sb = new StringBuilder(512);
        Native.GetWindowText(h, sb, sb.Capacity);
        uint pid; Native.GetWindowThreadProcessId(h, out pid);
        string proc = "?";
        try { proc = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; } catch { }
        return new WindowInfo { Title = sb.ToString(), Process = proc, IsForeground = h == fg, Minimised = Native.IsIconic(h) };
    }
}

// ==================================================================== panel
static class Panel
{
    public static void Draw(Graphics g, Rectangle r, Stats s, string nucName, string version)
    {
        var bg = new SolidBrush(Color.FromArgb(24, 26, 30));
        g.FillRectangle(bg, r);
        g.DrawLine(new Pen(Color.FromArgb(70, 74, 82), 2), r.X, r.Y, r.X, r.Bottom);

        using (var title = new Font("Segoe UI", 21f, FontStyle.Bold, GraphicsUnit.Pixel))
        using (var head = new Font("Segoe UI", 13f, FontStyle.Bold, GraphicsUnit.Pixel))
        using (var body = new Font("Segoe UI", 15f, FontStyle.Regular, GraphicsUnit.Pixel))
        using (var small = new Font("Segoe UI", 13f, FontStyle.Regular, GraphicsUnit.Pixel))
        {
            var white = Brushes.White;
            var muted = new SolidBrush(Color.FromArgb(150, 156, 166));
            var amber = new SolidBrush(Color.FromArgb(255, 183, 77));
            var green = new SolidBrush(Color.FromArgb(129, 199, 132));
            float x = r.X + 20, w = r.Width - 36, y = r.Y + 16;

            y = Text(g, nucName, title, white, x, y, w) + 2;
            y = Text(g, DateTime.Now.ToString("ddd d MMM yyyy, h:mm tt") + "  ·  Monitor v" + version, small, muted, x, y, w) + 12;

            // Warnings first: they are why anyone opens the screenshot.
            if (s.Warnings.Count > 0)
            {
                y = Section(g, "NEEDS A LOOK", head, amber, x, y, w);
                foreach (var warn in s.Warnings) y = Text(g, "! " + warn, body, amber, x, y, w);
                y += 10;
            }
            else
            {
                y = Text(g, "OK  Nothing flagged", body, green, x, y, w) + 10;
            }

            y = Section(g, "SYSTEM", head, muted, x, y, w);
            y = Row(g, "Uptime", s.Get("uptime"), body, x, y, w, muted);
            y = Row(g, "CPU", s.Get("cpu"), body, x, y, w, muted);
            y = Row(g, "RAM", s.Get("ram"), body, x, y, w, muted);
            y = Row(g, "Disk C:", s.Get("disk_c"), body, x, y, w, muted);
            y = Row(g, "Windows", s.Get("windows"), body, x, y, w, muted);
            y = Row(g, "PC name", s.Get("computer"), body, x, y, w, muted) + 8;

            y = Section(g, "NETWORK & DISPLAY", head, muted, x, y, w);
            y = Row(g, "Network", s.Get("network"), body, x, y, w, muted);
            y = Row(g, "WiFi", s.Get("wifi"), body, x, y, w, muted);
            y = Row(g, "Displays", s.Get("displays"), body, x, y, w, muted);
            y = Row(g, "Capture", s.Get("capture"), body, x, y, w, muted);
            y = Row(g, "Chrome", s.Get("chrome"), body, x, y, w, muted) + 8;

            y = Section(g, "OPEN WINDOWS (" + s.Windows.Count + ")", head, muted, x, y, w);
            foreach (var win in s.Windows)
            {
                if (y > r.Bottom - 40) { Text(g, "… and more", small, muted, x, y, w); break; }
                string mark = win.IsForeground ? "> " : (win.Minimised ? "- " : "   ");
                var brush = win.IsForeground ? (Brush)white : muted;
                y = Text(g, mark + win.Process + ": " + Stats.Trim(win.Title, 60), small, brush, x, y, w);
            }
        }
    }

    static float Section(Graphics g, string text, Font f, Brush b, float x, float y, float w)
    {
        return Text(g, text, f, b, x, y, w) + 2;
    }

    static float Row(Graphics g, string label, string value, Font f, float x, float y, float w, Brush muted)
    {
        const float labelW = 92;
        g.DrawString(label, f, muted, new RectangleF(x, y, labelW, 200));
        return Text(g, value, f, Brushes.White, x + labelW, y, w - labelW);
    }

    static float Text(Graphics g, string text, Font f, Brush b, float x, float y, float w)
    {
        var size = g.MeasureString(text, f, (int)w);
        g.DrawString(text, f, b, new RectangleF(x, y, w, size.Height + 2));
        return y + size.Height + 1;
    }
}

// ==================================================================== json
static class Json
{
    public static string Esc(string s)
    {
        if (s == null) return "";
        var sb = new StringBuilder(s.Length + 8);
        foreach (char c in s)
        {
            switch (c)
            {
                case '"': sb.Append("\\\""); break;
                case '\\': sb.Append("\\\\"); break;
                case '\n': sb.Append("\\n"); break;
                case '\r': sb.Append("\\r"); break;
                case '\t': sb.Append("\\t"); break;
                default:
                    if (c < 0x20) sb.Append("\\u" + ((int)c).ToString("x4")); else sb.Append(c);
                    break;
            }
        }
        return sb.ToString();
    }
}

// ==================================================================== native
static class Native
{
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int max);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextLength(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int index);
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int value, int size);
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromPoint(Point pt, uint flags);
    [DllImport("shcore.dll")] public static extern int GetDpiForMonitor(IntPtr mon, int type, out uint dpiX, out uint dpiY);
    [DllImport("kernel32.dll")] public static extern ulong GetTickCount64();
    [DllImport("kernel32.dll")] public static extern bool GetSystemTimes(out long idle, out long kernel, out long user);

    [StructLayout(LayoutKind.Sequential)]
    public struct MEMORYSTATUSEX
    {
        public uint dwLength, dwMemoryLoad;
        public ulong ullTotalPhys, ullAvailPhys, ullTotalPageFile, ullAvailPageFile, ullTotalVirtual, ullAvailVirtual, ullAvailExtendedVirtual;
    }
    [DllImport("kernel32.dll")] public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX m);
}
