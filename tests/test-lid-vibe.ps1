param([string]$CorePath = (Join-Path $PSScriptRoot '..\src\lid-vibe.ps1'))
$ErrorActionPreference = 'Stop'
. $CorePath -LibraryOnly
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('lid-vibe-tests-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $testRoot | Out-Null
$script:journalFile = Join-Path $testRoot 'restore.json'
$script:statusFile = Join-Path $testRoot 'status.json'
$script:stopFile = Join-Path $testRoot 'stop'
$script:passed = 0

function Assert { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw "FAIL: $Message" } }
function Reset-Test {
    param([string]$Case, [int]$Ac = 1, [int]$Battery = 1)
    $script:case = $Case; $script:tick = 0; $script:acChecks = 0; $script:wake = $false
    $script:writes = @(); $script:originalAc = $Ac; $script:fakeAc = $Ac; $script:fakeBattery = $Battery
    $script:fakeScheme = '381b4222-f694-41f0-9685-ff5bb260df2e'
    $script:originalScheme = $script:fakeScheme; $script:otherAc = 2
    $script:failRestore = $false; $script:cancelOnWrite = $false
    Get-ChildItem -LiteralPath $testRoot -File | Remove-Item -Force
}

# All OS-changing boundaries are replaced. These tests never call powercfg, Sleep or shutdown.
function Get-LidSettings {
    param([string]$Scheme = 'SCHEME_CURRENT')
    if ($Scheme -eq 'SCHEME_CURRENT') { $Scheme = $script:fakeScheme }
    [pscustomobject]@{ Scheme = $Scheme; Ac = $(if ($Scheme -eq $script:originalScheme) { $script:fakeAc } else { $script:otherAc }); Battery = $script:fakeBattery }
}
function Set-AcLidAction {
    param([string]$Scheme, [int]$Value)
    $script:writes += [pscustomobject]@{ Scheme = $Scheme; Value = $Value }
    if ($script:failRestore -and $Value -ne 0) { throw 'Mock restore failure' }
    if ($script:case -eq 'write-denied' -and $Value -eq 0) { throw 'Mock policy denied' }
    $script:fakeAc = $Value
    if ($script:case -eq 'apply-failed' -and $Value -eq 0) { throw 'Mock apply failed after write' }
    if ($script:cancelOnWrite) { Set-Content -LiteralPath $script:stopFile -Value 'test-session' }
}
function Set-IdleWake {
    param([bool]$Enabled)
    if ($script:case -eq 'idle-failed' -and $Enabled) { throw 'Mock idle request failed' }
    $script:wake = $Enabled
}
function Test-OnAC {
    $script:acChecks++
    if ($script:case -eq 'battery-start') { return $false }
    if ($script:case -eq 'unplug-start') { return $script:acChecks -eq 1 }
    if ($script:case -eq 'unplug') { return $script:tick -eq 0 }
    return $true
}
function Get-ConnectedWifi {
    if ($script:case -eq 'wifi-start' -or ($script:case -eq 'wifi-loss' -and $script:tick -ge 5)) { return $null }
    if ($script:case -eq 'sensor-error' -and $script:tick -ge 5) { throw 'Mock network sensor failed' }
    [pscustomobject]@{ Id = $(if ($script:tick -eq 0) { 'wifi-one' } else { 'wifi-two' }); Name = 'Mock Wi-Fi' }
}
function Test-OwnerAlive { param($ProcessId, $Started) return $script:case -ne 'owner-exit' }
function Start-Sleep {
    param($Seconds)
    $script:tick++
    if ($script:tick -gt 12) { throw 'Test loop exceeded bound' }
    if ($script:case -eq 'plan-change') { $script:fakeScheme = '11111111-1111-1111-1111-111111111111' }
    if ($script:case -eq 'policy-change') { $script:fakeAc = 2 }
    if ($script:case -eq 'restore-failed') { $script:failRestore = $true }
    if ($script:case -in @('off', 'restore-failed') -or $script:tick -eq 10) {
        Set-Content -LiteralPath $script:stopFile -Value 'test-session'
    }
}
function Enter-Sleep { throw 'FAIL: Sleep requested' }
function Enter-Shutdown { throw 'FAIL: Shutdown requested' }

