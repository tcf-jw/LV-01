# FIX window: restart stuck Windows shell parts, and end or restart your own apps.
# Never calls the power worker or edits power settings.
$script:fixWindow=$null; $script:fixTimer=$null; $script:fixArmTimer=$null; $script:fixArmed=''
$script:fixRows=@(); $script:fixButtons=@{}; $script:fixPending=@{}
$script:fixPaths=@{}; $script:fixNames=@{}; $script:fixLastCpu=@{}; $script:fixLastSample=$null
$script:fixSession=[Diagnostics.Process]::GetCurrentProcess().SessionId
$script:fixGrace=[timespan]::FromSeconds(3)
$script:fixShellParts=@(
    [pscustomobject]@{ Key='Search'; Label='Search'; Process='SearchHost' },
    [pscustomobject]@{ Key='Start'; Label='Start menu'; Process='StartMenuExperienceHost' },
    [pscustomobject]@{ Key='Explorer'; Label='Taskbar & File Explorer'; Process='explorer' },
    [pscustomobject]@{ Key='Notifications'; Label='Notifications'; Process='ShellExperienceHost' },
    [pscustomobject]@{ Key='Keyboard'; Label='Emoji & touch keyboard'; Process='TextInputHost' }
)
# Process boundary. Smoke and preview modes swap these for fakes, so tests never end real processes.
$script:fixList={ Get-Process }
$script:fixPathOf={ param($Process) try { $Process.Path } catch { $null } }
$script:fixClose={ param($Process) [void]$Process.CloseMainWindow() }
$script:fixStop={ param($Process) $Process.Kill() }
$script:fixStart={ param([string]$Path) Start-Process -FilePath $Path | Out-Null }
$script:fixWait={ param([int]$Milliseconds) Start-Sleep -Milliseconds $Milliseconds }

function Get-FixAppName {
    param([string]$Path)
    if (-not $script:fixNames.ContainsKey($Path)) {
        $name=$null
        try { $name=[Diagnostics.FileVersionInfo]::GetVersionInfo($Path).FileDescription } catch { }
        if (-not $name -or -not $name.Trim()) { $name=[IO.Path]::GetFileNameWithoutExtension($Path) }
        $script:fixNames[$Path]=$name.Trim()
    }
    return $script:fixNames[$Path]
}

function Test-FixOwnApp {
    param($Process,[string]$Path)
    # Without admin rights Windows hides the path of system and other-user processes, so they drop out here.
    return $Process.Id -ne $PID -and $Process.SessionId -eq $script:fixSession -and $Path -and
        -not $Path.StartsWith($env:WINDIR.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)
}

function Get-FixAppRows {
    param([int]$Top=8)
    $now=[datetime]::UtcNow
    $elapsed=if ($script:fixLastSample) { ($now-$script:fixLastSample).TotalSeconds } else { 0 }
    $seen=@{}; $groups=@{}
    foreach ($process in @(& $script:fixList)) {
        $seen[$process.Id]=$true
        # A process keeps its image path for life; caching it keeps refreshes cheap.
        if (-not $script:fixPaths.ContainsKey($process.Id)) { $script:fixPaths[$process.Id]=& $script:fixPathOf $process }
        $path=$script:fixPaths[$process.Id]
        if (-not (Test-FixOwnApp $process $path)) { continue }
        if (-not $groups.ContainsKey($path)) {
            $groups[$path]=[pscustomobject]@{ Path=$path; Name=(Get-FixAppName $path); Cpu=0.0; Memory=[long]0; Responding=$true; Processes=0; Percent=$null }
        }
        $row=$groups[$path]
        $row.Processes++; $row.Cpu+=[double]$process.CPU; $row.Memory+=[long]$process.WorkingSet64
        if (-not $process.Responding) { $row.Responding=$false }
    }
    foreach ($id in @($script:fixPaths.Keys)) { if (-not $seen.ContainsKey($id)) { $script:fixPaths.Remove($id) } }
    foreach ($row in $groups.Values) {
        if ($elapsed -gt 0 -and $script:fixLastCpu.ContainsKey($row.Path)) {
            $row.Percent=[Math]::Max(0,($row.Cpu-$script:fixLastCpu[$row.Path])/$elapsed/[Environment]::ProcessorCount*100)
        }
    }
    $script:fixLastCpu=@{}; foreach ($row in $groups.Values) { $script:fixLastCpu[$row.Path]=$row.Cpu }
    $script:fixLastSample=$now
    # Not responding first, then busiest; the first sample has no CPU rate yet, so memory breaks ties.
    return @($groups.Values | Sort-Object @{e={$_.Responding}}, @{e={if ($null -eq $_.Percent) {-1} else {$_.Percent}};Descending=$true}, @{e={$_.Memory};Descending=$true} | Select-Object -First $Top)
}

