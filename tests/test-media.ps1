$ErrorActionPreference='Stop'
Add-Type -Path @((Join-Path $PSScriptRoot '..\src\lid-vibe-media.cs'),(Join-Path $PSScriptRoot 'MediaKeysChecks.cs'))
[MediaKeysChecks]::Run()