function Run-Case {
    param([string]$Name, [int]$Ac = 1, [int]$Battery = 1, [switch]$ExpectError, [string]$Reason = '')
    Reset-Test $Name $Ac $Battery
    if ($Name -eq 'cancel-start') { $script:cancelOnWrite = $true }
    if ($Name -eq 'cancel-before') { Set-Content -LiteralPath $script:stopFile -Value 'test-session' }
    if ($Name -eq 'stale-stop') { Set-Content -LiteralPath $script:stopFile -Value 'previous-session' }
    $errorSeen = $false
    try { Invoke-AwakeSession 'test-session' } catch { $errorSeen = $true }
    Assert ($errorSeen -eq [bool]$ExpectError) "$Name error behavior"
    Assert (-not $script:wake) "$Name releases idle request"
    Assert ($script:fakeBattery -eq $Battery) "$Name preserves battery setting"
    if ($Name -eq 'restore-failed') {
        Assert (Test-Path -LiteralPath $script:journalFile) 'failed recovery retains journal'
        $status = Get-Content $script:statusFile -Raw | ConvertFrom-Json
        Assert ($status.State -eq 'Warning') 'failed recovery publishes warning'
        $script:failRestore = $false
        Restore-LidSettings
        Assert ($script:fakeAc -eq $Ac) 'recovery retry restores original setting'
    } elseif ($Name -eq 'policy-change') {
        Assert ($script:fakeAc -eq 2) 'preserves external policy change'
    } else { Assert ($script:fakeAc -eq $Ac) "$Name restores original AC setting" }
    Assert (-not (Test-Path -LiteralPath $script:journalFile)) "$Name completes recovery"
    if ($Reason) {
        $status = Get-Content $script:statusFile -Raw | ConvertFrom-Json
        Assert ($status.Detail -match $Reason) "$Name publishes expected reason"
    }
    if ($Name -in @('battery-start','wifi-start','cancel-before')) { Assert ($script:writes.Count -eq 0) "$Name performs no setting writes" }
    if ($Name -eq 'plan-change') {
        Assert ($script:fakeScheme -ne $script:originalScheme) 'does not switch power plan back'
        Assert ($script:otherAc -eq 2) 'does not modify new plan'
        Assert (@($script:writes | Where-Object Scheme -ne $script:originalScheme).Count -eq 0) 'writes only original plan'
    }
    $script:passed++
    Write-Output "PASS $Name (original AC=$Ac, battery=$Battery)"
}

try {
    # The exact reported transition: active on AC -> unplug while working.
    Run-Case 'unplug' -Reason 'Unplugged'
    Run-Case 'unplug' -Ac 2 -Battery 0 -Reason 'Unplugged'
    Run-Case 'unplug' -Ac 0 -Battery 2 -Reason 'Unplugged'
    Run-Case 'unplug' -Ac 3 -Battery 3 -Reason 'Unplugged'
    Run-Case 'wifi-loss' -Reason 'Wi-Fi disconnected'
    Run-Case 'off'
    Run-Case 'owner-exit' -Reason 'Panel closed'
    Run-Case 'battery-start' -ExpectError
    Run-Case 'wifi-start' -ExpectError
    Run-Case 'unplug-start' -Reason 'Unplugged'
    Run-Case 'cancel-start'
    Run-Case 'cancel-before'
    Run-Case 'stale-stop'
    Run-Case 'wifi-roam'
    Run-Case 'plan-change'
    Run-Case 'policy-change'
    Run-Case 'write-denied' -ExpectError
    Run-Case 'apply-failed' -ExpectError
    Run-Case 'idle-failed' -ExpectError
    Run-Case 'sensor-error' -ExpectError
    Run-Case 'restore-failed' -ExpectError

    Reset-Test 'crash-recovery' 2 3
    Write-JsonAtomic $script:journalFile @{ Version=1; Scheme=$script:originalScheme; Ac=2 }
    $script:fakeAc = 0
    Restore-LidSettings
    Assert ($script:fakeAc -eq 2 -and $script:fakeBattery -eq 3) 'crash recovery restores only AC'
    $script:passed++; 'PASS persisted crash recovery'

    $source = Get-Content -LiteralPath $CorePath -Raw
    Assert ($source -notmatch 'SetSuspendState|shutdown\.exe|/setdcvalueindex') 'no sleep, shutdown or DC-write path exists'
    $script:passed++; 'PASS forbidden power actions absent'
    Write-Output "$script:passed tests passed. No real power settings changed."
} finally {
    # Delete only files created by this harness in its unique temporary directory.
    Get-ChildItem -LiteralPath $testRoot -File | Remove-Item -Force
    Remove-Item -LiteralPath $testRoot
}