function Get-FixAppProcesses {
    param([string]$Path)
    $name=[IO.Path]::GetFileNameWithoutExtension($Path)
    # Read paths fresh: an action must never hit a reused process ID from the cache.
    return @(& $script:fixList | Where-Object { $_.ProcessName -eq $name } | Where-Object { $own=& $script:fixPathOf $_; (Test-FixOwnApp $_ $own) -and $own -eq $Path })
}

function Stop-FixProcesses {
    param([object[]]$Processes)
    $denied=0
    foreach ($process in $Processes) {
        try { & $script:fixStop $process }
        catch {
            $problem=$_.Exception
            while ($problem.InnerException -and -not ($problem -is [ComponentModel.Win32Exception])) { $problem=$problem.InnerException }
            # A process that already exited is fine; only a refusal counts.
            if ($problem -is [ComponentModel.Win32Exception] -or $problem -is [UnauthorizedAccessException]) { $denied++ }
        }
    }
    return $denied
}

function Restart-FixShellPart {
    param([string]$Key)
    $part=$script:fixShellParts | Where-Object { $_.Key -eq $Key }
    if (-not $part) { throw "Unknown Windows part: $Key" }
    $old=@(& $script:fixList | Where-Object { $_.ProcessName -eq $part.Process -and $_.SessionId -eq $script:fixSession })
    if (-not $old.Count) { return 'NotRunning' }
    if ((Stop-FixProcesses $old) -gt 0) { return 'NeedsAdmin' }
    if ($part.Key -eq 'Explorer') {
        # Windows normally relaunches the shell; a second explorer.exe would only open a folder window.
        $oldIds=@($old | ForEach-Object { $_.Id })
        for ($i=0; $i -lt 12; $i++) {
            & $script:fixWait 250
            if (@(& $script:fixList | Where-Object { $_.ProcessName -eq 'explorer' -and $_.SessionId -eq $script:fixSession -and $oldIds -notcontains $_.Id }).Count) { return 'Restarted' }
        }
        & $script:fixStart (Join-Path $env:WINDIR 'explorer.exe')
    }
    return 'Restarted'
}

function Request-FixAppClose {
    param([string]$Path)
    $processes=@(Get-FixAppProcesses $Path)
    if (-not $processes.Count) { return 'Gone' }
    # Hung or windowless processes cannot answer a polite close, so the caller ends them straight away.
    $polite=@($processes | Where-Object { $_.Responding -and $_.MainWindowHandle -ne [IntPtr]::Zero })
    if (-not $polite.Count -or @($processes | Where-Object { -not $_.Responding }).Count) { return 'Force' }
    foreach ($process in $polite) { try { & $script:fixClose $process } catch { } }
    return 'Waiting'
}

function Stop-FixApp {
    param([string]$Path)
    if ((Stop-FixProcesses (Get-FixAppProcesses $Path)) -gt 0) { return 'NeedsAdmin' }
    return 'Ended'
}

