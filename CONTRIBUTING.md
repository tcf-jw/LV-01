# Contributing

Open an issue with the Windows version, LV-01 version, connection state and what happened. Do not post private network names or unredacted local paths. For design changes, include light and dark screenshots.

## Local checks

Run these in Windows PowerShell 5.1 from the repository root:

```powershell
./tests/test-lid-vibe.ps1
./tests/test-lid-vibe-auto.ps1
./tests/test-lid-vibe-design.ps1
./tests/test-media.ps1
./tests/test-volume.ps1
./build.ps1 -Test
```

Power logic tests mock the OS boundaries. Never trigger real Sleep, Hibernate or Shut down as a test. Keep battery settings untouched, preserve the original AC policy, and keep recovery data until cleanup succeeds. Artwork and media controls must not change power state. Media tests must mock the input boundary so they never interrupt running players.
Volume tests inject simulated readers and writers. Do not change the host's volume or mute during automated tests.

Update the README or behavior documentation with changed behavior. Use a focused branch and a Conventional Commit. Public screenshots should use preview mode and should not contain personal data.

The package tests launch the compiled EXE twice in an isolated temporary folder. They verify WPF interaction checks, payload repair and preservation of recovery/preferences. They remove only their own validated test folder afterward.
