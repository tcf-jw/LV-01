param([string]$UiPath = (Join-Path $PSScriptRoot '..\src\lid-vibe-ui.ps1'))
$ErrorActionPreference = 'Stop'
$tokens=$null; $parseErrors=$null
$ast = [Management.Automation.Language.Parser]::ParseFile($UiPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors) { throw $parseErrors[0] }
$decision = $ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-AutoCheck'}, $false)
if (-not $decision) { throw 'Auto decision function missing' }
. ([scriptblock]::Create($decision.Extent.Text))
function Start-AwakeMonitor { $script:starts++; $script:monitor = [pscustomobject]@{Mock=$true} }
function Reset-Case {
    $script:starts=0; $script:monitor=$null; $script:readySamples=0
    $script:autoPaused=$false; $script:autoFaulted=$false; $script:state='Off'
}
function Assert-Starts { param($Expected,$Name)
    if ($script:starts -ne $Expected) { throw "FAIL $Name : expected $Expected, got $script:starts" }
    "PASS $Name"
}
Reset-Case
Invoke-AutoCheck $false; Invoke-AutoCheck $false
Assert-Starts 0 'battery or offline never starts'
Reset-Case
Invoke-AutoCheck $true
Assert-Starts 0 'one eligible sample waits'
Invoke-AutoCheck $true
Assert-Starts 1 'stable AC and Wi-Fi starts automatically'
Invoke-AutoCheck $true; Invoke-AutoCheck $true
Assert-Starts 1 'active worker is not duplicated'
Reset-Case
Invoke-AutoCheck $true; Invoke-AutoCheck $false; Invoke-AutoCheck $true
Assert-Starts 0 'brief connection resets stability delay'
Reset-Case
$script:autoPaused=$true
Invoke-AutoCheck $true; Invoke-AutoCheck $false; Invoke-AutoCheck $true; Invoke-AutoCheck $true
Assert-Starts 0 'Turn Off remains paused across reconnection'
$script:autoPaused=$false
Invoke-AutoCheck $true; Invoke-AutoCheck $true
Assert-Starts 1 'manual resume permits automatic operation'
Reset-Case
$script:autoFaulted=$true
Invoke-AutoCheck $true; Invoke-AutoCheck $true
Assert-Starts 0 'failure does not create an automatic retry loop'
Reset-Case
$script:state='Warning'
Invoke-AutoCheck $true; Invoke-AutoCheck $true
Assert-Starts 0 'unresolved warning blocks automatic startup'
Reset-Case
$script:state='Stopping'
Invoke-AutoCheck $true; Invoke-AutoCheck $true
Assert-Starts 0 'cleanup finishes before a new start'
Reset-Case
Invoke-AutoCheck $true; Invoke-AutoCheck $true
$script:monitor=$null
Invoke-AutoCheck $false
Invoke-AutoCheck $true; Invoke-AutoCheck $true
Assert-Starts 2 'guard stop re-arms after stable reconnection'
'11 auto checks passed. No process or power changes.'
