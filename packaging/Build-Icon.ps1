$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$root=Split-Path $PSScriptRoot -Parent
$markup=Get-Content -LiteralPath (Join-Path $root 'assets\app-icon.xaml') -Raw -Encoding UTF8
$visual=[Windows.Markup.XamlReader]::Parse($markup)
$visual.Measure([Windows.Size]::new(256,256)); $visual.Arrange([Windows.Rect]::new(0,0,256,256)); $visual.UpdateLayout()
$images=@()
foreach ($size in @(16,24,32,48,64,128,256)) {
    $drawing=[Windows.Media.DrawingVisual]::new()
    $context=$drawing.RenderOpen()
    $context.DrawRectangle([Windows.Media.VisualBrush]::new($visual),$null,[Windows.Rect]::new(0,0,$size,$size)); $context.Close()
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new($size,$size,96,96,[Windows.Media.PixelFormats]::Pbgra32); $bitmap.Render($drawing)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream=[IO.MemoryStream]::new(); $encoder.Save($stream)
    $images+=,@{ Size=$size; Bytes=$stream.ToArray() }; $stream.Dispose()
}
$file=[IO.File]::Create((Join-Path $root 'src\lid-vibe.ico'))
$writer=[IO.BinaryWriter]::new($file)
try {
    $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]$images.Count)
    $offset=6+16*$images.Count
    foreach ($entry in $images) {
        $dimension=if($entry.Size -eq 256){0}else{$entry.Size}
        $writer.Write([byte]$dimension);$writer.Write([byte]$dimension);$writer.Write([byte]0);$writer.Write([byte]0)
        $writer.Write([uint16]1);$writer.Write([uint16]32);$writer.Write([uint32]$entry.Bytes.Length);$writer.Write([uint32]$offset)
        $offset+=$entry.Bytes.Length
    }
    foreach ($entry in $images) { $writer.Write([byte[]]$entry.Bytes) }
} finally { $writer.Dispose(); $file.Dispose() }
[IO.File]::WriteAllBytes((Join-Path $root 'assets\app-icon.png'),$images[-1].Bytes)
'7 icon sizes built.'