function Start-FixApp {
    param([string]$Path)
    # No original arguments are replayed; packaged Store apps may refuse a direct launch.
    try { & $script:fixStart $Path; return 'Started' } catch { return 'StartFailed' }
}

function Format-FixMemory {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return '{0:0.0}GB' -f ($Bytes/1GB) }
    return '{0:0}MB' -f ($Bytes/1MB)
}

function Show-FixResult {
    param([string]$Title,[string]$Detail)
    if ($Title.Length -gt 24) { $Title=$Title.Substring(0,24) }
    if ($script:fixWindow) { $script:fixWindow.FindName('FixNote').Text="$Title. $Detail" }
    # Shares the media notice slot: two seconds on the display, and power warnings keep priority.
    $script:mediaTitle=$Title; $script:mediaNotice=$Detail
    $script:mediaTimer.Stop(); $script:mediaTimer.Start()
    Refresh-DeviceDisplay
}

function Complete-FixApp {
    param([string]$Path,[bool]$Restart)
    if ($script:fixPending.ContainsKey($Path)) { $script:fixPending[$Path].Stop(); $script:fixPending.Remove($Path) }
    $name=(Get-FixAppName $Path).ToUpperInvariant()
    if ((Stop-FixApp $Path) -eq 'NeedsAdmin') { Show-FixResult 'NEEDS ADMIN' "$(Get-FixAppName $Path) runs with higher rights. LV-01 can't end it." }
    elseif (-not $Restart) { Show-FixResult "$name ENDED" 'Closed. Unsaved work in it is lost.' }
    elseif ((Start-FixApp $Path) -eq 'Started') { Show-FixResult "$name RESTARTED" 'Ended and opened again.' }
    else { Show-FixResult "$name ENDED" 'Could not reopen it. Open it from Start.' }
    if ($script:fixWindow) { Update-FixRows -Resample }
}

function Invoke-FixApp {
    param([string]$Path,[bool]$Restart)
    if ($script:fixPending.ContainsKey($Path)) { return }
    $request=Request-FixAppClose $Path
    if ($request -eq 'Gone') { Show-FixResult "$((Get-FixAppName $Path).ToUpperInvariant()) GONE" 'It had already closed.'; Update-FixRows -Resample; return }
    if ($request -eq 'Force') { Complete-FixApp $Path $Restart; return }
    $grace=[Windows.Threading.DispatcherTimer]::new()
    $grace.Interval=$script:fixGrace
    $grace.Tag=[pscustomobject]@{ Path=$Path; Restart=$Restart }
    $grace.Add_Tick({ param($sender,$eventArgs) $sender.Stop(); Complete-FixApp $sender.Tag.Path $sender.Tag.Restart })
    $script:fixPending[$Path]=$grace
    $grace.Start()
    Update-FixRows
}

function Invoke-FixButton {
    param([string]$Tag)
    $action,$target=$Tag.Split([char[]]@('|'),2)
    # Explorer closes open folders and apps can lose work, so those take a second click.
    if (($action -ne 'Shell' -or $target -eq 'Explorer') -and $script:fixArmed -ne $Tag) {
        $script:fixArmed=$Tag; $script:fixArmTimer.Stop(); $script:fixArmTimer.Start()
        Update-FixRows; return
    }
    $script:fixArmed=''; $script:fixArmTimer.Stop()
    if ($action -eq 'Shell') {
        $label=($script:fixShellParts | Where-Object { $_.Key -eq $target }).Label.ToUpperInvariant()
        switch (Restart-FixShellPart $target) {
            'NotRunning' { Show-FixResult "$label READY" 'It was not running. Windows starts it when needed.' }
            'NeedsAdmin' { Show-FixResult 'NEEDS ADMIN' 'Windows refused. Sign out and back in instead.' }
            default { Show-FixResult "$label RESTARTED" $(if ($target -eq 'Explorer') { 'Taskbar is back. Reopen any folders you need.' } else { 'Windows relaunches it on its own.' }) }
        }
        Update-FixRows
    } else { Invoke-FixApp $target ($action -eq 'Restart') }
}

