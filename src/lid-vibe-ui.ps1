param([switch]$ValidateOnly, [switch]$SmokeTest, [switch]$StartPaused, [string]$PreviewPath = '', [ValidateSet('Off','On','Warning')][string]$PreviewState = 'Off', [ValidateSet('Light','Dark')][string]$PreviewTheme = 'Light', [ValidateSet('Orange','Cobalt','Mint','Red','Lilac')][string]$PreviewAccent = 'Orange', [ValidateSet('Device','Guide','Hover','Settings')][string]$PreviewView = 'Device', [ValidateRange(0,2)][int]$PreviewScene = 0, [switch]$PreviewEffect, [ValidateSet(1,2)][int]$PreviewScale = 2)

$ErrorActionPreference = 'Stop'
$coreScript = Join-Path $PSScriptRoot 'lid-vibe.ps1'
$iconPath = Join-Path $PSScriptRoot 'lid-vibe.ico'
. $coreScript -LibraryOnly
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# WindowChrome preserves native dragging and the system menu beneath the custom casing.
$xaml = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'lid-vibe-panel.xaml') -Raw -Encoding UTF8

$window = [Windows.Markup.XamlReader]::Parse($xaml)
if (Test-Path -LiteralPath $iconPath) { $window.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([uri]::new($iconPath)) }
if ($ValidateOnly) { 'XAML and icon: OK'; return }

$statusTitle = $window.FindName('StatusTitle'); $statusDetail = $window.FindName('StatusDetail')
$statusDot = $window.FindName('StatusDot'); $onButton = $window.FindName('OnButton'); $offButton = $window.FindName('OffButton')
$script:monitor = $null; $script:state = 'Off'; $script:sessionId = ''; $script:errorRead = $null
$script:uiTick = 0; $script:canStart = $false
$script:lightState = ''
$script:autoPaused = [bool]$StartPaused; $script:autoFaulted = $false; $script:readySamples = 0
$isTest = $SmokeTest -or [bool]$PreviewPath
. (Join-Path $PSScriptRoot 'lid-vibe-design.ps1')

function Invoke-AutoCheck {
    param([bool]$Eligible)
    if (-not $Eligible) { $script:readySamples = 0; return }
    if ($script:autoPaused -or $script:autoFaulted -or $script:monitor -or $script:state -ne 'Off') {
        $script:readySamples = 0
        return
    }
    $script:readySamples = [Math]::Min(2, $script:readySamples + 1)
    # Two consecutive telemetry samples avoid repeated starts during short network/power dropouts.
    if ($script:readySamples -ge 2) {
        $script:readySamples = 0
        Start-AwakeMonitor
    }
}

function Update-ActivityLights {
    param([string]$State)
    $lightState = $State + ':' + [Windows.SystemParameters]::ClientAreaAnimation + ':' + $script:preferences.Motion + ':' + $script:preferences.Tempo
    if ($script:lightState -eq $lightState) { return }
    $script:lightState = $lightState
    $active = $State -in @('On','Starting','Stopping')
    for ($i = 0; $i -lt 4; $i++) {
        $led = $window.FindName('Pulse' + $i)
        $led.BeginAnimation([Windows.UIElement]::OpacityProperty, $null)
        $led.Opacity = if ($active) { 0.85 } elseif ($State -eq 'Warning') { 0.65 } else { 0.12 }
        if ($active -and $script:preferences.Motion -and [Windows.SystemParameters]::ClientAreaAnimation) {
            $pulse = [Windows.Media.Animation.DoubleAnimation]::new()
            $pulse.From = 0.16; $pulse.To = 1
            $pulse.Duration = [Windows.Duration]::new([timespan]::FromSeconds(0.9 / $script:preferences.Tempo))
            $pulse.BeginTime = [timespan]::FromSeconds($i * 0.22 / $script:preferences.Tempo)
            $pulse.AutoReverse = $true
            $pulse.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
            $led.BeginAnimation([Windows.UIElement]::OpacityProperty, $pulse)
        }
    }
    $window.FindName('SignalLabel').Text = switch ($State) {
        'On' { 'running' }; 'Starting' { 'connecting' }; 'Stopping' { 'releasing' }
        'Warning' { 'attention' }; default { 'standby' }
    }
}

