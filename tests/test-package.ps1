param([string]$ExePath=(Join-Path $PSScriptRoot '..\dist\LV-01.exe'))
$ErrorActionPreference='Stop'
$ExePath=(Resolve-Path -LiteralPath $ExePath).Path
$root=Split-Path $PSScriptRoot -Parent
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('LV01-package-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
function Assert { param($Condition,[string]$Name) if(-not $Condition){throw ('FAIL '+$Name)}; 'PASS '+$Name }
function Invoke-Package {
    $process=Start-Process -FilePath $ExePath -ArgumentList @('--smoke-test','--test-data',('"'+$testRoot+'"'),'--preview',('"'+(Join-Path $testRoot 'preview.png')+'"')) -PassThru
    if(-not $process.WaitForExit(30000)){throw 'Package smoke test timed out.'}
    if($process.ExitCode -ne 0){throw (Get-Content (Join-Path $testRoot 'last-error.log') -Raw)}
}
try {
    Invoke-Package
    Assert ((Get-Content (Join-Path $testRoot 'self-test.log') -Raw) -match 'UI startup, design interactions and render: OK') 'standalone EXE passes native UI tests'
    Assert ((Get-Item (Join-Path $testRoot 'preview.png')).Length -gt 1000) 'standalone EXE renders the LV-01 window'
    $appRoot=Get-ChildItem (Join-Path $testRoot 'app') -Directory | Select-Object -First 1 -ExpandProperty FullName
    Assert ((Get-FileHash (Join-Path $appRoot 'LICENSE')).Hash -eq (Get-FileHash (Join-Path $root 'LICENSE')).Hash) 'MIT license is embedded in the executable'
    Assert (-not (Test-Path (Join-Path $testRoot '.lid-vibe-restore.json'))) 'preview does not create a recovery journal'
    $journal=Join-Path $testRoot '.lid-vibe-restore.json'; $prefs=Join-Path $testRoot '.lid-vibe-preferences.json'
    [IO.File]::WriteAllText($journal,'{"test":"preserve recovery across extraction"}')
    [IO.File]::WriteAllText($prefs,'{"Theme":"Dark","Accent":"Mint"}')
    $journalHash=(Get-FileHash $journal).Hash; $prefsHash=(Get-FileHash $prefs).Hash
    [IO.File]::WriteAllText((Join-Path $appRoot 'lid-vibe-panel.xaml'),'damaged cached file')
    Invoke-Package
    Assert ((Get-FileHash (Join-Path $appRoot 'lid-vibe-panel.xaml')).Hash -eq (Get-FileHash (Join-Path $root 'src\lid-vibe-panel.xaml')).Hash) 'next launch repairs damaged cached app files'
    Assert ((Get-FileHash $journal).Hash -eq $journalHash -and (Get-FileHash $prefs).Hash -eq $prefsHash) 'extraction and preview preserve recovery and preferences'
    $icon=[IO.File]::ReadAllBytes((Join-Path $appRoot 'lid-vibe.ico'))
    Assert ([BitConverter]::ToUInt16($icon,4) -eq 7) 'miniature device icon has seven Windows sizes'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead((Join-Path $root 'dist\LV-01-v0.1.0-windows-x64.zip'))
    try { $names=@($zip.Entries | ForEach-Object {$_.FullName} | Sort-Object); Assert (($names -join ',') -eq 'LICENSE,LV-01.exe,START-HERE.txt') 'shareable zip contains only the app, license and guide' } finally {$zip.Dispose()}
    '8 package checks passed; no real power changes.'
} finally {
    $absolute=[IO.Path]::GetFullPath($testRoot)
    $tempPrefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
    if(-not $absolute.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $absolute -Leaf) -notlike 'LV01-package-*'){throw 'Refusing cleanup outside the package test folder.'}
    Remove-Item -LiteralPath $absolute -Recurse -Force
}
