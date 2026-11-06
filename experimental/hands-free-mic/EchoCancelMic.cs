// Records the microphone through Windows' built-in echo canceller
// (the Voice Capture DSP), so sound from the speakers is filtered out.
// Usage: EchoCancelMic.exe <out.wav> <seconds>
//        EchoCancelMic.exe --stdout       (streams raw 16 kHz mono 16-bit PCM forever)
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

[StructLayout(LayoutKind.Sequential)]
struct DMO_MEDIA_TYPE {
    public Guid majortype; public Guid subtype;
    public int bFixedSizeSamples; public int bTemporalCompression; public int lSampleSize;
    public Guid formattype; public IntPtr pUnk; public int cbFormat; public IntPtr pbFormat;
}

[StructLayout(LayoutKind.Sequential)]
struct DMO_OUTPUT_DATA_BUFFER {
    public IntPtr pBuffer; public int dwStatus; public long rtTimestamp; public long rtTimelength;
}

[StructLayout(LayoutKind.Sequential)]
struct PROPERTYKEY { public Guid fmtid; public int pid; }

[StructLayout(LayoutKind.Explicit, Size = 24)]
struct PROPVARIANT { [FieldOffset(0)] public short vt; [FieldOffset(8)] public int intVal; }

[ComImport, Guid("d8ad0f58-5494-4102-97c5-ec798e59bcf4"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMediaObject {
    [PreserveSig] int GetStreamCount(out int i, out int o);
    [PreserveSig] int GetInputStreamInfo(int s, out int f);
    [PreserveSig] int GetOutputStreamInfo(int s, out int f);
    [PreserveSig] int GetInputType(int s, int t, IntPtr pmt);
    [PreserveSig] int GetOutputType(int s, int t, IntPtr pmt);
    [PreserveSig] int SetInputType(int s, IntPtr pmt, int f);
    [PreserveSig] int SetOutputType(int s, ref DMO_MEDIA_TYPE pmt, int f);
    [PreserveSig] int GetInputCurrentType(int s, IntPtr pmt);
    [PreserveSig] int GetOutputCurrentType(int s, IntPtr pmt);
    [PreserveSig] int GetInputSizeInfo(int s, out int size, out int look, out int align);
    [PreserveSig] int GetOutputSizeInfo(int s, out int size, out int align);
    [PreserveSig] int GetInputMaxLatency(int s, out long l);
    [PreserveSig] int SetInputMaxLatency(int s, long l);
    [PreserveSig] int Flush();
    [PreserveSig] int Discontinuity(int s);
    [PreserveSig] int AllocateStreamingResources();
    [PreserveSig] int FreeStreamingResources();
    [PreserveSig] int GetInputStatus(int s, out int f);
    [PreserveSig] int ProcessInput(int s, IntPtr buf, int f, long t, long len);
    [PreserveSig] int ProcessOutput(int f, int count, [In, Out, MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 1)] DMO_OUTPUT_DATA_BUFFER[] bufs, out int status);
    [PreserveSig] int Lock(int l);
}

[ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IPropertyStore {
    [PreserveSig] int GetCount(out int c);
    [PreserveSig] int GetAt(int i, out PROPERTYKEY k);
    [PreserveSig] int GetValue(ref PROPERTYKEY k, out PROPVARIANT v);
    [PreserveSig] int SetValue(ref PROPERTYKEY k, ref PROPVARIANT v);
    [PreserveSig] int Commit();
}

[ComVisible(true), Guid("59eff8b9-938c-4a26-82f2-95cb84cdc837"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMediaBuffer {
    [PreserveSig] int SetLength(int len);
    [PreserveSig] int GetMaxLength(out int len);
    [PreserveSig] int GetBufferAndLength(out IntPtr buf, out int len);
}

[ComVisible(true), ClassInterface(ClassInterfaceType.None)]
public class MediaBuffer : IMediaBuffer {
    public IntPtr Data; public int Max; public int Length;
    public MediaBuffer(int max) { Max = max; Data = Marshal.AllocCoTaskMem(max); }
    public int SetLength(int len) { if (len > Max) return unchecked((int)0x80070057); Length = len; return 0; }
    public int GetMaxLength(out int len) { len = Max; return 0; }
    public int GetBufferAndLength(out IntPtr buf, out int len) { buf = Data; len = Length; return 0; }
}

[ComImport, Guid("745057c7-f353-4f2d-a7ee-58434477730e")]
class CWMAudioAEC { }

static class Program {
    static readonly Guid AecProps = new Guid("6f52c567-0360-4bd2-9617-ccbf1421c939");

    static void SetInt(IPropertyStore ps, int pid, int val) {
        var k = new PROPERTYKEY { fmtid = AecProps, pid = pid };
        var v = new PROPVARIANT { vt = 3, intVal = val }; // VT_I4
        Check(ps.SetValue(ref k, ref v), "SetValue " + pid);
    }

    static void Check(int hr, string what) { if (hr < 0) throw new Exception(what + " failed: 0x" + hr.ToString("X8")); }

    [MTAThread]
    static int Main(string[] args) {
        bool toStdout = args.Length > 0 && args[0] == "--stdout";
        string path = toStdout ? null : args[0];
        double seconds = toStdout ? double.MaxValue : double.Parse(args[1]);

        // The echo canceller fails after a few seconds if nothing is playing on the
        // speakers, so keep a silent sound looping the whole time.
        var silence = new MemoryStream();
        using (var sw = new BinaryWriter(silence, System.Text.Encoding.ASCII, true)) {
            int n = 32000;
            sw.Write(new[] { 'R', 'I', 'F', 'F' }); sw.Write(36 + n);
            sw.Write(new[] { 'W', 'A', 'V', 'E', 'f', 'm', 't', ' ' }); sw.Write(16);
            sw.Write((short)1); sw.Write((short)1); sw.Write(16000); sw.Write(32000);
            sw.Write((short)2); sw.Write((short)16);
            sw.Write(new[] { 'd', 'a', 't', 'a' }); sw.Write(n); sw.Write(new byte[n]);
        }
        silence.Position = 0;
        var player = new System.Media.SoundPlayer(silence);
        player.PlayLooping();

        var dmo = (IMediaObject)new CWMAudioAEC();
        var ps = (IPropertyStore)dmo;
        SetInt(ps, 2, 0);  // SYSTEM_MODE = SINGLE_CHANNEL_AEC (echo cancel, default mic + speakers)

        var wfx = Marshal.AllocCoTaskMem(18);
        short[] w = { 1, 1 }; // PCM, mono
        Marshal.WriteInt16(wfx, 0, 1); Marshal.WriteInt16(wfx, 2, 1);
        Marshal.WriteInt32(wfx, 4, 16000); Marshal.WriteInt32(wfx, 8, 32000);
        Marshal.WriteInt16(wfx, 12, 2); Marshal.WriteInt16(wfx, 14, 16); Marshal.WriteInt16(wfx, 16, 0);
        var mt = new DMO_MEDIA_TYPE {
            majortype = new Guid("73647561-0000-0010-8000-00AA00389B71"),
            subtype = new Guid("00000001-0000-0010-8000-00AA00389B71"),
            bFixedSizeSamples = 1, lSampleSize = 2,
            formattype = new Guid("05589f81-c356-11ce-bf01-00aa0055595a"),
            cbFormat = 18, pbFormat = wfx
        };
        Check(dmo.SetOutputType(0, ref mt, 0), "SetOutputType");
        Check(dmo.AllocateStreamingResources(), "AllocateStreamingResources");

        var mb = new MediaBuffer(32000);
        IntPtr pmb = Marshal.GetComInterfaceForObject(mb, typeof(IMediaBuffer));
        var bufs = new DMO_OUTPUT_DATA_BUFFER[1];
        Stream outs = toStdout ? Console.OpenStandardOutput() : new MemoryStream();
        var chunk = new byte[32000];
        var start = DateTime.UtcNow;

        while ((DateTime.UtcNow - start).TotalSeconds < seconds) {
            int status;
            do {
                mb.Length = 0;
                bufs[0].pBuffer = pmb; bufs[0].dwStatus = 0;
                int hr = dmo.ProcessOutput(0, 1, bufs, out status);
                if (hr < 0) Check(hr, "ProcessOutput");
                if (mb.Length > 0) {
                    Marshal.Copy(mb.Data, chunk, 0, mb.Length);
                    outs.Write(chunk, 0, mb.Length);
                    if (toStdout) outs.Flush();
                }
            } while ((bufs[0].dwStatus & 0x01000000) != 0); // more data waiting
            Thread.Sleep(10);
        }

        if (!toStdout) {
            var pcm = ((MemoryStream)outs).ToArray();
            using (var f = new BinaryWriter(File.Create(path))) {
                f.Write(new[] { 'R', 'I', 'F', 'F' }); f.Write(36 + pcm.Length);
                f.Write(new[] { 'W', 'A', 'V', 'E', 'f', 'm', 't', ' ' }); f.Write(16);
                f.Write((short)1); f.Write((short)1); f.Write(16000); f.Write(32000);
                f.Write((short)2); f.Write((short)16);
                f.Write(new[] { 'd', 'a', 't', 'a' }); f.Write(pcm.Length); f.Write(pcm);
            }
        }
        dmo.FreeStreamingResources();
        return 0;
    }
}