function Set-VisualState {
    param([string]$State, [string]$Detail)
    $script:state = $State
    $script:lastDetail = $Detail
    $color = switch ($State) { 'On' { '#FF6B24' }; 'Warning' { '#FFB06B' }; default { '#B2B2B2' } }
    $statusDot.Fill = [Windows.Media.BrushConverter]::new().ConvertFromString($color)
    if ($State -eq 'On') { $statusDot.Fill = $window.Resources['AccentLight'] }
    Update-ActivityLights $State
    Refresh-DeviceDisplay
    $onButton.IsEnabled = $script:canStart -and ($State -in @('Off', 'Warning')) -and -not $script:monitor
    $offButton.IsEnabled = $State -ne 'Stopping'
}

function Update-Telemetry {
    try {
        $ac = Test-OnAC
        $wifi = $null -ne (Get-ConnectedWifi)
        $script:canStart = $ac -and $wifi
        $window.FindName('PowerLabel').Text = if ($ac) { 'AC' } else { 'BATTERY' }
        $window.FindName('WifiLabel').Text = if ($wifi) { 'WI-FI' } else { 'OFFLINE' }
        $window.FindName('PowerLed').Fill = [Windows.Media.BrushConverter]::new().ConvertFromString($(if ($ac) { '#3E783B' } else { '#858C7D' }))
        $window.FindName('WifiLed').Fill = [Windows.Media.BrushConverter]::new().ConvertFromString($(if ($wifi) { '#3E783B' } else { '#858C7D' }))
        $battery = [System.Windows.Forms.SystemInformation]::PowerStatus.BatteryLifePercent
        $window.FindName('BatteryLabel').Text = if ($battery -ge 0 -and $battery -le 1) { '{0:0}%' -f ($battery * 100) } else { '--%' }
        Set-VisualState $script:state $script:lastDetail
        if (-not $isTest) { Invoke-AutoCheck $script:canStart }
    } catch {
        $script:readySamples = 0
        $script:canStart = $false
        $onButton.IsEnabled = $false
        $window.FindName('PowerLabel').Text = 'Power  Unknown'
    }
}

function Show-Error {
    param([string]$Message)
    [Windows.MessageBox]::Show($window, $Message, 'LV-01', 'OK', 'Warning') | Out-Null
}

function Get-SessionStatus {
    try {
        $data = Get-Content -LiteralPath $script:statusFile -Raw -ErrorAction Stop | ConvertFrom-Json
        if ($data.Session -eq $script:sessionId) { return $data }
    } catch { }
    return $null
}

$window.FindName('MinimizeButton').Add_Click({ $window.WindowState = 'Minimized' })
$window.FindName('CloseButton').Add_Click({ $window.Close() })

function Start-AwakeMonitor {
    if ($script:monitor -or $isTest) { return }
    try {
        $script:sessionId = [guid]::NewGuid().ToString()
        $info = [Diagnostics.ProcessStartInfo]::new()
        $info.FileName = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $info.Arguments = '-NoProfile -NonInteractive -File "' + $coreScript + '" -Mode On -OwnerPid ' + $PID + ' -Session ' + $script:sessionId
        $info.UseShellExecute = $false; $info.CreateNoWindow = $true; $info.RedirectStandardError = $true
        $script:monitor = [Diagnostics.Process]::Start($info)
        $script:errorRead = $script:monitor.StandardError.ReadToEndAsync()
        Set-VisualState 'Starting' 'Checking power, Wi-Fi and your lid settings.'
    } catch {
        $script:autoFaulted = $true
        Set-VisualState 'Warning' $_.Exception.Message
    }
}

$onButton.Add_Click({
    $script:autoPaused = $false; $script:autoFaulted = $false; $script:readySamples = 0
    Start-AwakeMonitor
})

$offButton.Add_Click({
    if ($isTest) { return }
    $script:autoPaused = $true; $script:readySamples = 0
    try {
        if ($script:monitor -and -not $script:monitor.HasExited) {
            Set-Content -LiteralPath $script:stopFile -Value $script:sessionId
            Set-VisualState 'Stopping' 'Restoring your Windows settings.'
        } else {
            Invoke-LidVibe 'Off' $script:sessionId
            Set-VisualState 'Off' 'Auto is paused. Click Stay Awake to resume.'
        }
    } catch { Set-VisualState 'Warning' $_.Exception.Message }
})

