# Presentation only. This module never calls the power worker or edits power settings.
$script:preferences = [ordered]@{ Version=2; Theme='Light'; Accent='Orange'; Brightness=0.95; Tempo=1.0; Motion=$true; Scene=0 }
$script:preferencePath = Join-Path $script:dataRoot '.lid-vibe-preferences.json'
$script:preferenceNote = 'Saved on this computer.'
$script:pointerHint = ''; $script:focusHint = ''; $script:lastDetail = ''
$script:helpPinned = $false; $script:lastDisplayKey = ''; $script:settingsWindow = $null
$script:designReady = $false; $script:dialDrag = $null
$script:artFrozen=$false; $script:art=$null; $script:artTimer=$null

function Get-ValidatedPreferences {
    param($InputValue)
    $value = [ordered]@{ Version=2; Theme='Light'; Accent='Orange'; Brightness=0.95; Tempo=1.0; Motion=$true; Scene=0 }
    if ($null -eq $InputValue) { return $value }
    if ($InputValue.Theme -in @('Light','Dark')) { $value.Theme = $InputValue.Theme }
    if ($InputValue.Accent -in @('Orange','Cobalt','Mint','Red','Lilac')) { $value.Accent = $InputValue.Accent }
    foreach ($item in @(@('Brightness',0.45,1.0), @('Tempo',0.5,1.5))) {
        $number = 0.0
        if ([double]::TryParse([string]$InputValue.($item[0]), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -and
            -not [double]::IsNaN($number) -and -not [double]::IsInfinity($number)) {
            $value[$item[0]] = [Math]::Max($item[1], [Math]::Min($item[2], $number))
        }
    }
    if ($InputValue.Scene -is [int] -or $InputValue.Scene -is [long]) { $value.Scene = [int][Math]::Max([long]0,[Math]::Min([long]2,[long]$InputValue.Scene)) }
    if ($InputValue.Motion -is [bool]) { $value.Motion = $InputValue.Motion }
    return $value
}

function New-DeviceBrush { param([string]$Color) return [Windows.Media.BrushConverter]::new().ConvertFromString($Color) }
function New-DeviceGradient {
    param([string]$Top,[string]$Bottom)
    $brush = [Windows.Media.LinearGradientBrush]::new()
    $brush.StartPoint = [Windows.Point]::new(0,0); $brush.EndPoint = [Windows.Point]::new(0.8,1)
    $brush.GradientStops.Add([Windows.Media.GradientStop]::new([Windows.Media.ColorConverter]::ConvertFromString($Top),0))
    $brush.GradientStops.Add([Windows.Media.GradientStop]::new([Windows.Media.ColorConverter]::ConvertFromString($Bottom),1))
    return $brush
}

function Apply-DevicePalette {
    $palette = switch ($script:preferences.Accent) {
        'Cobalt' { @('#73B2FF','#327BE1','#235290','#ADCEFF') }
        'Mint' { @('#9DE3BC','#64B98C','#397A59','#BCECCE') }
        'Red' { @('#FF9783','#E76150','#A74035','#FFC2B7') }
        'Lilac' { @('#D2BCFF','#A08AD1','#6A5796','#DFD0FF') }
        default { @('#FF8B42','#E85A1D','#A6461C','#FFA95A') }
    }
    $window.Resources['OrangeKey'] = New-DeviceGradient $palette[0] $palette[1]
    $window.Resources['AccentInk'] = New-DeviceBrush $(if ($script:preferences.Theme -eq 'Dark') { $palette[0] } else { $palette[2] })
    $window.Resources['AccentLight'] = New-DeviceBrush $palette[3]
    $window.Resources['AccentEdge'] = New-DeviceBrush $palette[2]
    if ($script:preferences.Theme -eq 'Dark') {
        $window.Resources['Casing'] = New-DeviceGradient '#414945' '#272D2B'
        $window.Resources['IvoryKey'] = New-DeviceGradient '#69726B' '#47534C'
        $window.Resources['HeaderFace'] = New-DeviceBrush '#353D38'
        $window.Resources['ShellEdge'] = New-DeviceBrush '#171D19'
        $window.Resources['SoftEdge'] = New-DeviceBrush '#58655B'
        $window.Resources['KeyRim'] = New-DeviceBrush '#68746B'
        $window.Resources['LightKeyInk'] = New-DeviceBrush '#EEF1E3'
        $window.Resources['Ink'] = New-DeviceBrush '#EEEADF'
        $window.Resources['MutedInk'] = New-DeviceBrush '#C2C3B8'
        $window.FindName('CaseFace').BorderBrush = New-DeviceBrush '#858A83'
    } else {
        $window.Resources['Casing'] = New-DeviceGradient '#DFDED7' '#BCBDB6'
        $window.Resources['IvoryKey'] = New-DeviceGradient '#F6F5ED' '#D5D6CE'
        $window.Resources['HeaderFace'] = New-DeviceBrush '#ECEAE4'
        $window.Resources['ShellEdge'] = New-DeviceBrush '#92968F'
        $window.Resources['SoftEdge'] = New-DeviceBrush '#B0B3A9'
        $window.Resources['KeyRim'] = New-DeviceBrush '#C2C5BA'
        $window.Resources['LightKeyInk'] = New-DeviceBrush '#41473E'
        $window.Resources['Ink'] = New-DeviceBrush '#45433B'
        $window.Resources['MutedInk'] = New-DeviceBrush '#756F62'
        $window.FindName('CaseFace').BorderBrush = New-DeviceBrush '#FFFBF2'
    }
    # All grille layers change material with the shell, including the hole bevels.
    $grille=$window.Resources['Grille'].Clone()
    $grille.Drawing.Children[0].Brush=$window.Resources['ShellEdge']
    $grille.Drawing.Children[1].Brush=$window.Resources['SoftEdge']
    $window.Resources['Grille']=$grille
    if ($script:settingsWindow) {
        $script:settingsWindow.Background = $window.Resources['Casing']
        $script:settingsWindow.Content.Background = $window.Resources['Casing']
        $script:settingsWindow.Foreground = $window.Resources['Ink']
        $script:settingsWindow.FindName('MotionChoice').Foreground = $window.Resources['Ink']
        $script:settingsWindow.FindName('Done').Foreground = $window.Resources['Ink']
    }
    Refresh-ArtKeys
    if ($script:state -eq 'On') { $statusDot.Fill = $window.Resources['AccentLight'] }
}

function Save-DevicePreferences {
    if ($isTest) { return }
    try {
        Write-JsonAtomic $script:preferencePath $script:preferences
        $script:preferenceNote = 'Saved on this computer.'
    } catch { $script:preferenceNote = 'Could not save. Changes last until this window closes.' }
    if ($script:settingsWindow) { $script:settingsWindow.FindName('SaveNote').Text = $script:preferenceNote }
}

function Queue-PreferenceSave {
    if (-not $script:designReady -or $isTest) { return }
    $script:saveTimer.Stop(); $script:saveTimer.Start()
}

function Refresh-DeviceDisplay {
    $hint = if ($script:pointerHint) { $script:pointerHint } else { $script:focusHint }
    $title = ''; $detail = ''; $size = 15
    if ($script:state -eq 'Warning') {
        $title = 'CHECK SETTINGS'; $size = 14; $detail = $script:lastDetail
    } elseif ($hint) {
        $size = 14
        switch ($hint) {
            'Awake' {
                $title = 'STAY AWAKE'
                $detail = if ($script:state -eq 'On') { 'Running on AC + Wi-Fi.' } elseif (-not $script:canStart) { 'Connect AC power and Wi-Fi first.' } else { 'Resume auto. Keep working with the lid closed.' }
            }
            'Off' { $title='TURN OFF'; $detail='Pause auto. Restore Windows settings.' }
            'Glow' { $title = 'DISPLAY  {0:0}%' -f ($script:preferences.Brightness*100); $detail='Adjust this display. Laptop brightness stays unchanged.' }
            'Tempo' { $title = 'TEMPO  {0:0.0}x' -f $script:preferences.Tempo; $detail='Set the speed of the artwork and activity lights.' }
            'Scene' { $title='SCENE SELECT'; $detail='0 / Pasture    1 / Orbit    2 / Scope' }
            'Cow' { $title='PASTURE'; $detail='A pixel cow. Tap the effect key for a little joy.' }
            'Orbit' { $title='ORBIT'; $detail='Moons in motion. The effect key sends a comet.' }
            'Wave' { $title='SCOPE'; $detail='Synthetic waves. Turn TEMPO to change their rhythm.' }
            'Freeze' { $title=if ($script:artFrozen) {'UNFREEZE ART'} else {'FREEZE ART'}; $detail='Pause the artwork only. Power monitoring continues.' }
            'Burst' { $title='PLAY EFFECT'; $detail=if (-not $script:preferences.Motion) {'Enable motion in Appearance to play effects.'} elseif ($script:artFrozen) {'Unfreeze the artwork first.'} else {'Pasture: hearts. Orbit: comet. Scope: wave burst.'} }
        }
    } else {
        $title = switch ($script:state) { 'On' {'AWAKE'}; 'Starting' {'STARTING'}; 'Stopping' {'STOPPING'}; default {if ($script:autoPaused) {'PAUSED'} else {'STANDBY'}} }
        $detail = switch ($script:state) {
            'On' {'AC + WI-FI'}; 'Starting' {'Checking connections'}; 'Stopping' {'Restoring Windows settings'}
            default { if ($script:autoPaused) { 'Press Stay Awake to resume' } elseif ($script:canStart) { 'Auto starts shortly' } else { 'Waiting for AC + Wi-Fi' } }
        }
    }
    $key = "$title|$detail"
    $statusTitle.Text = $title; $statusTitle.FontSize = $size
    $window.FindName('LcdPixels').Opacity = if ($script:state -eq 'Warning') { [Math]::Max(0.85,$script:preferences.Brightness) } else { $script:preferences.Brightness }
    $statusDetail.Text = $detail; $statusDetail.ToolTip = $script:lastDetail
    if ($script:lastDisplayKey -ne $key -and $script:preferences.Motion -and [Windows.SystemParameters]::ClientAreaAnimation) {
        $fade = [Windows.Media.Animation.DoubleAnimation]::new(0.45,1,[Windows.Duration]::new([timespan]::FromSeconds(0.14)))
        $window.FindName('DisplayContent').BeginAnimation([Windows.UIElement]::OpacityProperty,$fade)
    }
    $script:lastDisplayKey = $key
    $window.FindName('ArtStrip').Visibility = if ($script:state -eq 'Warning' -or $hint) { 'Collapsed' } else { 'Visible' }
    $window.FindName('ModeLabel').Visibility = if ($hint -or $script:state -eq 'Warning') { 'Collapsed' } else { 'Visible' }
    $window.FindName('ModeLabel').Text = if ($script:autoPaused) {'AUTO / PAUSED'} elseif ($script:autoFaulted) {'AUTO / CHECK'} else {'AUTO'}
}

function Set-DeviceHint { param([string]$Hint) $script:pointerHint = $Hint; Refresh-DeviceDisplay }
function Get-ControlHint {
    param([string]$Name)
    switch ($Name) { 'OnButton' {'Awake'}; 'OnHoverSurface' {'Awake'}; 'OffButton' {'Off'}; 'OffHoverSurface' {'Off'}; 'GlowDial' {'Glow'}; 'TempoDial' {'Tempo'}; 'SceneDial' {'Scene'}; 'CowButton' {'Cow'}; 'OrbitButton' {'Orbit'}; 'WaveButton' {'Wave'}; 'FreezeButton' {'Freeze'}; 'BurstButton' {'Burst'}; default {''} }
}

function Set-HelpVisible {
    param([bool]$Visible)
    $help = $window.FindName('HelpPanel')
    $help.Visibility = if ($Visible) { 'Visible' } else { 'Collapsed' }
    if ($Visible -and $script:preferences.Motion -and [Windows.SystemParameters]::ClientAreaAnimation) {
        $help.BeginAnimation([Windows.UIElement]::OpacityProperty,[Windows.Media.Animation.DoubleAnimation]::new(0,1,[Windows.Duration]::new([timespan]::FromSeconds(0.12))))
    }
}

function Update-DialVisual {
    param($Dial)
    $Dial.ApplyTemplate() | Out-Null
    $pointer = $Dial.Template.FindName('Pointer',$Dial)
    if ($pointer) { $pointer.RenderTransform = [Windows.Media.RotateTransform]::new((-135 + 270 * (($Dial.Value-$Dial.Minimum)/($Dial.Maximum-$Dial.Minimum)))) }
    if ($Dial.Name -eq 'GlowDial') {
        $script:preferences.Brightness = [Math]::Round($Dial.Value,2)
        $window.FindName('LcdPixels').Opacity = $script:preferences.Brightness
    } elseif ($Dial.Name -eq 'SceneDial') {
        Set-ArtScene ([int][Math]::Round($Dial.Value))
    } else {
        $script:preferences.Tempo = [Math]::Round($Dial.Value,2)
        Update-ActivityLights $script:state
    }
    Refresh-DeviceDisplay
    Queue-PreferenceSave
}

function Show-DeviceSettings {
    if ($script:settingsWindow) { $script:settingsWindow.Activate() | Out-Null; return }
    $settingsMarkup = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework"
 Title="LV-01 appearance" Width="308" Height="310" WindowStyle="None" ResizeMode="NoResize" ShowInTaskbar="False" WindowStartupLocation="CenterOwner">
 <shell:WindowChrome.WindowChrome><shell:WindowChrome CaptionHeight="43" ResizeBorderThickness="0" CornerRadius="8" GlassFrameThickness="0" UseAeroCaptionButtons="False"/></shell:WindowChrome.WindowChrome>
 <Border BorderBrush="#898B80" BorderThickness="1" Padding="20,14">
  <StackPanel>
   <Grid Margin="0,0,0,17"><TextBlock Text="Appearance" FontSize="18" FontWeight="Light"/><Button x:Name="Done" Content="&#xD7;" Width="25" Height="24" HorizontalAlignment="Right" Background="Transparent" BorderThickness="0" FontSize="18" shell:WindowChrome.IsHitTestVisibleInChrome="True" AutomationProperties.Name="Close settings"/></Grid>
   <TextBlock Text="Casing" FontSize="11" Margin="0,0,0,5"/>
   <ComboBox x:Name="ThemeChoice" Height="30" Margin="0,0,0,12" AutomationProperties.Name="Casing theme"><ComboBoxItem Content="Light"/><ComboBoxItem Content="Dark"/></ComboBox>
   <TextBlock Text="Accent" FontSize="11" Margin="0,0,0,5"/>
   <ComboBox x:Name="AccentChoice" Height="30" Margin="0,0,0,15" AutomationProperties.Name="Accent colour"><ComboBoxItem Content="Orange"/><ComboBoxItem Content="Cobalt"/><ComboBoxItem Content="Mint"/><ComboBoxItem Content="Red"/><ComboBoxItem Content="Lilac"/></ComboBox>
   <CheckBox x:Name="MotionChoice" Content="Animate the display and lights" FontSize="11" Margin="0,0,0,15"/>
   <TextBlock x:Name="SaveNote" FontSize="10" TextWrapping="Wrap"/>
  </StackPanel>
 </Border>
</Window>
'@
    $script:settingsWindow = [Windows.Markup.XamlReader]::Parse($settingsMarkup)
    $script:settingsWindow.Owner = $window
    Apply-DevicePalette
    foreach ($pair in @(@('ThemeChoice','Theme'),@('AccentChoice','Accent'))) {
        $combo = $script:settingsWindow.FindName($pair[0])
        foreach ($item in $combo.Items) { if ($item.Content -eq $script:preferences[$pair[1]]) { $combo.SelectedItem = $item } }
    }
    $script:settingsWindow.FindName('MotionChoice').IsChecked = $script:preferences.Motion
    $script:settingsWindow.FindName('SaveNote').Text = $script:preferenceNote
    $script:settingsWindow.FindName('Done').Add_Click({ $script:settingsWindow.Close() })
    $script:settingsWindow.Add_PreviewKeyDown({param($sender,$eventArgs) if ($eventArgs.Key -eq 'Escape') { $sender.Close(); $eventArgs.Handled=$true }})
    $script:settingsWindow.Add_Closed({ $script:settingsWindow = $null })
    $script:settingsWindow.FindName('ThemeChoice').Add_SelectionChanged({
        param($sender,$eventArgs)
        $script:preferences.Theme = [string]$sender.SelectedItem.Content
        Apply-DevicePalette; Queue-PreferenceSave
    })
    $script:settingsWindow.FindName('AccentChoice').Add_SelectionChanged({
        param($sender,$eventArgs)
        $script:preferences.Accent = [string]$sender.SelectedItem.Content
        Apply-DevicePalette; Queue-PreferenceSave
    })
    $script:settingsWindow.FindName('MotionChoice').Add_Click({
        param($sender,$eventArgs)
        $script:preferences.Motion = [bool]$sender.IsChecked
        Update-ActivityLights $script:state
        if (-not $script:preferences.Motion) { if ($script:art) { $script:art.ClearEffect() }; $window.FindName('DisplayContent').BeginAnimation([Windows.UIElement]::OpacityProperty,$null) }
        Queue-PreferenceSave
    })
    $script:settingsWindow.Show()
}

function Initialize-DeviceDesign {
    if (-not $isTest -and (Test-Path -LiteralPath $script:preferencePath)) {
        try { $script:preferences = Get-ValidatedPreferences (Get-Content -LiteralPath $script:preferencePath -Raw | ConvertFrom-Json) }
        catch { $script:preferenceNote = 'Unreadable preferences. Using defaults.' }
    }
    $script:saveTimer = [Windows.Threading.DispatcherTimer]::new()
    $script:saveTimer.Interval = [timespan]::FromMilliseconds(400)
    $script:saveTimer.Add_Tick({ $script:saveTimer.Stop(); Save-DevicePreferences })
    Apply-DevicePalette
    foreach ($name in @('OnHoverSurface','OffHoverSurface','GlowDial','TempoDial','SceneDial','CowButton','OrbitButton','WaveButton','FreezeButton','BurstButton')) {
        $control = $window.FindName($name)
        $control.Add_MouseEnter({param($sender,$eventArgs) Set-DeviceHint (Get-ControlHint $sender.Name) })
        $control.Add_MouseLeave({param($sender,$eventArgs) if (-not $script:dialDrag) { Set-DeviceHint '' } })
    }
    foreach ($name in @('OnButton','OffButton','GlowDial','TempoDial','SceneDial','CowButton','OrbitButton','WaveButton','FreezeButton','BurstButton')) {
        $control = $window.FindName($name)
        $control.Add_GotKeyboardFocus({param($sender,$eventArgs) $script:focusHint=Get-ControlHint $sender.Name; Refresh-DeviceDisplay })
        $control.Add_LostKeyboardFocus({ $script:focusHint=''; Refresh-DeviceDisplay })
    }
    foreach ($name in @('GlowDial','TempoDial','SceneDial')) {
        $dial = $window.FindName($name)
        $dial.Value = if ($name -eq 'GlowDial') { $script:preferences.Brightness } elseif ($name -eq 'SceneDial') { $script:preferences.Scene } else { $script:preferences.Tempo }
        $dial.Add_ValueChanged({param($sender,$eventArgs) Update-DialVisual $sender })
        $dial.Add_PreviewMouseLeftButtonDown({
            param($sender,$eventArgs)
            $sender.Focus() | Out-Null
            if ($eventArgs.ClickCount -eq 2) { $sender.Value = if ($sender.Name -eq 'GlowDial') { 0.95 } elseif ($sender.Name -eq 'SceneDial') { 0 } else { 1 }; $eventArgs.Handled=$true; return }
            $point = $eventArgs.GetPosition($window)
            $script:dialDrag = @{ Name=$sender.Name; X=$point.X; Y=$point.Y; Value=$sender.Value }
            $sender.CaptureMouse() | Out-Null; $eventArgs.Handled=$true
        })
        $dial.Add_PreviewMouseMove({
            param($sender,$eventArgs)
            if ($script:dialDrag -and $script:dialDrag.Name -eq $sender.Name -and $sender.IsMouseCaptured) {
                $point = $eventArgs.GetPosition($window)
                $change = ($point.X-$script:dialDrag.X+$script:dialDrag.Y-$point.Y) * ($sender.Maximum-$sender.Minimum) / 140
                $sender.Value = [Math]::Max($sender.Minimum,[Math]::Min($sender.Maximum,$script:dialDrag.Value+$change))
                $eventArgs.Handled=$true
            }
        })
        $dial.Add_PreviewMouseLeftButtonUp({param($sender,$eventArgs) $script:dialDrag=$null; $sender.ReleaseMouseCapture(); if (-not $sender.IsMouseOver) { Set-DeviceHint '' }; $eventArgs.Handled=$true })
        $dial.Add_LostMouseCapture({ $script:dialDrag=$null })
        $dial.Add_PreviewMouseWheel({param($sender,$eventArgs) $sender.Value=[Math]::Max($sender.Minimum,[Math]::Min($sender.Maximum,$sender.Value+[Math]::Sign($eventArgs.Delta)*$sender.SmallChange)); $eventArgs.Handled=$true })
        Update-DialVisual $dial
    }
    $window.FindName('InfoButton').Add_MouseEnter({ Set-HelpVisible $true })
    $window.FindName('InfoButton').Add_MouseLeave({ if (-not $script:helpPinned) { $script:helpTimer.Start() } })
    $window.FindName('InfoButton').Add_GotKeyboardFocus({ Set-HelpVisible $true })
    $window.FindName('InfoButton').Add_LostKeyboardFocus({ if (-not $script:helpPinned) { Set-HelpVisible $false } })
    $window.FindName('InfoButton').Add_Click({ $script:helpPinned=-not $script:helpPinned; Set-HelpVisible $script:helpPinned })
    $window.FindName('HelpPanel').Add_MouseEnter({ $script:helpTimer.Stop() })
    $window.FindName('HelpPanel').Add_MouseLeave({ if (-not $script:helpPinned) { $script:helpTimer.Start() } })
    $script:helpTimer = [Windows.Threading.DispatcherTimer]::new()
    $script:helpTimer.Interval = [timespan]::FromMilliseconds(250)
    $script:helpTimer.Add_Tick({ $script:helpTimer.Stop(); if (-not $script:helpPinned -and -not $window.FindName('HelpPanel').IsMouseOver -and -not $window.FindName('InfoButton').IsMouseOver) { Set-HelpVisible $false } })
    $window.Add_PreviewKeyDown({param($sender,$eventArgs) if ($eventArgs.Key -eq 'Escape') { $script:helpPinned=$false; Set-HelpVisible $false; $eventArgs.Handled=$true } })
    $window.Add_PreviewMouseDown({
        if ($script:helpPinned -and -not $window.FindName('HelpPanel').IsMouseOver -and -not $window.FindName('InfoButton').IsMouseOver) {
            $script:helpPinned=$false; Set-HelpVisible $false
        }
    })
    $window.FindName('SettingsButton').Add_Click({ $script:helpPinned=$false; Set-HelpVisible $false; Show-DeviceSettings })
    $window.Add_Deactivated({ $script:helpPinned=$false; Set-HelpVisible $false; $script:pointerHint=''; Refresh-DeviceDisplay })
    Initialize-DeviceArt
    $script:designReady = $true
}

function Test-DeviceDesign {
    if (-not $isTest) { throw 'Design tests require smoke/preview mode.' }
    $savedPreferences = Get-ValidatedPreferences ([pscustomobject]$script:preferences)
    $savedState = $script:state; $savedDetail = $script:lastDetail
    try {
        Set-VisualState 'On' 'Original live status'
        Set-DeviceHint 'Off'
        if ($statusTitle.Text -ne 'TURN OFF') { throw 'Button hover hint missing.' }
        Set-VisualState 'On' 'Heartbeat refresh'
        if ($statusTitle.Text -ne 'TURN OFF' -or $script:lastDetail -ne 'Heartbeat refresh') { throw 'Heartbeat overwrote hover or live status.' }
        Set-DeviceHint ''
        if ($statusTitle.Text -ne 'AWAKE') { throw 'Hover exit did not restore live state.' }
        Set-DeviceHint 'Glow'
        Set-VisualState 'Warning' 'Recovery needs attention'
        if ($statusTitle.Text -ne 'CHECK SETTINGS' -or $statusDetail.Text -ne 'Recovery needs attention') { throw 'Hover obscured a warning.' }
        Set-DeviceHint ''
        Set-VisualState 'On' 'Test active display'

        $glow=$window.FindName('GlowDial'); $tempo=$window.FindName('TempoDial')
        $glow.Value=0.6
        if ([Math]::Abs($window.FindName('LcdPixels').Opacity-0.6) -gt 0.001) { throw 'Brightness dial did not change display.' }
        $key=[Windows.Input.KeyEventArgs]::new([Windows.Input.Keyboard]::PrimaryDevice,[Windows.PresentationSource]::FromVisual($window),0,[Windows.Input.Key]::Right)
        $key.RoutedEvent=[Windows.Input.Keyboard]::KeyDownEvent
        $glow.RaiseEvent($key)
        if ($glow.Value -le 0.6) { throw 'Dial keyboard increment failed.' }
        $wheel=[Windows.Input.MouseWheelEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,0,120)
        $wheel.RoutedEvent=[Windows.Input.Mouse]::PreviewMouseWheelEvent
        $tempo.Value=0.7; $tempo.RaiseEvent($wheel)
        if ([Math]::Abs($tempo.Value-0.8) -gt 0.001 -or $script:preferences.Tempo -ne 0.8) { throw 'Dial scroll/tempo update failed.' }
        $pointer=$glow.Template.FindName('Pointer',$glow)
        if ($pointer.RenderTransform.Angle -lt -135 -or $pointer.RenderTransform.Angle -gt 135) { throw 'Dial needle outside valid sweep.' }

        $window.FindName('InfoButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        if (-not $script:helpPinned -or $window.FindName('HelpPanel').Visibility -ne 'Visible') { throw 'Info click did not open guide.' }
        $window.FindName('InfoButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        if ($script:helpPinned -or $window.FindName('HelpPanel').Visibility -ne 'Collapsed') { throw 'Info click did not dismiss guide.' }

        $window.FindName('SettingsButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        if (-not $script:settingsWindow -or -not $script:settingsWindow.IsVisible) { throw 'Settings window did not open.' }
        $script:settingsWindow.FindName('ThemeChoice').SelectedIndex=1
        if ($script:preferences.Theme -ne 'Dark' -or $window.Resources['Ink'].Color.ToString() -ne '#FFEEEADF') { throw 'Dark theme selection failed.' }
        $script:settingsWindow.FindName('ThemeChoice').SelectedIndex=0
        if ($script:preferences.Theme -ne 'Light') { throw 'Light theme selection failed.' }
        $accents=@('Orange','Cobalt','Mint','Red','Lilac')
        for ($i=0;$i -lt $accents.Count;$i++) {
            $script:settingsWindow.FindName('AccentChoice').SelectedIndex=$i
            if ($script:preferences.Accent -ne $accents[$i]) { throw 'Accent selection failed.' }
        }
        $motion=$script:settingsWindow.FindName('MotionChoice')
        $motion.IsChecked=$false
        $motion.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        if ($window.FindName('Pulse0').HasAnimatedProperties -or $window.FindName('DisplayContent').HasAnimatedProperties) { throw 'Motion-off did not stop animation.' }
        $script:settingsWindow.FindName('Done').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        if ($script:settingsWindow) { throw 'Settings close failed.' }
        foreach ($pair in @(@('OrbitButton',1),@('WaveButton',2),@('CowButton',0))) {
            $window.FindName($pair[0]).RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
            if ($script:art.Scene -ne $pair[1] -or $script:preferences.Scene -ne $pair[1]) { throw 'Scene pad failed.' }
        }
        $scene=$window.FindName('SceneDial'); $scene.Value=2
        if ($script:art.Scene -ne 2) { throw 'Scene dial failed.' }
        $script:preferences.Motion=$true
        $window.FindName('BurstButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        if ([Windows.SystemParameters]::ClientAreaAnimation -and $script:art.EffectRemaining -ne 3) { throw 'Scene effect did not start.' }
        $frame=$script:art.FrameCount
        Invoke-ArtFrame 0.12
        if ([Windows.SystemParameters]::ClientAreaAnimation -and $script:art.FrameCount -le $frame) { throw 'Artwork did not advance.' }
        $window.FindName('FreezeButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        $frame=$script:art.FrameCount; Invoke-ArtFrame 0.12
        if ($script:art.FrameCount -ne $frame -or -not $script:artFrozen) { throw 'Artwork freeze failed.' }
        $window.FindName('FreezeButton').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
        $script:preferences.Motion=$false; Invoke-ArtFrame 0.12
        if ($script:art.FrameCount -ne $frame) { throw 'Motion setting did not stop artwork.' }
        $script:preferences.Motion=$true
        $window.WindowState='Minimized'; Invoke-ArtFrame 0.12
        if ($script:art.FrameCount -ne $frame) { throw 'Minimized artwork continued rendering.' }
        $window.WindowState='Normal'
        $script:preferences.Theme='Dark'; Apply-DevicePalette
        if ($window.Resources['IvoryKey'].GradientStops[0].Color.ToString() -ne '#FF69726B' -or $window.Resources['Grille'].Drawing.Children[0].Brush.Color.ToString() -ne '#FF171D19') { throw 'Dark key/grille material failed.' }
        $script:designChecksPassed=$true
        'Design interactions: OK (hover, warnings, guide, dials, keyboard, wheel, themes, accents, motion)'
    } finally {
        if ($script:settingsWindow) { $script:settingsWindow.Close() }
        $script:preferences=$savedPreferences
        $script:pointerHint=''; $script:focusHint=''; $script:helpPinned=$false
        Set-HelpVisible $false
        $window.FindName('GlowDial').Value=$script:preferences.Brightness
        $window.FindName('TempoDial').Value=$script:preferences.Tempo
        $script:artFrozen=$false; $script:art.ClearEffect()
        $window.FindName('SceneDial').Value=$script:preferences.Scene
        Set-ArtScene $script:preferences.Scene
        Apply-DevicePalette
        Set-VisualState $savedState $savedDetail
    }
}


function Set-ArtScene {
    param([int]$Scene)
    $script:preferences.Scene=[Math]::Max(0,[Math]::Min(2,$Scene))
    if ($script:art) { $script:art.Scene=$script:preferences.Scene; $script:art.ClearEffect(); $script:art.InvalidateVisual() }
    $window.FindName('SceneLabel').Text= @('01 / PASTURE','02 / ORBIT','03 / SCOPE')[$script:preferences.Scene]
    $window.FindName('SceneNumber').Text= '{0:00}' -f ($script:preferences.Scene+1)
    $window.FindName('SceneHost').SetValue([Windows.Automation.AutomationProperties]::NameProperty, @('Animated pixel cow visualizer','Orbital visualizer','Synthetic waveform visualizer')[$script:preferences.Scene])
    Refresh-ArtKeys
    if ($window.FindName('SceneDial').Value -ne $script:preferences.Scene) { $window.FindName('SceneDial').Value=$script:preferences.Scene }
    Queue-PreferenceSave
}

function Invoke-ArtFrame {
    param([double]$Seconds)
    if ($window.WindowState -ne 'Minimized' -and $window.IsVisible -and $script:preferences.Motion -and [Windows.SystemParameters]::ClientAreaAnimation -and -not $script:artFrozen) {
        $script:art.Advance($Seconds,$script:preferences.Tempo)
    }
    $window.FindName('ClockLabel').Text=[datetime]::Now.ToString('HH:mm')
    $moving=$script:preferences.Motion -and [Windows.SystemParameters]::ClientAreaAnimation -and -not $script:artFrozen
    $window.FindName('ArtModeLabel').Text=if ($moving) { 'ART / PLAY' } else { 'ART / HOLD' }
    $step=[int]([Math]::Floor($script:art.Phase*3)%16)
    for ($i=0;$i -lt 16;$i++) { $window.FindName('ArtStep'+$i).Opacity=if ($i -eq $step) {1} else {0.2} }
}

function Initialize-DeviceArt {
    Add-Type -Path (Join-Path $PSScriptRoot 'lid-vibe-art.cs') -ReferencedAssemblies @('PresentationCore','PresentationFramework','WindowsBase','System.Xaml')
    $script:art=New-Object LidVibeArt
    $window.FindName('SceneHost').Child=$script:art
    Set-ArtScene $script:preferences.Scene
    foreach ($name in @('CowButton','OrbitButton','WaveButton')) {
        $window.FindName($name).Add_Click({param($sender,$eventArgs)
            $choice=switch($sender.Name) { 'CowButton' {0}; 'OrbitButton' {1}; 'WaveButton' {2} }
            Set-ArtScene $choice; Refresh-DeviceDisplay
        })
    }
    $window.FindName('FreezeButton').Add_Click({
        $script:artFrozen=-not $script:artFrozen
        $window.FindName('FreezeButton').BorderBrush=if ($script:artFrozen) { $window.Resources['AccentInk'] } else { New-DeviceBrush '#141816' }
        $window.FindName('FreezeButton').SetValue([Windows.Automation.AutomationProperties]::NameProperty,$(if ($script:artFrozen) {'Unfreeze visualizer'} else {'Freeze visualizer'}))
        Refresh-DeviceDisplay
    })
    $window.FindName('BurstButton').Add_Click({
        if ($script:preferences.Motion -and [Windows.SystemParameters]::ClientAreaAnimation -and -not $script:artFrozen) { $script:art.Trigger() }
    })
    $script:artClock=[Diagnostics.Stopwatch]::StartNew()
    $script:artTimer=[Windows.Threading.DispatcherTimer]::new()
    $script:artTimer.Interval=[timespan]::FromMilliseconds(125)
    $script:artTimer.Add_Tick({
        $elapsed=$script:artClock.Elapsed.TotalSeconds; $script:artClock.Restart()
        Invoke-ArtFrame $elapsed
        $moving=$window.WindowState -ne 'Minimized' -and $script:preferences.Motion -and [Windows.SystemParameters]::ClientAreaAnimation -and -not $script:artFrozen
        $script:artTimer.Interval=[timespan]::FromMilliseconds($(if ($moving) {125} else {1000}))
    })
    $script:artTimer.Start()
}


function Refresh-ArtKeys {
    foreach ($pair in @(@('CowButton',0),@('OrbitButton',1),@('WaveButton',2))) {
        $window.FindName($pair[0]).BorderBrush=if ($pair[1] -eq $script:preferences.Scene) { $window.Resources['AccentInk'] } else { New-DeviceBrush '#141816' }
    }
    $window.FindName('FreezeButton').BorderBrush=if ($script:artFrozen) { $window.Resources['AccentInk'] } else { New-DeviceBrush '#141816' }
}
