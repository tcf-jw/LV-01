$ErrorActionPreference='Stop'
Add-Type -Path (Join-Path $PSScriptRoot '..\src\lid-vibe-volume.cs')
function Assert { param($Condition,[string]$Name) if(-not $Condition){throw ('FAIL '+$Name)}; 'PASS '+$Name }
Assert ([LV01.MasterVolume]::ToScalar(-1) -eq 0) 'volume clamps below zero'
Assert ([LV01.MasterVolume]::ToScalar(101) -eq 1) 'volume clamps above 100'
Assert ([Math]::Abs([LV01.MasterVolume]::ToScalar(42)-0.42) -lt 0.00001) 'percent maps to Windows scalar'
foreach ($invalid in @([double]::NaN,[double]::PositiveInfinity,[double]::NegativeInfinity)) {
    $rejected=$false
    try { [LV01.MasterVolume]::Set($invalid) } catch { $rejected=$_.Exception.InnerException -is [ArgumentOutOfRangeException] }
    Assert $rejected 'invalid volume rejected before touching audio devices'
}
# Device access is covered by the WPF smoke suite with injected readers/writers.
# CI has no guaranteed audio endpoint and must never alter the host's volume.
