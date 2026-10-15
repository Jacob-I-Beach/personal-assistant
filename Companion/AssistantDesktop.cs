using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Web.Script.Serialization;
using System.Windows.Automation;
using System.Windows.Forms;

// A normal-user desktop tool. Secure desktops, login and UAC are never targets.
internal static class AssistantDesktop {
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
    [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("user32.dll")] static extern bool SwitchDesktop(IntPtr desktop);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr window, StringBuilder text, int maximum);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
    [DllImport("user32.dll")] static extern uint SendInput(uint count, INPUT[] inputs, int size);
    [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public UNION data; }
    [StructLayout(LayoutKind.Explicit)] struct UNION { [FieldOffset(0)] public KEYBOARD keyboard; [FieldOffset(0)] public MOUSE mouse; }
    [StructLayout(LayoutKind.Sequential)] struct KEYBOARD { public ushort key, scan; public uint flags, time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct MOUSE { public int x,y; public uint data,flags,time; public UIntPtr extra; }
    static string Value(Dictionary<string,object> args,string name) { object value; return args.TryGetValue(name,out value)&&value!=null?Convert.ToString(value):null; }
    static int Integer(Dictionary<string,object> args,string name) { int value; if(!Int32.TryParse(Value(args,name),out value))throw new Exception("A numeric coordinate is required.");return value; }
    static string Title() { var value=new StringBuilder(1024);GetWindowText(GetForegroundWindow(),value,value.Capacity);return value.ToString(); }
    static void Type(string value) {
        if(value==null||value.Length>10000)throw new Exception("Enter up to 10,000 characters.");
        try{if(AutomationElement.FocusedElement.Current.IsPassword)throw new InvalidOperationException("Password entry stays user-operated.");}catch(ElementNotAvailableException){throw new Exception("Take another snapshot before typing.");}
        foreach(char c in value){var key=new INPUT{type=1,data=new UNION{keyboard=new KEYBOARD{scan=c,flags=4}}};var up=key;up.data.keyboard.flags=6;if(SendInput(2,new[]{key,up},Marshal.SizeOf(typeof(INPUT)))!=2)throw new Exception("Windows did not accept the text input.");}
    }
    static List<object> Controls(IntPtr window) {
        var output=new List<object>();
        try {
            var queue=new Queue<KeyValuePair<AutomationElement,int>>();queue.Enqueue(new KeyValuePair<AutomationElement,int>(AutomationElement.FromHandle(window),0));
            while(queue.Count>0&&output.Count<70){var node=queue.Dequeue();var current=node.Key.Current;
                if(!current.IsOffscreen&&!current.IsPassword&&!String.IsNullOrWhiteSpace(current.Name)){
                    var rect=current.BoundingRectangle;output.Add(new{name=current.Name.Length>180?current.Name.Substring(0,180):current.Name,kind=current.ControlType.ProgrammaticName,enabled=current.IsEnabled,x=rect.X,y=rect.Y,width=rect.Width,height=rect.Height});
                }
                if(node.Value>=3)continue;
                var children=node.Key.FindAll(TreeScope.Children,Condition.TrueCondition);
                for(int i=0;i<children.Count&&i<40;i++)queue.Enqueue(new KeyValuePair<AutomationElement,int>(children[i],node.Value+1));
            }
        }catch{/* Pixels remain the source of truth if an app has no accessibility tree. */}
        return output;
    }
    [STAThread] static int Main(string[] argv) {
        Console.InputEncoding=Encoding.UTF8;Console.OutputEncoding=new UTF8Encoding(false);
        var json=new JavaScriptSerializer{MaxJsonLength=16*1024*1024};
        try {
            if(argv.Length==1&&argv[0]=="--self-test"){Console.WriteLine(json.Serialize(new{available=true,interactive_session=Environment.UserInteractive}));return 0;}
            SetProcessDPIAware();
            var args=json.Deserialize<Dictionary<string,object>>(Console.In.ReadToEnd());
            var desktop=OpenInputDesktop(0,false,0x0100);
            if(desktop==IntPtr.Zero)throw new Exception("Unlock the Windows session before using desktop tools.");
            bool unlocked=SwitchDesktop(desktop);CloseDesktop(desktop);if(!unlocked)throw new Exception("Desktop interaction is unavailable while Windows is locked.");
            var bounds=SystemInformation.VirtualScreen;double scale=Math.Min(1.0,1600.0/bounds.Width);
            string screenId=bounds.X+","+bounds.Y+","+bounds.Width+","+bounds.Height;
            string action=Value(args,"action")??"snapshot",window=Title();
            if(action!="snapshot"){
                if(Value(args,"expected_screen_id")!=screenId)throw new Exception("The display arrangement changed. Take a new snapshot before acting.");
                if(Value(args,"expected_window")!=window)throw new Exception("The foreground window changed. Take a new snapshot before acting.");
                if(Value(args,"expected_window_id")!=GetForegroundWindow().ToInt64().ToString())throw new Exception("The target window changed. Take a new snapshot.");
            }
            if(action=="click"||action=="scroll"){
                int x=Integer(args,"x"),y=Integer(args,"y");
                if(x<0||y<0||x>=bounds.Width*scale||y>=bounds.Height*scale)throw new Exception("The coordinates are outside the observed screen.");
                if(!SetCursorPos(bounds.X+(int)(x/scale),bounds.Y+(int)(y/scale)))throw new Exception("Windows rejected cursor movement.");
                if(action=="click"){mouse_event(2,0,0,0,UIntPtr.Zero);mouse_event(4,0,0,0,UIntPtr.Zero);}
                else{string direction=Value(args,"text");if(direction!="up"&&direction!="down")throw new Exception("Scroll direction must be up or down.");mouse_event(0x0800,0,0,unchecked((uint)(direction=="up"?360:-360)),UIntPtr.Zero);}
            }else if(action=="type")Type(Value(args,"text"));
            else if(action=="key"){
                var keys=new Dictionary<string,string>{{"enter","{ENTER}"},{"tab","{TAB}"},{"escape","{ESC}"},{"backspace","{BACKSPACE}"},{"delete","{DELETE}"},{"ctrl+a","^a"},{"ctrl+c","^c"},{"ctrl+v","^v"},{"ctrl+z","^z"},{"alt+left","%{LEFT}"},{"up","{UP}"},{"down","{DOWN}"},{"left","{LEFT}"},{"right","{RIGHT}"}};
                string key=Value(args,"text"),sequence;if(key==null||!keys.TryGetValue(key.ToLowerInvariant(),out sequence))throw new Exception("This key combination is unsupported.");SendKeys.SendWait(sequence);
            }else if(action!="snapshot")throw new Exception("Unsupported desktop action.");
            if(action!="snapshot")System.Threading.Thread.Sleep(220);
            var foreground=GetForegroundWindow();string image;
            using(var original=new Bitmap(bounds.Width,bounds.Height)){
                using(var graphics=Graphics.FromImage(original))graphics.CopyFromScreen(bounds.Location,Point.Empty,bounds.Size);
                using(var resized=new Bitmap(original,new Size((int)(bounds.Width*scale),(int)(bounds.Height*scale))))
                using(var memory=new MemoryStream()){resized.Save(memory,ImageFormat.Png);image=Convert.ToBase64String(memory.ToArray());}
            }
            var monitors=new List<object>();
            foreach(var screen in Screen.AllScreens){var rect=screen.Bounds;monitors.Add(new{name=screen.DeviceName,primary=screen.Primary,orientation=rect.Height>rect.Width?"portrait":"landscape",x=(rect.X-bounds.X)*scale,y=(rect.Y-bounds.Y)*scale,width=rect.Width*scale,height=rect.Height*scale});}
            Console.WriteLine(json.Serialize(new{window=Title(),window_id=foreground.ToInt64().ToString(),screen_id=screenId,desktop_x=bounds.X,desktop_y=bounds.Y,pixels_to_screenshot=scale,monitors=monitors,width=(int)(bounds.Width*scale),height=(int)(bounds.Height*scale),image_base64=image,controls=Controls(foreground),controls_coordinate_space="physical desktop; screenshot x=(physical x-desktop_x)*pixels_to_screenshot; same for y. Monitor bounds and click coordinates use screenshot pixels.",verification=action=="snapshot"?"Observed screenshot and available controls.":"Input submitted. Inspect this new screenshot before claiming the intended outcome."}));return 0;
        }catch(Exception error){Console.WriteLine(json.Serialize(new{error=error.Message}));return 1;}
    }
}
