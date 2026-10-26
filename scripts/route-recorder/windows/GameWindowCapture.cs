using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace PlayerBots.RouteRecorder
{
    public sealed class CaptureTarget
    {
        public long Handle;
        public int ProcessId;
        public long StartTicks;
        public string Label;
        public override string ToString() { return Label; }
    }
    public sealed class CapturedFrame
    {
        public byte[] Jpeg;
        public int Width, Height;
        public string CapturedUtc;
    }
    public static class GameWindowCapture
    {
        [StructLayout(LayoutKind.Sequential)] struct Rect { public int Left, Top, Right, Bottom; }
        [StructLayout(LayoutKind.Sequential)] struct Point { public int X, Y; }
        [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
        [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint id);
        [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out Rect r);
        [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref Point p);
        [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c);
        [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point p);
        [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr h, uint flags);
        [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
        [StructLayout(LayoutKind.Sequential)] struct KeyboardInput { public ushort Key, Scan; public uint Flags, Time; public UIntPtr Extra; }
        [StructLayout(LayoutKind.Sequential)] struct MouseInput { public int X,Y; public uint Data, Flags, Time; public UIntPtr Extra; }
        [StructLayout(LayoutKind.Explicit)] struct InputUnion { [FieldOffset(0)] public KeyboardInput Keyboard; [FieldOffset(0)] public MouseInput Mouse; }
        [StructLayout(LayoutKind.Sequential)] struct Input { public uint Type; public InputUnion Value; }
        [DllImport("user32.dll", SetLastError=true)] static extern uint SendInput(uint count, Input[] inputs, int size);

        public static string RequestScreenshot(CaptureTarget target, int key)
        {
            if (key < 0x70 || key > 0x7b) throw new ArgumentOutOfRangeException("key", "Choose F1 through F12.");
            if (!IsForeground(target)) throw new InvalidOperationException("Screenshot key skipped: selected ArcheAge window is not in front.");
            foreach (int modifier in new int[] {0x10,0x11,0x12,0x5b,0x5c,key})
                if ((GetAsyncKeyState(modifier) & 0x8000) != 0) throw new InvalidOperationException("Release modifier/screenshot keys; the next timed photo will retry.");
            var down = new Input { Type=1, Value=new InputUnion { Keyboard=new KeyboardInput {Key=(ushort)key} } };
            var up = new Input { Type=1, Value=new InputUnion { Keyboard=new KeyboardInput {Key=(ushort)key,Flags=2} } };
            string requested = DateTimeOffset.UtcNow.ToString("O");
            uint sent = SendInput(2, new Input[] {down,up}, Marshal.SizeOf(typeof(Input)));
            // A partial insertion must not leave the requested function key held.
            if (sent == 1) SendInput(1, new Input[] {up}, Marshal.SizeOf(typeof(Input)));
            if (sent != 2)
                throw new InvalidOperationException("Windows did not send the screenshot key. Check game/recorder permission levels.");
            return requested;
        }

        public static CapturedFrame DecodeScreenshot(byte[] source, int maximumWidth, string requestedUtc)
        {
            if (maximumWidth < 640 || maximumWidth > 2560 || source.Length > 134217728) throw new ArgumentOutOfRangeException("source");
            using (var input = new MemoryStream(source))
            using (var original = Image.FromStream(input, false, true))
            {
                if (original.Width > 8192 || original.Height > 8192 || original.Width < 1 || original.Height < 1)
                    throw new InvalidOperationException("Screenshot dimensions are unsupported.");
                double ratio = Math.Min(1.0,(double)maximumWidth/original.Width);
                using (var bitmap = new Bitmap((int)(original.Width*ratio),Math.Max(1,(int)(original.Height*ratio)),PixelFormat.Format24bppRgb))
                using (var graphics = Graphics.FromImage(bitmap))
                using (var output = new MemoryStream())
                using (var settings = new EncoderParameters(1))
                {
                    graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    graphics.DrawImage(original,0,0,bitmap.Width,bitmap.Height);
                    settings.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality,80L);
                    ImageCodecInfo jpeg = null;
                    foreach(var codec in ImageCodecInfo.GetImageEncoders()) if(codec.MimeType=="image/jpeg") jpeg=codec;
                    bitmap.Save(output,jpeg,settings);
                    return new CapturedFrame {Jpeg=output.ToArray(),Width=bitmap.Width,Height=bitmap.Height,CapturedUtc=requestedUtc};
                }
            }
        }

        static bool IsGame(Process p)
        {
            return String.Equals(p.ProcessName, "archeage", StringComparison.OrdinalIgnoreCase) ||
                String.Equals(p.ProcessName, "archeage64", StringComparison.OrdinalIgnoreCase);
        }
        public static CaptureTarget[] List()
        {
            var targets = new List<CaptureTarget>();
            foreach (var p in Process.GetProcesses())
            {
                using (p)
                {
                    try
                    {
                        if (!IsGame(p) || p.MainWindowHandle == IntPtr.Zero || !IsWindowVisible(p.MainWindowHandle)) continue;
                        targets.Add(new CaptureTarget { Handle = p.MainWindowHandle.ToInt64(), ProcessId = p.Id,
                            StartTicks = p.StartTime.ToUniversalTime().Ticks,
                            Label = "ArcheAge game window (process " + p.Id + ")" });
                    }
                    catch (InvalidOperationException) { }
                    catch (System.ComponentModel.Win32Exception) { }
                }
            }
            return targets.ToArray();
        }
        public static bool IsForeground(CaptureTarget target)
        {
            if (target == null) return false;
            try
            {
                var h = new IntPtr(target.Handle);
                uint pid; GetWindowThreadProcessId(h, out pid);
                using (var p = Process.GetProcessById(target.ProcessId))
                    return pid == target.ProcessId && IsGame(p) &&
                        p.StartTime.ToUniversalTime().Ticks == target.StartTicks &&
                        GetForegroundWindow() == h && IsWindowVisible(h) && !IsIconic(h);
            }
            catch (ArgumentException) { return false; }
            catch (InvalidOperationException) { return false; }
            catch (System.ComponentModel.Win32Exception) { return false; }
        }
        static Rectangle Bounds(IntPtr h)
        {
            Rect r; var point = new Point();
            if (!GetClientRect(h, out r) || !ClientToScreen(h, ref point)) throw new InvalidOperationException("Game window is unavailable.");
            return new Rectangle(point.X, point.Y, r.Right - r.Left, r.Bottom - r.Top);
        }
        static bool Uncovered(IntPtr h, Rectangle r)
        {
            // Reject known overlays; even foreground windows can have a topmost app above them.
            for (int y = 1; y <= 8; y++) for (int x = 1; x <= 12; x++)
            {
                var p = new Point { X = r.Left + r.Width * x / 13, Y = r.Top + r.Height * y / 9 };
                if (GetAncestor(WindowFromPoint(p), 2) != h) return false;
            }
            return true;
        }
        public static CapturedFrame Capture(CaptureTarget target, int maximumWidth)
        {
            if (maximumWidth < 640 || maximumWidth > 2560) throw new ArgumentOutOfRangeException("maximumWidth");
            if (!IsForeground(target)) throw new InvalidOperationException("Waiting for the selected ArcheAge window in the foreground.");
            var oldDpi = SetThreadDpiAwarenessContext(new IntPtr(-4));
            if (oldDpi == IntPtr.Zero) throw new InvalidOperationException("Physical-pixel capture requires Windows 10 1703 or later.");
            try
            {
                var h = new IntPtr(target.Handle);
                var area = Bounds(h);
                bool onScreen = false;
                foreach (var screen in Screen.AllScreens) if (screen.Bounds.Contains(area)) onScreen = true;
                if (!onScreen || area.Width < 320 || area.Height < 200 || area.Width > 8192 || area.Height > 8192)
                    throw new InvalidOperationException("Keep the entire game window visible on one monitor; use windowed or borderless mode.");
                if (!Uncovered(h, area)) throw new InvalidOperationException("Another window covers the game; photo skipped.");
                using (var original = new Bitmap(area.Width, area.Height, PixelFormat.Format24bppRgb))
                {
                    string stamp;
                    using (var g = Graphics.FromImage(original))
                    {
                        g.CopyFromScreen(area.Location, System.Drawing.Point.Empty, area.Size, CopyPixelOperation.SourceCopy);
                        stamp = DateTimeOffset.UtcNow.ToString("O");
                    }
                    if (!IsForeground(target) || Bounds(h) != area || !Uncovered(h, area))
                        throw new InvalidOperationException("Game focus or window position changed; photo skipped.");
                    int brightest = 0;
                    for (int y = 0; y < 12; y++) for (int x = 0; x < 16; x++)
                    {
                        var c = original.GetPixel(original.Width * (x + 1) / 17, original.Height * (y + 1) / 13);
                        brightest = Math.Max(brightest, Math.Max(c.R, Math.Max(c.G, c.B)));
                    }
                    if (brightest < 8) throw new InvalidOperationException("Photo is black. Try borderless/windowed mode and check the preview after a short walk.");
                    var ratio = Math.Min(1.0, (double)maximumWidth / original.Width);
                    using (var resized = new Bitmap((int)(original.Width * ratio), Math.Max(1, (int)(original.Height * ratio)), PixelFormat.Format24bppRgb))
                    using (var g = Graphics.FromImage(resized))
                    using (var bytes = new MemoryStream())
                    using (var settings = new EncoderParameters(1))
                    {
                        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                        g.DrawImage(original, 0, 0, resized.Width, resized.Height);
                        settings.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, 80L);
                        ImageCodecInfo jpeg = null;
                        foreach (var codec in ImageCodecInfo.GetImageEncoders()) if (codec.MimeType == "image/jpeg") jpeg = codec;
                        resized.Save(bytes, jpeg, settings);
                        return new CapturedFrame { Jpeg = bytes.ToArray(), Width = resized.Width, Height = resized.Height, CapturedUtc = stamp };
                    }
                }
            }
            finally { SetThreadDpiAwarenessContext(oldDpi); }
        }
    }
}
