// Native vector artwork. No network, power APIs or resource loading.
using System;
using System.Windows;
using System.Windows.Media;
public sealed class LidVibeArt : FrameworkElement {
    public int Scene { get; set; }
    public double Phase { get; private set; }
    public double EffectRemaining { get; private set; }
    public int FrameCount { get; private set; }
    private static Brush B(string hex) { var b=(SolidColorBrush)new BrushConverter().ConvertFromString(hex); b.Freeze(); return b; }
    private static readonly Brush Cream=B("#DEE8CC"), Mint=B("#6EA88B"), Dim=B("#263D35"), Dark=B("#172622"), Pink=B("#EA9C83"), Cyan=B("#6BC6C7"), Orange=B("#EE8052"), Gold=B("#D6B665");
    private static readonly Pen GridPen=new Pen(Dim,0.4), CyanPen=new Pen(Cyan,1), GoldPen=new Pen(Gold,1);
    public void Advance(double seconds, double tempo) { Phase += Math.Min(0.25,seconds)*tempo; EffectRemaining=Math.Max(0,EffectRemaining-seconds); FrameCount++; InvalidateVisual(); }
    public void Trigger() { EffectRemaining=3; InvalidateVisual(); }
    public void ClearEffect() { EffectRemaining=0; InvalidateVisual(); }
    private static void R(DrawingContext d,Brush b,double x,double y,double w,double h) { d.DrawRectangle(b,null,new Rect(x,y,w,h)); }
    private static void Line(DrawingContext d,Brush b,double x,double y,double xx,double yy,double width) { d.DrawLine(new Pen(b,width),new Point(x,y),new Point(xx,yy)); }
    protected override void OnRender(DrawingContext d) {
        base.OnRender(d);
        double scale=Math.Min(ActualWidth/170,ActualHeight/78);
        if(scale<=0) return;
        d.PushTransform(new TranslateTransform((ActualWidth-170*scale)/2,(ActualHeight-78*scale)/2));
        d.PushTransform(new ScaleTransform(scale,scale));
        for(int i=0;i<12;i++) R(d,Dim,5+i*14,74,1,1);
        if(Scene==0) Cow(d); else if(Scene==1) Orbit(d); else Scope(d);
        d.Pop();d.Pop();
    }
    private void Cow(DrawingContext d) {
        // Stepped contours and square pixels keep the cow legible at device scale.
        d.DrawEllipse(null,new Pen(Gold,1),new Point(143,15),7,7);
        for(int i=0;i<9;i++) { double x=(i*23-Phase*5)%180; if(x<0)x+=180; R(d,Mint,x,68,3,1); if(i%3==0)R(d,Mint,x+1,66,1,2); }
        double hop=EffectRemaining>0 ? -Math.Abs(Math.Sin(Phase*7))*8 : Math.Sin(Phase*2)*0.6;
        d.PushTransform(new TranslateTransform(0,hop));
        double step=Math.Sin(Phase*5)>0?2:0;
        R(d,Cream,37+step,53,6,12-step);R(d,Dark,37+step,63-step,7,3);
        R(d,Mint,51-step,53,5,11);R(d,Dark,51-step,63,6,3);
        R(d,Mint,81+step,53,5,11);R(d,Dark,81+step,63,6,3);
        R(d,Cream,93-step,52,6,13-step);R(d,Dark,93-step,63-step,7,3);
        R(d,Cream,32,30,70,23);R(d,Cream,36,26,61,31);R(d,Cream,96,31,10,18);
        R(d,Dark,43,26,18,10);R(d,Dark,47,33,20,9);R(d,Dark,78,39,15,16);R(d,Dark,85,34,13,10);
        R(d,Pink,62,56,12,3);R(d,Pink,65,59,2,3);R(d,Pink,71,59,2,3);
        Line(d,Cream,32,31,25,30,2);Line(d,Cream,25,30,22,39+step,2);R(d,Dark,19,38+step,5,5);
        R(d,Cream,101,21,25,29);R(d,Cream,98,27,31,16);
        R(d,Cream,94,23,8,5);R(d,Pink,95,25,5,2);R(d,Cream,126,23,7,5);R(d,Pink,127,25,5,2);
        R(d,Gold,102,16,3,7);R(d,Gold,123,16,3,7);R(d,Cream,105,20,18,4);
        R(d,Dark,102,25,10,8);R(d,Dark,103,31,6,7);
        bool blink=((int)(Phase*5)%27)==0;
        R(d,blink?Dark:Cream,106,30,2,blink?1:3);R(d,Dark,120,30,2,blink?1:3);
        R(d,Pink,100,41,29,10);R(d,Pink,104,50,21,3);R(d,Dark,106,45,3,3);R(d,Dark,121,45,3,3);
        d.Pop();
        if(EffectRemaining>0) {
            for(int i=0;i<3;i++) { double y=10-(Phase*10+i*7)%16; double x=45+i*17;
                R(d,Pink,x,y,3,3);R(d,Pink,x+5,y,3,3);R(d,Pink,x,y+3,8,3);R(d,Pink,x+2,y+6,4,2);R(d,Pink,x+3,y+8,2,2);
            }
        }
    }
    private void Orbit(DrawingContext d) {
        for(int i=0;i<23;i++) { double x=(i*47+11)%166,y=(i*31+7)%69; R(d,i%3==0?Mint:Dim,x,y,1,1); }
        d.DrawEllipse(null,new Pen(Dim,1),new Point(84,38),63,25);
        d.DrawEllipse(null,new Pen(Mint,0.8),new Point(84,38),47,18);
        d.DrawEllipse(Cream,null,new Point(84,38),16,16);
        d.DrawEllipse(Dark,null,new Point(90,34),13,14);
        d.DrawEllipse(null,new Pen(Orange,1.5),new Point(84,38),26,7);
        for(int i=0;i<3;i++) { double a=Phase*(0.7+i*.25)+i*2.1; double x=84+Math.Cos(a)*(47+i*8),y=38+Math.Sin(a)*(18+i*3.5); d.DrawEllipse(i==0?Cyan:Gold,null,new Point(x,y),2.5,2.5); }
        if(EffectRemaining>0) {double x=(Phase*70)%220-30; Line(d,Pink,x-22,12,x,23,2);d.DrawEllipse(Cream,null,new Point(x,23),3,3);}
    }
    private void Scope(DrawingContext d) {
        for(int x=5;x<170;x+=16) d.DrawLine(GridPen,new Point(x,7),new Point(x,66));
        for(int y=7;y<70;y+=12) d.DrawLine(GridPen,new Point(5,y),new Point(165,y));
        for(int i=1;i<159;i++) {
            double amp=EffectRemaining>0?24:15;
            double a=(i-1)*.065+Phase*2,b=i*.065+Phase*2;
            d.DrawLine(CyanPen,new Point(i+4,35+Math.Sin(a)*amp),new Point(i+5,35+Math.Sin(b)*amp));
            d.DrawLine(GoldPen,new Point(i+4,35+Math.Sin(a*1.7+Phase)*9),new Point(i+5,35+Math.Sin(b*1.7+Phase)*9));
        }
        double cursor=5+(Phase*23)%158;Line(d,Mint,cursor,7,cursor,66,.6);
    }
}

