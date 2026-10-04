param(
    [ValidateSet('On', 'Off', 'Status', 'Recover')][string]$Mode = 'Status',
    [int]$OwnerPid = 0,
    [string]$Session = '',
    [switch]$LibraryOnly
)

# Windows PowerShell 5.1. Only the AC lid action is temporarily changed.
# No sleep, hibernate, shutdown, or battery-setting writes exist in this utility.
$ErrorActionPreference = 'Stop'
# The executable supplies a stable per-user data folder across app upgrades.
# Direct script launches retain the existing adjacent-file behavior.
$script:dataRoot = if ($env:LV01_DATA_DIR) { $env:LV01_DATA_DIR } else { $PSScriptRoot }
$script:stopFile = Join-Path $script:dataRoot '.lid-vibe.stop'
$script:journalFile = Join-Path $script:dataRoot '.lid-vibe-restore.json'
$script:statusFile = Join-Path $script:dataRoot '.lid-vibe-status.json'
$script:mutexName = 'Local\LidVibe.Worker.' + [Environment]::UserName

function Write-JsonAtomic {
    param([string]$Path, $Value)
    $temp = "$Path.$PID.tmp"
    try {
        $Value | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $temp -Encoding UTF8
        Move-Item -LiteralPath $temp -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
    }
}

function Get-LidSettings {
    param([string]$Scheme = 'SCHEME_CURRENT')
    $raw = (& powercfg.exe /qh $Scheme SUB_BUTTONS LIDACTION) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'Windows could not read the lid settings.' }
    $guidMatch = [regex]::Match($raw, '(?i)[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}')
    $indices = [regex]::Matches($raw, '0x[0-9a-fA-F]{8}')
    if (-not $guidMatch.Success -or $indices.Count -lt 2) { throw 'Windows returned unreadable lid settings.' }
    [pscustomobject]@{
        Scheme = $guidMatch.Value
        Ac = [Convert]::ToInt32($indices[$indices.Count - 2].Value.Substring(2), 16)
        Battery = [Convert]::ToInt32($indices[$indices.Count - 1].Value.Substring(2), 16)
    }
}

function Set-AcLidAction {
    param([string]$Scheme, [ValidateRange(0,3)][int]$Value)
    & powercfg.exe /setacvalueindex $Scheme SUB_BUTTONS LIDACTION $Value | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Windows denied the AC lid setting change. Company policy may block Stay Awake.' }
    # Never switch the user back to a different plan during cleanup.
    if ((Get-LidSettings).Scheme -eq $Scheme) {
        & powercfg.exe /setactive $Scheme | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Windows could not apply the AC lid setting.' }
    }
    if ((Get-LidSettings -Scheme $Scheme).Ac -ne $Value) { throw 'Windows did not retain the AC lid setting.' }
}

function Restore-LidSettings {
    if (-not (Test-Path -LiteralPath $script:journalFile)) { return }
    $saved = Get-Content -LiteralPath $script:journalFile -Raw | ConvertFrom-Json
    if ($saved.Version -ne 1 -or $saved.Scheme -notmatch '^[0-9a-fA-F-]{36}$' -or
        $null -eq $saved.Ac -or [int]$saved.Ac -notin 0,1,2,3) { throw 'Recovery data is invalid. Check Windows lid settings.' }
    $current = Get-LidSettings -Scheme $saved.Scheme
    # A deliberate user/policy change takes precedence over our saved value.
    if ($current.Ac -eq 0) { Set-AcLidAction -Scheme $saved.Scheme -Value $saved.Ac }
    Remove-Item -LiteralPath $script:journalFile -Force
}

function Get-ConnectedWifi {
    foreach ($adapter in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($adapter.NetworkInterfaceType -ne 'Wireless80211' -or $adapter.OperationalStatus -ne 'Up') { continue }
        try {
            $addresses = @($adapter.GetIPProperties().UnicastAddresses | Where-Object {
                ($_.Address.AddressFamily -eq 'InterNetwork' -and -not $_.Address.ToString().StartsWith('169.254.')) -or
                ($_.Address.AddressFamily -eq 'InterNetworkV6' -and -not $_.Address.IsIPv6LinkLocal)
            })
        } catch { continue }
        if ($addresses.Count -gt 0) { return [pscustomobject]@{ Id = $adapter.Id; Name = $adapter.Name } }
    }
    return $null
}