$timer = [Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [timespan]::FromSeconds(1)
$timer.Add_Tick({
    try {
        $script:uiTick++
        if ($script:uiTick % 5 -eq 0) { Update-Telemetry }
        if (-not $script:monitor) { return }
        $workerState = Get-SessionStatus
        if ($script:monitor.HasExited) {
            $exitCode = $script:monitor.ExitCode
            $errorText = $script:errorRead.GetAwaiter().GetResult().Trim()
            $script:monitor.Dispose(); $script:monitor = $null
            $script:readySamples = 0
            # Recover even after abrupt worker termination; never assume process exit means cleanup succeeded.
            try { Invoke-LidVibe 'Recover' $script:sessionId }
            catch { $script:autoFaulted = $true; Set-VisualState 'Warning' $_.Exception.Message; return }
            if ($exitCode -ne 0) {
                $script:autoFaulted = $true
                $message = if ($errorText) { ($errorText -split "`r?`n")[0] } else { 'Worker stopped unexpectedly. Settings restored.' }
                Set-VisualState 'Warning' $message
            } else {
                $message = if ($workerState) { $workerState.Detail } else { 'Windows controls sleep and the lid.' }
                if ($script:autoPaused) { $message = 'Auto is paused. Click Stay Awake to resume.' }
                elseif ($message -match 'Power settings changed') {
                    $script:autoPaused = $true
                    $message = 'Power settings changed. Auto is paused.'
                }
                Set-VisualState 'Off' $message
            }
            Update-Telemetry
        } elseif ($workerState -and $script:state -ne 'Stopping') {
            if ($workerState.State -eq 'On' -and ([datetime]::UtcNow - [datetime]$workerState.UpdatedUtc).TotalSeconds -gt 15) {
                Set-VisualState 'Warning' 'Monitor is not responding. Click Turn Off.'
            } else { Set-VisualState $workerState.State $workerState.Detail }
        }
    } catch { Set-VisualState 'Warning' $_.Exception.Message }
})

$window.Add_Closing({
    $closingArgs = $_
    $script:autoPaused = $true; $script:readySamples = 0
    $timer.Stop()
    if (-not $isTest) {
        try { Invoke-LidVibe 'Off' $script:sessionId }
        catch {
            $closingArgs.Cancel = $true; $timer.Start()
            Set-VisualState 'Warning' $_.Exception.Message
            Show-Error $_.Exception.Message
        }
    }
})

$panelMutex = $null; $ownsPanel = $false
try {
    Initialize-DeviceDesign
    if (-not $isTest) {
        $panelMutex = [Threading.Mutex]::new($false, ('Local\LidVibe.Panel.' + [Environment]::UserName))
        try { $ownsPanel = $panelMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsPanel = $true }
        if (-not $ownsPanel) { Show-Error 'LV-01 / Lid Vibe is already open. Use its taskbar window.'; return }
        try {
            Invoke-LidVibe 'Recover' ''
            Set-VisualState 'Off' 'Auto starts on AC + Wi-Fi. Battery use stays normal.'
        } catch { $script:autoFaulted = $true; Set-VisualState 'Warning' $_.Exception.Message }
    }
    Update-Telemetry
    $timer.Start()
    if ($isTest) {
        $script:canStart = $true
        foreach ($checkState in @('Off', 'Starting', 'On', 'Stopping', 'Warning')) {
            Set-VisualState $checkState 'Test state'
            $expectedOn = $checkState -in @('Off', 'Warning')
            if ($onButton.IsEnabled -ne $expectedOn -or $offButton.IsEnabled -ne ($checkState -ne 'Stopping')) {
                throw "UI button state failed: $checkState"
            }
            $expectedMotion = ($checkState -in @('Starting','On','Stopping')) -and [Windows.SystemParameters]::ClientAreaAnimation
            for ($ledIndex = 0; $ledIndex -lt 4; $ledIndex++) {
                if ($window.FindName('Pulse' + $ledIndex).HasAnimatedProperties -ne $expectedMotion) { throw "LED state failed: $checkState" }
            }
        }
        $script:canStart = $false
        Set-VisualState 'Off' 'Auto starts on AC + Wi-Fi. Battery use stays normal.'
        if ($onButton.IsEnabled) { throw 'Stay Awake must be disabled when prerequisites are missing.' }
        if ([regex]::Matches($xaml, '<Button x:Name="(?:On|Off)Button"').Count -ne 2) { throw 'The panel must have exactly two power action buttons.' }
        if ([regex]::Matches($xaml, '<Button\s').Count -ne 11) { throw 'Expected two power actions, five artwork keys, settings, help, minimize and close.' }
        if (-not [Windows.Shell.WindowChrome]::GetWindowChrome($window)) { throw 'Native drag/system-menu chrome missing.' }
        Update-Telemetry
        $script:preferences.Theme = $PreviewTheme
        $script:preferences.Accent = $PreviewAccent
        Apply-DevicePalette
        if ($PreviewPath -and $PreviewState -ne 'Off') {
            $script:canStart = $true
            Set-VisualState $PreviewState $(if ($PreviewState -eq 'On') { 'Lid can close. Your work keeps running.' } else { 'Check Windows power settings. Click Turn Off to retry.' })
            $window.FindName('PowerLabel').Text = 'AC'
            $window.FindName('WifiLabel').Text = 'WI-FI'
        }
        $window.WindowStartupLocation = 'Manual'; $window.Left = -10000; $window.Top = -10000
        $closeTimer = [Windows.Threading.DispatcherTimer]::new()
        $closeTimer.Interval = [timespan]::FromSeconds(1)
        $closeTimer.Add_Tick({
            $closeTimer.Stop()
            try {
            $window.FindName('MinimizeButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
            if ($window.WindowState -ne 'Minimized') { throw 'Custom minimize button failed.' }
            $window.WindowState = 'Normal'
            $window.UpdateLayout()
            Test-DeviceDesign | Write-Output
            if ($PreviewView -eq 'Guide') { Set-HelpVisible $true }
            if ($PreviewView -eq 'Hover') { Set-DeviceHint 'Off' }
            if ($PreviewView -eq 'Settings') { Show-DeviceSettings; $script:settingsWindow.UpdateLayout() }
            Set-ArtScene $PreviewScene
            if ($PreviewEffect) { $script:art.Trigger(); $script:art.Advance(0.12,1) }
            Invoke-ArtFrame 0
            # Capture settled text/help, not the zero-time frame of a new fade animation.
            $window.FindName('DisplayContent').BeginAnimation([Windows.UIElement]::OpacityProperty,$null)
            $window.FindName('DisplayContent').Opacity=1
            $window.FindName('HelpPanel').BeginAnimation([Windows.UIElement]::OpacityProperty,$null)
            $window.FindName('HelpPanel').Opacity=1
            $window.UpdateLayout()
            if ($PreviewPath) {
                $surface = if ($PreviewView -eq 'Settings') { $script:settingsWindow.Content } else { $window.Content }
                $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new([int]($surface.ActualWidth * $PreviewScale), [int]($surface.ActualHeight * $PreviewScale), (96*$PreviewScale), (96*$PreviewScale), [Windows.Media.PixelFormats]::Pbgra32)
                $bitmap.Render($surface)
                $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
                $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
                $stream = [IO.File]::Create($PreviewPath)
                try { $encoder.Save($stream) } finally { $stream.Dispose() }
            }
            } catch { $script:smokeFailure=$_.Exception.Message }
            $window.FindName('CloseButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        })
        $closeTimer.Start()
    }
    [void]$window.ShowDialog()
    if ($script:smokeFailure) { throw $script:smokeFailure }
    if ($isTest -and -not $script:designChecksPassed) { throw 'Design interaction checks did not finish.' }
    if ($isTest) { 'UI startup, design interactions and render: OK (no power changes)' }
} finally {
    $timer.Stop()
    if ($script:saveTimer) { $script:saveTimer.Stop() }
    if ($script:helpTimer) { $script:helpTimer.Stop() }
    if ($script:artTimer) { $script:artTimer.Stop() }
    if ($script:designReady -and $ownsPanel) { Save-DevicePreferences }
    if ($script:settingsWindow) { $script:settingsWindow.Close() }
    if ($ownsPanel) { $panelMutex.ReleaseMutex() }
    if ($panelMutex) { $panelMutex.Dispose() }
}
