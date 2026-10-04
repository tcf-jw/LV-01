// Hardware media-key equivalents. Windows/player settings choose the receiver.
using System;
using System.Runtime.InteropServices;
namespace LV01 {
    public enum MediaAction { Previous, PlayPause, Next }
    public static class MediaKeys {
        [StructLayout(LayoutKind.Sequential)]
        public struct KeyboardInput { public ushort Key, Scan; public uint Flags, Time; public UIntPtr ExtraInfo; }
        [StructLayout(LayoutKind.Sequential)]
        public struct MouseInput { public int X, Y; public uint Data, Flags, Time; public UIntPtr ExtraInfo; }
        [StructLayout(LayoutKind.Sequential)]
        public struct HardwareInput { public uint Message; public ushort Low, High; }
        [StructLayout(LayoutKind.Explicit)]
        public struct InputUnion {
            [FieldOffset(0)] public KeyboardInput Keyboard;
            [FieldOffset(0)] public MouseInput Mouse;
            [FieldOffset(0)] public HardwareInput Hardware;
        }
        [StructLayout(LayoutKind.Sequential)]
        public struct Input { public uint Type; public InputUnion Data; }
        [DllImport("user32.dll", SetLastError=true)]
        private static extern uint SendInput(uint count, Input[] inputs, int size);

        public static Input[] CreateInputs(MediaAction action) {
            ushort key;
            switch(action) {
                case MediaAction.Previous: key=0xB1; break;
                case MediaAction.PlayPause: key=0xB3; break;
                case MediaAction.Next: key=0xB0; break;
                default: throw new ArgumentOutOfRangeException("action");
            }
            var down=new Input { Type=1, Data=new InputUnion { Keyboard=new KeyboardInput { Key=key } } };
            var up=down; up.Data.Keyboard.Flags=2; // KEYEVENTF_KEYUP
            return new[] { down, up };
        }
        public static void Send(MediaAction action) {
            Send(action, inputs=>SendInput((uint)inputs.Length,inputs,Marshal.SizeOf(typeof(Input))));
        }
        // The injected boundary lets tests verify dispatch and failure without touching playback.
        public static void Send(MediaAction action, Func<Input[],uint> dispatch) {
            if(dispatch==null) throw new ArgumentNullException("dispatch");
            var inputs=CreateInputs(action);
            uint sent=dispatch(inputs);
            if(sent==2) return;
            if(sent==1) dispatch(new[] { inputs[1] }); // Best-effort release after a partial send.
            throw new InvalidOperationException("Windows did not accept the media key. Check the player or Windows restrictions.");
        }
    }
}