function Test-OnAC {
    Add-Type -AssemblyName System.Windows.Forms
    return [System.Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus -eq 'Online'
}

function Set-IdleWake {
    param([bool]$Enabled)
    if (-not ('LidVibeIdle' -as [type])) {
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
public static class LidVibeIdle {
    [DllImport("Kernel32.dll")]
    public static extern uint SetThreadExecutionState(uint flags);
}
'@
    }
    $flags = if ($Enabled) { [Convert]::ToUInt32('80000001', 16) } else { [Convert]::ToUInt32('80000000', 16) }
    if ([LidVibeIdle]::SetThreadExecutionState($flags) -eq 0) { throw 'Windows could not update the stay-awake request.' }
}

function Test-StopRequested {
    param([string]$SessionId)
    if (-not (Test-Path -LiteralPath $script:stopFile)) { return $false }
    return (Get-Content -LiteralPath $script:stopFile -Raw).Trim() -eq $SessionId
}

function Test-OwnerAlive {
    param([int]$ProcessId, [datetime]$Started)
    if ($ProcessId -eq 0) { return $true }
    $owner = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    return $null -ne $owner -and $owner.StartTime.ToUniversalTime() -eq $Started
}

function Publish-State {
    param([string]$State, [string]$Detail, [string]$SessionId)
    Write-JsonAtomic $script:statusFile ([ordered]@{
        State = $State; Detail = $Detail; Session = $SessionId; Pid = $PID
        UpdatedUtc = [datetime]::UtcNow.ToString('o')
    })
}

function Invoke-AwakeSession {
    param([string]$SessionId, [int]$ParentPid = 0)
    $reason = 'Turned off. Windows settings restored.'
    $wakeSet = $false
    $ownerStart = [datetime]::MinValue
    try {
        Restore-LidSettings
        if ($ParentPid -ne 0) { $ownerStart = (Get-Process -Id $ParentPid).StartTime.ToUniversalTime() }
        if (Test-StopRequested $SessionId) { return }
        if (-not (Test-OnAC)) { throw 'Connect the charger before using Stay Awake.' }
        if (-not (Get-ConnectedWifi)) { throw 'Connect to Wi-Fi before using Stay Awake.' }
        $saved = Get-LidSettings
        Write-JsonAtomic $script:journalFile ([ordered]@{ Version = 1; Scheme = $saved.Scheme; Ac = $saved.Ac })
        Set-AcLidAction -Scheme $saved.Scheme -Value 0
        # Recheck after setup to cover unplug/close during startup.
        if (Test-StopRequested $SessionId) { return }
        if (-not (Test-OnAC)) { $reason = 'Unplugged. Normal battery behavior.'; return }
        Set-IdleWake $true
        $wakeSet = $true
        Publish-State 'On' 'Lid can close while power and Wi-Fi stay connected.' $SessionId
        $tick = 0
        while ($true) {
            Start-Sleep -Seconds 1
            if (Test-StopRequested $SessionId) { break }
            if (-not (Test-OwnerAlive $ParentPid $ownerStart)) { $reason = 'Panel closed. Windows settings restored.'; break }
            if (-not (Test-OnAC)) { $reason = 'Unplugged. Normal battery behavior.'; break }
            $tick++
            if ($tick % 5 -eq 0) {
                if (-not (Get-ConnectedWifi)) { $reason = 'Wi-Fi disconnected. Windows settings restored.'; break }
                $now = Get-LidSettings
                if ($now.Scheme -ne $saved.Scheme -or $now.Ac -ne 0) {
                    $reason = 'Power settings changed. Stay Awake is off.'; break
                }
                Publish-State 'On' 'Lid can close while power and Wi-Fi stay connected.' $SessionId
            }
        }
    } catch {
        $reason = $_.Exception.Message
        throw
    } finally {
        try {
            try { if ($wakeSet) { Set-IdleWake $false } }
            finally { Restore-LidSettings }
            Publish-State 'Off' $reason $SessionId
        } catch {
            Publish-State 'Warning' ('Could not restore settings. ' + $_.Exception.Message) $SessionId
            throw
        }
    }
}

function Invoke-LidVibe {
    param([string]$Action, [string]$SessionId, [int]$ParentPid = 0)
    if ($Action -eq 'Status') { Get-LidSettings; return }
    $mutex = [Threading.Mutex]::new($false, $script:mutexName)
    $locked = $false
    try {
        if ($Action -eq 'Off') {
            if (-not $SessionId -and (Test-Path -LiteralPath $script:statusFile)) {
                $SessionId = (Get-Content -LiteralPath $script:statusFile -Raw | ConvertFrom-Json).Session
            }
            if ($SessionId) { Set-Content -LiteralPath $script:stopFile -Value $SessionId }
        }
        try { $locked = $mutex.WaitOne($(if ($Action -eq 'On') { 0 } else { 8000 })) }
        catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { throw 'Stay Awake is already running or still stopping. Try Turn Off again.' }
        if ($Action -eq 'On') {
            if (-not $SessionId) { $SessionId = [guid]::NewGuid().ToString() }
            Invoke-AwakeSession $SessionId $ParentPid
        } else {
            Restore-LidSettings
        }
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

if (-not $LibraryOnly) { Invoke-LidVibe $Mode $Session $OwnerPid }