function New-FixButton {
    param([string]$Text,[string]$Tag,[string]$Name)
    $button=[Windows.Controls.Button]::new()
    $button.Content=if ($script:fixArmed -eq $Tag) { 'Sure?' } else { $Text }
    $button.Tag=$Tag; $button.MinWidth=56; $button.Height=22; $button.Margin='4,0,0,0'; $button.FontSize=11
    $button.SetValue([Windows.Automation.AutomationProperties]::NameProperty,"$Text $Name")
    $button.Add_Click({ param($sender,$eventArgs) Invoke-FixButton ([string]$sender.Tag) })
    $script:fixButtons[$Tag]=$button
    return $button
}

function New-FixRow {
    param([string]$Label,[string]$Stats,[bool]$Alert,[object[]]$Buttons)
    $grid=[Windows.Controls.Grid]::new(); $grid.Margin='0,2'
    foreach ($width in @('*','Auto','Auto')) { $column=[Windows.Controls.ColumnDefinition]::new(); $column.Width=[Windows.GridLengthConverter]::new().ConvertFromString($width); $grid.ColumnDefinitions.Add($column) }
    $name=[Windows.Controls.TextBlock]::new(); $name.Text=$Label; $name.VerticalAlignment='Center'; $name.TextTrimming='CharacterEllipsis'; $name.FontSize=12
    if ($Alert) { $name.Foreground=New-DeviceBrush '#C0412E'; $name.FontWeight='SemiBold' }
    $stat=[Windows.Controls.TextBlock]::new(); $stat.Text=$Stats; $stat.FontFamily='Consolas'; $stat.FontSize=10; $stat.VerticalAlignment='Center'; $stat.Margin='6,0,2,0'
    if ($Alert) { $stat.Foreground=New-DeviceBrush '#C0412E' }
    $keys=[Windows.Controls.StackPanel]::new(); $keys.Orientation='Horizontal'
    foreach ($button in $Buttons) { [void]$keys.Children.Add($button) }
    [Windows.Controls.Grid]::SetColumn($stat,1); [Windows.Controls.Grid]::SetColumn($keys,2)
    foreach ($child in @($name,$stat,$keys)) { [void]$grid.Children.Add($child) }
    return $grid
}

function Update-FixRows {
    param([switch]$Resample)
    if (-not $script:fixWindow) { return }
    if ($Resample) { try { $script:fixRows=@(Get-FixAppRows) } catch { $script:fixRows=@(); $script:fixWindow.FindName('FixNote').Text='Could not read running apps.' } }
    $script:fixButtons=@{}
    $shell=$script:fixWindow.FindName('ShellRows'); $shell.Children.Clear()
    foreach ($part in $script:fixShellParts) { [void]$shell.Children.Add((New-FixRow $part.Label '' $false @(New-FixButton 'Restart' "Shell|$($part.Key)" $part.Label))) }
    $apps=$script:fixWindow.FindName('AppRows'); $apps.Children.Clear()
    foreach ($row in $script:fixRows) {
        $cpu=if ($null -eq $row.Percent) { '  --' } else { '{0,3:0}%' -f $row.Percent }
        if ($script:fixPending.ContainsKey($row.Path)) {
            $closing=[Windows.Controls.TextBlock]::new(); $closing.Text='CLOSING'; $closing.FontFamily='Consolas'; $closing.FontSize=10; $closing.VerticalAlignment='Center'; $closing.Margin='4,0,0,0'
            [void]$apps.Children.Add((New-FixRow $row.Name "$cpu $(Format-FixMemory $row.Memory)" $false @($closing)))
            continue
        }
        $label=if ($row.Responding) { $row.Name } else { "$($row.Name)  NOT RESPONDING" }
        [void]$apps.Children.Add((New-FixRow $label ("{0} {1,6}" -f $cpu,(Format-FixMemory $row.Memory)) (-not $row.Responding) @((New-FixButton 'Restart' "Restart|$($row.Path)" $row.Name),(New-FixButton 'End' "End|$($row.Path)" $row.Name))))
    }
    if (-not $script:fixRows.Count) { $empty=[Windows.Controls.TextBlock]::new(); $empty.Text='No apps found.'; $empty.FontSize=11; [void]$apps.Children.Add($empty) }
}

