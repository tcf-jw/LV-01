using System;
using System.Runtime.InteropServices;
using LV01;
public static class MediaKeysChecks {
    private static void Check(bool condition,string name) { if(!condition) throw new Exception(name); }
    public static string Run() {
        Check(Marshal.SizeOf(typeof(MediaKeys.Input))==(IntPtr.Size==8?40:28),"Native INPUT layout");
        var actions=new[] { MediaAction.Previous,MediaAction.PlayPause,MediaAction.Next };
        var keys=new ushort[] {0xB1,0xB3,0xB0};
        for(int i=0;i<actions.Length;i++) {
            var pair=MediaKeys.CreateInputs(actions[i]);
            Check(pair.Length==2 && pair[0].Type==1 && pair[1].Type==1,"Keyboard pair");
            Check(pair[0].Data.Keyboard.Key==keys[i] && pair[1].Data.Keyboard.Key==keys[i],"Media key mapping");
            Check(pair[0].Data.Keyboard.Flags==0 && pair[1].Data.Keyboard.Flags==2,"Balanced press/release");
        }
        bool rejected=false;
        try { MediaKeys.CreateInputs((MediaAction)99); } catch(ArgumentOutOfRangeException) { rejected=true; }
        Check(rejected,"Unsupported commands must be rejected");
        int calls=0;
        MediaKeys.Send(MediaAction.PlayPause, inputs=> {calls++; return 2;});
        Check(calls==1,"Successful pair sent once");
        calls=0; rejected=false;
        try { MediaKeys.Send(MediaAction.Next, inputs=> {calls++; return 0;}); } catch(InvalidOperationException) {rejected=true;}
        Check(rejected && calls==1,"Blocked input reported without retries");
        calls=0; rejected=false; bool released=false;
        try { MediaKeys.Send(MediaAction.Previous, inputs=> {
            calls++; if(calls==2) released=inputs.Length==1 && inputs[0].Data.Keyboard.Flags==2;
            return 1;
        }); } catch(InvalidOperationException) {rejected=true;}
        Check(rejected && calls==2 && released,"Partial send releases key and reports failure");
        return "8 media checks passed; native input was mocked, no playback changed.";
    }
}
