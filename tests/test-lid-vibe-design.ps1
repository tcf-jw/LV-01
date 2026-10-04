param([string]$DesignPath = (Join-Path $PSScriptRoot '..\src\lid-vibe-design.ps1'))
$ErrorActionPreference='Stop'
$tokens=$null; $parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($DesignPath,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors) { throw $parseErrors[0] }
$function=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-ValidatedPreferences'},$false)
. ([scriptblock]::Create($function.Extent.Text))
function Assert { param($Condition,$Name) if (-not $Condition) { throw "FAIL $Name" }; "PASS $Name" }
$prefs=Get-ValidatedPreferences $null
Assert ($prefs.Theme -eq 'Light' -and $prefs.Accent -eq 'Orange' -and $prefs.Brightness -eq 0.95) 'missing preferences use defaults'
$prefs=Get-ValidatedPreferences ([pscustomobject]@{Theme='Dark';Accent='Cobalt';Brightness=0.65;Tempo=1.3;Motion=$false})
Assert ($prefs.Theme -eq 'Dark' -and $prefs.Accent -eq 'Cobalt' -and -not $prefs.Motion -and $prefs.Brightness -eq 0.65) 'valid preferences round-trip'
$prefs=Get-ValidatedPreferences ([pscustomobject]@{Theme='Unknown';Accent='Bad';Brightness=9;Tempo=-1;Motion='false'})
Assert ($prefs.Theme -eq 'Light' -and $prefs.Accent -eq 'Orange' -and $prefs.Motion) 'invalid names and types use defaults'
Assert ($prefs.Brightness -eq 1 -and $prefs.Tempo -eq 0.5) 'dial bounds are clamped'
$prefs=Get-ValidatedPreferences ([pscustomobject]@{Brightness='NaN';Tempo='Infinity'})
Assert ($prefs.Brightness -eq 0.95 -and $prefs.Tempo -eq 1) 'non-finite values rejected'
$prefs=Get-ValidatedPreferences ([pscustomobject]@{Scene=2})
Assert ($prefs.Scene -eq 2) 'scene choice round-trips'
$prefs=Get-ValidatedPreferences ([pscustomobject]@{Scene=[long]::MaxValue})
Assert ($prefs.Scene -eq 2) 'out-of-range scene clamps without overflow'
$prefs=Get-ValidatedPreferences ([pscustomobject]@{Scene='unknown'})
Assert ($prefs.Scene -eq 0) 'older or invalid scene defaults to the cow'
$priorCulture=[Threading.Thread]::CurrentThread.CurrentCulture
try {
    [Threading.Thread]::CurrentThread.CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo('fr-FR')
    $prefs=Get-ValidatedPreferences ([pscustomobject]@{Brightness='0.6';Tempo='1.2'})
    Assert ($prefs.Brightness -eq 0.6 -and $prefs.Tempo -eq 1.2) 'saved numeric values parse independently of locale'
} finally { [Threading.Thread]::CurrentThread.CurrentCulture=$priorCulture }
. (Join-Path $PSScriptRoot '..\src\lid-vibe.ps1') -LibraryOnly
$saveFunction=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Save-DevicePreferences'},$false)
. ([scriptblock]::Create($saveFunction.Extent.Text))
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('lid-vibe-preferences-test-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    $script:preferencePath=Join-Path $testRoot 'preferences.json'
    $script:preferences=Get-ValidatedPreferences ([pscustomobject]@{Theme='Dark';Accent='Mint';Brightness=0.7;Tempo=1.1;Motion=$false})
    $script:settingsWindow=$null; $isTest=$false
    Save-DevicePreferences
    $restored=Get-ValidatedPreferences (Get-Content -LiteralPath $script:preferencePath -Raw | ConvertFrom-Json)
    Assert ($restored.Theme -eq 'Dark' -and $restored.Accent -eq 'Mint' -and $restored.Brightness -eq 0.7 -and -not $restored.Motion) 'preferences persist to disk and reload'
    $isTest=$true; $script:preferences.Theme='Light'
    Save-DevicePreferences
    Assert ((Get-Content -LiteralPath $script:preferencePath -Raw | ConvertFrom-Json).Theme -eq 'Dark') 'preview mode never saves preferences'
    $isTest=$false; $script:preferencePath=Join-Path $testRoot 'missing\preferences.json'
    Save-DevicePreferences
    Assert ($script:preferenceNote -match 'Could not save') 'write failures are reported without stopping the app'
} finally {
    Get-ChildItem -LiteralPath $testRoot -File | Remove-Item -Force
    Remove-Item -LiteralPath $testRoot
}
'12 preference checks passed. Only isolated temporary files used; no power changes.'