function Show-DeviceFix {
    if ($script:fixWindow) { $script:fixWindow.Activate() | Out-Null; return }
    $fixMarkup=@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework"
 Title="LV-01 fix" Width="400" Height="540" WindowStyle="None" ResizeMode="NoResize" ShowInTaskbar="False" WindowStartupLocation="CenterOwner" FontFamily="Segoe UI">
 <shell:WindowChrome.WindowChrome><shell:WindowChrome CaptionHeight="43" ResizeBorderThickness="0" CornerRadius="8" GlassFrameThickness="0" UseAeroCaptionButtons="False"/></shell:WindowChrome.WindowChrome>
 <Border BorderBrush="#898B80" BorderThickness="1" Padding="20,14">
  <DockPanel>
   <Grid DockPanel.Dock="Top" Margin="0,0,0,12"><TextBlock Text="Fix" FontSize="18" FontWeight="Light"/><Button x:Name="FixDone" Content="&#xD7;" Width="25" Height="24" HorizontalAlignment="Right" Background="Transparent" BorderThickness="0" FontSize="18" shell:WindowChrome.IsHitTestVisibleInChrome="True" AutomationProperties.Name="Close fix window"/></Grid>
   <TextBlock DockPanel.Dock="Top" Text="WINDOWS" FontFamily="Consolas" FontSize="9" Margin="0,0,0,3"/>
   <StackPanel x:Name="ShellRows" DockPanel.Dock="Top" Margin="0,0,0,14"/>
   <Grid DockPanel.Dock="Top" Margin="0,0,0,3"><TextBlock Text="YOUR APPS" FontFamily="Consolas" FontSize="9"/><TextBlock Text="CPU    RAM" FontFamily="Consolas" FontSize="9" HorizontalAlignment="Right" Margin="0,0,128,0"/></Grid>
   <TextBlock x:Name="FixNote" DockPanel.Dock="Bottom" FontSize="10" TextWrapping="Wrap" Margin="0,8,0,0" Text="Restart and End ask for a second click. Unsaved work in an ended app is lost."/>
   <StackPanel x:Name="AppRows"/>
  </DockPanel>
 </Border>
</Window>
'@
    $script:fixWindow=[Windows.Markup.XamlReader]::Parse($fixMarkup)
    $script:fixWindow.Owner=$window
    Apply-DevicePalette
    $script:fixWindow.FindName('FixDone').Add_Click({ $script:fixWindow.Close() })
    $script:fixWindow.Add_PreviewKeyDown({param($sender,$eventArgs) if ($eventArgs.Key -eq 'Escape') { $sender.Close(); $eventArgs.Handled=$true }})
    $script:fixWindow.Add_Closed({
        $script:fixTimer.Stop(); $script:fixArmTimer.Stop(); $script:fixArmed=''
        $script:fixWindow=$null
    })
    $script:fixLastSample=$null
    Update-FixRows -Resample
    $script:fixTimer.Start()
    $script:fixWindow.Show()
}

