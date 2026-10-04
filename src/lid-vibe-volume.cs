using System;
using System.Runtime.InteropServices;

namespace LV01
{
    public sealed class VolumeState
    {
        public double Percent { get; private set; }
        public bool Muted { get; private set; }
        public VolumeState(double percent, bool muted) { Percent = percent; Muted = muted; }
    }

    public static class MasterVolume
    {
        public static float ToScalar(double percent)
        {
            if (Double.IsNaN(percent) || Double.IsInfinity(percent))
                throw new ArgumentOutOfRangeException("percent");
            return (float)(Math.Max(0, Math.Min(100, percent)) / 100);
        }

        public static VolumeState Read() { return Access(null); }
        public static void Set(double percent) { Access(ToScalar(percent)); }

        // Resolve the default render endpoint each time, including after a device switch.
        // No endpoint is cached and no volume or mute setting is written on startup.
        private static VolumeState Access(float? scalar)
        {
            object enumerator = null, endpoint = null;
            IDevice device = null;
            try
            {
                enumerator = Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")));
                ((IDeviceEnumerator)enumerator).GetDefaultAudioEndpoint(0, 0, out device);
                Guid iid = typeof(IEndpointVolume).GUID;
                device.Activate(ref iid, 23, IntPtr.Zero, out endpoint);
                IEndpointVolume volume = (IEndpointVolume)endpoint;
                if (scalar.HasValue) volume.SetMasterVolumeLevelScalar(scalar.Value, IntPtr.Zero);
                float level; bool muted;
                volume.GetMasterVolumeLevelScalar(out level);
                volume.GetMute(out muted);
                return new VolumeState(level * 100.0, muted);
            }
            finally
            {
                if (endpoint != null) Marshal.ReleaseComObject(endpoint);
                if (device != null) Marshal.ReleaseComObject(device);
                if (enumerator != null) Marshal.ReleaseComObject(enumerator);
            }
        }

        // COM slots follow mmdeviceapi.h and endpointvolume.h through the last used method.
        // Void signatures translate failed HRESULTs into exceptions at the UI boundary.
        [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IDeviceEnumerator
        {
            void EnumAudioEndpoints(int flow, uint mask, out IntPtr devices);
            void GetDefaultAudioEndpoint(int flow, int role, out IDevice device);
        }
        [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IDevice
        {
            void Activate(ref Guid iid, uint context, IntPtr parameters, [MarshalAs(UnmanagedType.IUnknown)] out object instance);
        }
        [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IEndpointVolume
        {
            void RegisterControlChangeNotify(IntPtr callback);
            void UnregisterControlChangeNotify(IntPtr callback);
            void GetChannelCount(out uint count);
            void SetMasterVolumeLevel(float level, IntPtr context);
            void SetMasterVolumeLevelScalar(float level, IntPtr context);
            void GetMasterVolumeLevel(out float level);
            void GetMasterVolumeLevelScalar(out float level);
            void SetChannelVolumeLevel(uint channel, float level, IntPtr context);
            void SetChannelVolumeLevelScalar(uint channel, float level, IntPtr context);
            void GetChannelVolumeLevel(uint channel, out float level);
            void GetChannelVolumeLevelScalar(uint channel, out float level);
            void SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, IntPtr context);
            void GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
        }
    }
}
