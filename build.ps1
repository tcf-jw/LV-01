param([switch]$Test)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$dist=Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$csc=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$automation=Get-ChildItem -LiteralPath (Join-Path $env:WINDIR 'Microsoft.NET\assembly\GAC_MSIL\System.Management.Automation') -Recurse -Filter System.Management.Automation.dll | Select-Object -First 1 -ExpandProperty FullName
if (-not (Test-Path $csc) -or -not $automation) { throw 'Build requires Windows, .NET Framework 4.8 and Windows PowerShell 5.1.' }
& (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -STA -File (Join-Path $root 'packaging\Build-Icon.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Icon build failed.' }
$exe=Join-Path $dist 'LV-01.exe'
$arguments=@('/nologo','/target:winexe','/platform:x64','/optimize+','/warnaserror+',('/out:'+$exe),('/reference:'+$automation),'/reference:System.Windows.Forms.dll','/reference:System.Core.dll',('/win32manifest:'+(Join-Path $root 'packaging\app.manifest')),('/win32icon:'+(Join-Path $root 'src\lid-vibe.ico')))
foreach ($name in @('lid-vibe.ps1','lid-vibe-ui.ps1','lid-vibe-design.ps1','lid-vibe-panel.xaml','lid-vibe-art.cs','lid-vibe.ico')) {
    $arguments+=('/resource:'+(Join-Path $root ('src\'+$name))+',payload.'+$name)
}
$arguments+=('/resource:'+(Join-Path $root 'LICENSE')+',payload.LICENSE')
$arguments+=(Join-Path $root 'packaging\Program.cs')
& $csc @arguments
if ($LASTEXITCODE -ne 0) { throw 'Executable build failed.' }
Copy-Item -LiteralPath (Join-Path $root 'LICENSE') -Destination $dist -Force
Copy-Item -LiteralPath (Join-Path $root 'docs\START-HERE.txt') -Destination $dist -Force
$zip=Join-Path $dist 'LV-01-v0.1.0-windows-x64.zip'
Compress-Archive -LiteralPath $exe,(Join-Path $dist 'LICENSE'),(Join-Path $dist 'START-HERE.txt') -DestinationPath $zip -Force
$checksums=@($exe,$zip) | ForEach-Object { '{0}  {1}' -f (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant(),(Split-Path $_ -Leaf) }
[IO.File]::WriteAllLines((Join-Path $dist 'SHA256SUMS.txt'),[string[]]$checksums,[Text.Encoding]::ASCII)
if ($Test) { & (Join-Path $root 'tests\test-package.ps1') -ExePath $exe }
Get-Item $exe,$zip | Select-Object Name,Length