function Initialize-DeviceFix {
    $script:fixTimer=[Windows.Threading.DispatcherTimer]::new()
    $script:fixTimer.Interval=[timespan]::FromSeconds(3)
    $script:fixTimer.Add_Tick({ Update-FixRows -Resample })
    $script:fixArmTimer=[Windows.Threading.DispatcherTimer]::new()
    $script:fixArmTimer.Interval=[timespan]::FromSeconds(3)
    $script:fixArmTimer.Add_Tick({ $script:fixArmTimer.Stop(); $script:fixArmed=''; Update-FixRows })
    if ($isTest) {
        $script:fixLog=[Collections.Generic.List[string]]::new()
        $script:fixFakes=@(
            [pscustomobject]@{ Id=1001; ProcessName='SearchHost'; Path='C:\Windows\SystemApps\SearchHost.exe'; CPU=1.0; WorkingSet64=140MB; Responding=$true; MainWindowHandle=[IntPtr]::Zero; SessionId=$script:fixSession },
            [pscustomobject]@{ Id=1002; ProcessName='explorer'; Path='C:\Windows\explorer.exe'; CPU=9.0; WorkingSet64=380MB; Responding=$true; MainWindowHandle=[IntPtr]::new(1); SessionId=$script:fixSession },
            [pscustomobject]@{ Id=2001; ProcessName='chrome'; Path='C:\Apps\Chrome\chrome.exe'; CPU=40.0; WorkingSet64=900MB; Responding=$true; MainWindowHandle=[IntPtr]::new(1); SessionId=$script:fixSession },
            [pscustomobject]@{ Id=2002; ProcessName='chrome'; Path='C:\Apps\Chrome\chrome.exe'; CPU=12.0; WorkingSet64=300MB; Responding=$true; MainWindowHandle=[IntPtr]::Zero; SessionId=$script:fixSession },
            [pscustomobject]@{ Id=3001; ProcessName='Notes'; Path='C:\Apps\Notes.exe'; CPU=2.0; WorkingSet64=120MB; Responding=$false; MainWindowHandle=[IntPtr]::new(1); SessionId=$script:fixSession },
            [pscustomobject]@{ Id=4001; ProcessName='Hidden'; Path=$null; CPU=5.0; WorkingSet64=50MB; Responding=$true; MainWindowHandle=[IntPtr]::Zero; SessionId=$script:fixSession },
            [pscustomobject]@{ Id=$PID; ProcessName='LV-01'; Path='C:\Apps\LV-01.exe'; CPU=3.0; WorkingSet64=90MB; Responding=$true; MainWindowHandle=[IntPtr]::new(1); SessionId=$script:fixSession },
            [pscustomobject]@{ Id=5001; ProcessName='Other'; Path='C:\Apps\Other.exe'; CPU=3.0; WorkingSet64=90MB; Responding=$true; MainWindowHandle=[IntPtr]::new(1); SessionId=($script:fixSession+1) }
        )
        $script:fixList={ $script:fixFakes }
        $script:fixPathOf={ param($Process) $Process.Path }
        $script:fixClose={ param($Process) $script:fixLog.Add('close:'+$Process.Id) }
        $script:fixStop={ param($Process) $script:fixLog.Add('stop:'+$Process.Id); $script:fixFakes=@($script:fixFakes | Where-Object { $_.Id -ne $Process.Id }) }
        $script:fixStart={ param([string]$Path) $script:fixLog.Add('start:'+$Path) }
        $script:fixWait={ param([int]$Milliseconds) }
    }
    $window.FindName('FixButton').Add_Click({ $script:helpPinned=$false; Set-HelpVisible $false; Show-DeviceFix })
}

