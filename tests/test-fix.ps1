$ErrorActionPreference='Stop'
$fixScript=Join-Path $PSScriptRoot '..\src\lid-vibe-fix.ps1'
. $fixScript
function Assert { param($Condition,[string]$Name) if(-not $Condition){throw ('FAIL '+$Name)}; 'PASS '+$Name }
function New-Fake { param([int]$Id,[string]$Name,[string]$Path,[double]$Cpu=1,[long]$Memory=10MB,[bool]$Responding=$true,[bool]$Window=$false,[int]$Session=$script:fixSession)
    [pscustomobject]@{ Id=$Id; ProcessName=$Name; Path=$Path; CPU=$Cpu; WorkingSet64=$Memory; Responding=$Responding; MainWindowHandle=$(if ($Window) {[IntPtr]::new(1)} else {[IntPtr]::Zero}); SessionId=$Session }
}
function Use-Fakes { param([object[]]$Processes)
    $script:fixFakes=$Processes; $script:fixLog=[Collections.Generic.List[string]]::new()
    $script:fixPaths=@{}; $script:fixLastCpu=@{}; $script:fixLastSample=$null
    $script:fixList={ $script:fixFakes }
    $script:fixPathOf={ param($Process) $Process.Path }
    $script:fixClose={ param($Process) $script:fixLog.Add('close:'+$Process.Id) }
    $script:fixStop={ param($Process) $script:fixLog.Add('stop:'+$Process.Id); $script:fixFakes=@($script:fixFakes | Where-Object { $_.Id -ne $Process.Id }) }
    $script:fixStart={ param([string]$Path) $script:fixLog.Add('start:'+$Path) }
    $script:fixWait={ param([int]$Milliseconds) }
}
$windows=$env:WINDIR.TrimEnd('\')

Use-Fakes @(
    (New-Fake 1 'SearchHost' "$windows\SystemApps\SearchHost.exe"),
    (New-Fake 2 'chrome' 'C:\Apps\chrome.exe' 5 700MB $true $true),
    (New-Fake 3 'chrome' 'C:\Apps\chrome.exe' 5 300MB),
    (New-Fake 4 'Notes' 'C:\Apps\Notes.exe' 1 20MB $false $true),
    (New-Fake 5 'Hidden' $null),
    (New-Fake $PID 'LV-01' 'C:\Apps\LV-01.exe'),
    (New-Fake 6 'Other' 'C:\Apps\Other.exe' 1 10MB $true $true ($script:fixSession+1))
)
$rows=@(Get-FixAppRows)
Assert ((($rows | ForEach-Object Name) -join ',') -eq 'Notes,chrome') 'only own, visible, non-Windows apps are listed; hung apps first'
Assert ($rows[1].Processes -eq 2 -and $rows[1].Memory -eq 1000MB) 'processes of one app are grouped'
Assert ($null -eq $rows[0].Percent) 'first sample shows no CPU rate'
$script:fixLastSample=[datetime]::UtcNow.AddSeconds(-2)
foreach ($fake in $script:fixFakes) { if ($fake.ProcessName -eq 'chrome') { $fake.CPU+=[Environment]::ProcessorCount*0.5 } }
$rate=(@(Get-FixAppRows) | Where-Object Name -eq 'chrome').Percent
Assert ($rate -gt 45 -and $rate -lt 55) 'CPU rate is a share of the whole machine'
Use-Fakes @(1..12 | ForEach-Object { New-Fake (100+$_) "App$_" "C:\Apps\App$_.exe" 1 ($_*1MB) })
Assert (@(Get-FixAppRows).Count -eq 8 -and (@(Get-FixAppRows)[0]).Name -eq 'App12') 'list keeps the top eight'

Use-Fakes @((New-Fake 10 'explorer' "$windows\explorer.exe" 1 10MB $true $true))
Assert ((Restart-FixShellPart 'Explorer') -eq 'Restarted' -and ($script:fixLog -join ',') -eq "stop:10,start:$windows\explorer.exe") 'explorer is started when Windows does not relaunch it'
Use-Fakes @((New-Fake 10 'explorer' "$windows\explorer.exe" 1 10MB $true $true))
$script:fixWait={ param([int]$Milliseconds) $script:fixFakes=@(New-Fake 11 'explorer' "$windows\explorer.exe") }
Assert ((Restart-FixShellPart 'Explorer') -eq 'Restarted' -and $script:fixLog -notmatch '^start:') 'no second explorer when Windows relaunches the shell'
Use-Fakes @()
Assert ((Restart-FixShellPart 'Search') -eq 'NotRunning') 'a part that is not running is reported, not started'
Use-Fakes @((New-Fake 12 'SearchHost' "$windows\SystemApps\SearchHost.exe"))
$script:fixStop={ param($Process) throw [ComponentModel.Win32Exception]::new(5) }
Assert ((Restart-FixShellPart 'Search') -eq 'NeedsAdmin') 'access denied is reported'
$script:fixStop={ param($Process) throw [InvalidOperationException]::new('exited') }
Assert ((Restart-FixShellPart 'Search') -eq 'Restarted') 'a process that already exited is not a failure'

Use-Fakes @((New-Fake 20 'Word' 'C:\Apps\Word.exe' 1 10MB $true $true),(New-Fake 21 'Word' 'C:\Apps\Word.exe'))
Assert ((Request-FixAppClose 'C:\Apps\Word.exe') -eq 'Waiting' -and ($script:fixLog -join ',') -eq 'close:20') 'responsive windows are asked to close first'
Use-Fakes @((New-Fake 22 'Tool' 'C:\Apps\Tool.exe'))
Assert ((Request-FixAppClose 'C:\Apps\Tool.exe') -eq 'Force') 'windowless apps are ended directly'
Use-Fakes @((New-Fake 23 'Hung' 'C:\Apps\Hung.exe' 1 10MB $false $true))
Assert ((Request-FixAppClose 'C:\Apps\Hung.exe') -eq 'Force' -and -not $script:fixLog.Count) 'hung apps are ended directly'
Assert ((Request-FixAppClose 'C:\Apps\Missing.exe') -eq 'Gone') 'an app that already closed is reported'
Use-Fakes @((New-Fake $PID 'LV-01' 'C:\Apps\LV-01.exe'))
Assert ((Stop-FixApp 'C:\Apps\LV-01.exe') -eq 'Ended' -and -not $script:fixLog.Count) 'LV-01 never ends itself'
$script:fixStart={ param([string]$Path) throw 'Store apps refuse direct launch' }
Assert ((Start-FixApp 'C:\Apps\Store.exe') -eq 'StartFailed') 'a failed relaunch is reported'

# Live check against throwaway processes only: a sleeping console app compiled into a temp folder.
. $fixScript
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('LV01-fix-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$dummy=Join-Path $testRoot 'lv01-fix-dummy.exe'
try {
    Set-Content -LiteralPath (Join-Path $testRoot 'dummy.cs') -Value 'class P { static void Main() { System.Threading.Thread.Sleep(120000); } }'
    & (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe') /nologo /target:exe ('/out:'+$dummy) (Join-Path $testRoot 'dummy.cs') | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Dummy build failed.' }
    $first=Start-Process -FilePath $dummy -WindowStyle Hidden -PassThru
    $second=Start-Process -FilePath $dummy -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 500
    $row=@(Get-FixAppRows -Top 1000) | Where-Object Path -eq $dummy
    Assert ($row -and $row.Processes -eq 2) 'live processes are found and grouped'
    Assert ((Request-FixAppClose $dummy) -eq 'Force') 'live windowless app skips the polite close'
    Assert ((Stop-FixApp $dummy) -eq 'Ended' -and $first.WaitForExit(5000) -and $second.WaitForExit(5000)) 'live app is ended'
    Assert ((Start-FixApp $dummy) -eq 'Started') 'live app is started again'
    Start-Sleep -Milliseconds 500
    Assert (@(Get-FixAppProcesses $dummy).Count -eq 1) 'restarted app is running'
} finally {
    Get-Process -Name 'lv01-fix-dummy' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $dummy } | Stop-Process -Force
    Start-Sleep -Milliseconds 300
    $absolute=[IO.Path]::GetFullPath($testRoot)
    if ((Split-Path $absolute -Leaf) -notlike 'LV01-fix-*') { throw 'Refusing cleanup outside the fix test folder.' }
    Remove-Item -LiteralPath $absolute -Recurse -Force
}
'21 fix checks passed; only throwaway test processes were ended.'
