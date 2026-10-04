using System;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Windows.Forms;
[assembly: AssemblyTitle("LV-01")]
[assembly: AssemblyDescription("A playful Windows awake controller")]
[assembly: AssemblyCompany("Joel Wu")]
[assembly: AssemblyProduct("LV-01")]
[assembly: AssemblyCopyright("Copyright (c) 2026 Joel Wu — MIT License")]
[assembly: AssemblyVersion("0.2.0.0")]
[assembly: AssemblyFileVersion("0.2.0.0")]
internal static class Program {
    private static string Hash(byte[] bytes) {
        using (var sha=SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", "").ToLowerInvariant();
    }
    private static byte[] Resource(string name) {
        using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream(name)) {
            if(stream==null) throw new InvalidOperationException("Missing app resource: "+name);
            using(var buffer=new MemoryStream()) { stream.CopyTo(buffer); return buffer.ToArray(); }
        }
    }
    private static string Extract(string dataRoot) {
        var assembly=Assembly.GetExecutingAssembly();
        var names=assembly.GetManifestResourceNames().Where(n=>n.StartsWith("payload.",StringComparison.Ordinal)).OrderBy(n=>n,StringComparer.Ordinal).ToArray();
        string identity=Hash(Encoding.UTF8.GetBytes(String.Join("\n",names.Select(n=>n+":"+Hash(Resource(n))).ToArray()))).Substring(0,20);
        string folder=Path.Combine(dataRoot,"app",identity);
        using(var gate=new Mutex(false,"Local\\LV01.Extract."+Environment.UserName)) {
            bool owned=false;
            try {
                try { owned=gate.WaitOne(TimeSpan.FromSeconds(20)); } catch(AbandonedMutexException) { owned=true; }
                if(!owned) throw new IOException("Another LV-01 instance is preparing the app. Try again shortly.");
                Directory.CreateDirectory(folder);
                foreach(string name in names) {
                    string fileName=name.Substring("payload.".Length);
                    if(fileName!=Path.GetFileName(fileName)) throw new InvalidOperationException("Invalid packaged filename.");
                    byte[] expected=Resource(name);
                    string target=Path.Combine(folder,fileName);
                    if(File.Exists(target) && Hash(File.ReadAllBytes(target))==Hash(expected)) continue;
                    string temp=target+"."+System.Diagnostics.Process.GetCurrentProcess().Id+".tmp";
                    File.WriteAllBytes(temp,expected);
                    if(File.Exists(target)) File.Replace(temp,target,null); else File.Move(temp,target);
                }
            } finally { if(owned) gate.ReleaseMutex(); }
        }
        return folder;
    }
    [STAThread]
    private static int Main(string[] args) {
        bool smoke=false,paused=false;
        string preview=null,testRoot=null;
        string dataRoot=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"LV-01");
        try {
            for(int i=0;i<args.Length;i++) {
                switch(args[i]) {
                    case "--smoke-test": smoke=true; break;
                    case "--start-paused": paused=true; break;
                    case "--preview": if(++i>=args.Length) throw new ArgumentException("--preview needs a PNG path."); preview=Path.GetFullPath(args[i]); smoke=true; break;
                    case "--test-data": if(++i>=args.Length) throw new ArgumentException("--test-data needs a folder."); testRoot=Path.GetFullPath(args[i]); break;
                    default: throw new ArgumentException("Unknown option: "+args[i]);
                }
            }
            if(testRoot!=null && !smoke) throw new ArgumentException("--test-data requires --smoke-test or --preview.");
            if(smoke) dataRoot=testRoot ?? Path.Combine(Path.GetTempPath(),"LV-01-tests",Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(dataRoot);
            string appRoot=Extract(dataRoot);
            Environment.SetEnvironmentVariable("LV01_DATA_DIR",dataRoot,EnvironmentVariableTarget.Process);
            using(var runspace=RunspaceFactory.CreateRunspace()) {
                runspace.ApartmentState=ApartmentState.STA;
                runspace.ThreadOptions=PSThreadOptions.UseCurrentThread;
                runspace.Open();
                Runspace.DefaultRunspace=runspace;
                using(var shell=PowerShell.Create()) {
                    shell.Runspace=runspace;
                    shell.AddCommand(Path.Combine(appRoot,"lid-vibe-ui.ps1"));
                    if(smoke) shell.AddParameter("SmokeTest");
                    if(paused) shell.AddParameter("StartPaused");
                    if(preview!=null) { shell.AddParameter("PreviewPath",preview); shell.AddParameter("PreviewState","On"); }
                    var result=shell.Invoke();
                    var output=String.Join(Environment.NewLine,result.Select(item=>item.ToString()).ToArray());
                    if(shell.HadErrors) throw new InvalidOperationException(String.Join(Environment.NewLine,shell.Streams.Error.Select(item=>item.ToString()).ToArray()));
                    if(smoke) File.WriteAllText(Path.Combine(dataRoot,"self-test.log"),output,Encoding.UTF8);
                }
            }
            return 0;
        } catch(Exception ex) {
            string error=ex.ToString();
            try { Directory.CreateDirectory(dataRoot); File.WriteAllText(Path.Combine(dataRoot,"last-error.log"),error,Encoding.UTF8); } catch { }
            if(!smoke) MessageBox.Show("LV-01 could not start or finish cleanly.\n\n"+ex.Message+"\n\nDetails: "+Path.Combine(dataRoot,"last-error.log"),"LV-01",MessageBoxButtons.OK,MessageBoxIcon.Warning);
            return 1;
        }
    }
}