function Test-DeviceFix {
    if (-not $isTest) { throw 'Fix tests require smoke/preview mode.' }
    $priorState=$script:state; $priorDetail=$script:lastDetail; $priorPaused=$script:autoPaused
    $priorFakes=$script:fixFakes; $priorStop=$script:fixStop
    try {
        $script:fixLog.Clear()
        $window.FindName('FixButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        if (-not $script:fixWindow -or -not $script:fixWindow.IsVisible) { throw 'Fix window did not open.' }
        if ($script:fixWindow.FindName('ShellRows').Children.Count -ne 5) { throw 'Fix window must list five Windows parts.' }
        $names=@($script:fixRows | ForEach-Object { $_.Name })
        if (($names -join ',') -ne 'Notes,chrome') { throw "App rows wrong: $($names -join ',')" }
        if ($script:fixRows[1].Processes -ne 2 -or $script:fixRows[1].Memory -ne 1200MB) { throw 'Processes of one app were not grouped.' }

        $script:fixButtons['Shell|Search'].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        if ($script:fixLog -notcontains 'stop:1001' -or $statusTitle.Text -ne 'SEARCH RESTARTED') { throw 'Search restart failed or had no feedback.' }
        $script:fixButtons['Shell|Explorer'].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        if ($script:fixLog -contains 'stop:1002' -or $script:fixButtons['Shell|Explorer'].Content -ne 'Sure?') { throw 'Explorer restart skipped its confirm step.' }
        $script:fixButtons['Shell|Explorer'].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        if ($script:fixLog -notcontains 'stop:1002' -or $script:fixLog -notcontains ('start:'+(Join-Path $env:WINDIR 'explorer.exe'))) { throw 'Explorer was not relaunched after it stayed gone.' }

        $chrome='C:\Apps\Chrome\chrome.exe'
        $script:fixButtons["End|$chrome"].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        if ($script:fixLog -match '^close:200') { throw 'End skipped its confirm step.' }
        $script:fixButtons["End|$chrome"].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        if ($script:fixLog -notcontains 'close:2001' -or $script:fixLog -contains 'close:2002' -or -not $script:fixPending.ContainsKey($chrome)) { throw 'End did not ask the app window to close first.' }
        Complete-FixApp $chrome $false
        if ($script:fixLog -notcontains 'stop:2001' -or $script:fixLog -notcontains 'stop:2002' -or $script:fixLog -contains "start:$chrome" -or $script:fixPending.Count) { throw 'End did not finish closing the app.' }

        $notes='C:\Apps\Notes.exe'
        $script:fixButtons["Restart|$notes"].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        $script:fixButtons["Restart|$notes"].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        if ($script:fixLog -contains 'close:3001' -or $script:fixLog -notcontains 'stop:3001' -or $script:fixLog -notcontains "start:$notes") { throw "Hung app was not force-restarted. Log: $($script:fixLog -join ' ')" }

        $script:fixFakes=@([pscustomobject]@{ Id=6001; ProcessName='SearchHost'; Path='C:\Windows\SystemApps\SearchHost.exe'; CPU=1.0; WorkingSet64=1MB; Responding=$true; MainWindowHandle=[IntPtr]::Zero; SessionId=$script:fixSession })
        $script:fixStop={ param($Process) throw [ComponentModel.Win32Exception]::new(5) }
        Invoke-FixButton 'Shell|Search'
        if ($statusTitle.Text -ne 'NEEDS ADMIN') { throw 'Access denied was not reported.' }
        Set-VisualState 'Warning' 'Recovery still pending'
        Invoke-FixButton 'Shell|Start'
        if ($statusTitle.Text -ne 'CHECK SETTINGS') { throw 'Fix feedback hid a power warning.' }
        if ($script:autoPaused -ne $priorPaused) { throw 'Fix actions changed automatic power behavior.' }

        $key=[Windows.Input.KeyEventArgs]::new([Windows.Input.Keyboard]::PrimaryDevice,[Windows.PresentationSource]::FromVisual($script:fixWindow),0,[Windows.Input.Key]::Escape)
        $key.RoutedEvent=[Windows.Input.Keyboard]::PreviewKeyDownEvent
        $script:fixWindow.RaiseEvent($key)
        if ($script:fixWindow -or $script:fixTimer.IsEnabled) { throw 'Escape did not close the fix window and stop its refresh.' }
    } finally {
        if ($script:fixWindow) { $script:fixWindow.Close() }
        $script:fixFakes=$priorFakes; $script:fixStop=$priorStop
        Clear-MediaNotice; Set-VisualState $priorState $priorDetail
    }
    'Fix interactions: OK (Windows parts, confirm, polite close, hung apps, admin refusal, warnings)'
}
