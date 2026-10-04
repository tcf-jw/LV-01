# Changelog

## 0.3.0 — 2026-10-04

- Added a physical-style VOL fader beneath the media keys, with keyboard and scroll controls.
- The fader follows Windows main output volume and device changes. Mute stays unchanged.
- Disconnected outputs disable the fader until audio becomes available again. Opening or closing the app never resets volume.
- Added volume validation and WPF interaction checks using simulated audio devices; updated previews and the miniature icon.

## 0.2.0 — 2026-10-04

- Added previous, play/pause and next media keys beneath the scene and tempo dials.
- Windows chooses the receiving player, as with keyboard media keys. Controls work on battery and while Stay Awake is off.
- Added hover explanations and brief send/failure feedback; power warnings stay visible.
- Added eight native-boundary tests and WPF checks without sending commands to running players.
- Updated the miniature icon, previews and packaged executable.

## 0.1.0 — 2026-10-04

First shareable Windows release of LV-01, previously developed as Lid Vibe.

- Automatic AC + Wi-Fi Stay Awake with exact AC-policy restoration and crash recovery.
- Unplugging and Wi-Fi loss release the override; no forced sleep or battery-policy changes.
- Native WPF device interface, symbol keys, Japanese accents, light/dark themes and five accents.
- Pixel cow, orbit and scope scenes with dials, effects and artwork freeze.
- Single Windows executable, miniature device icon, per-user settings and recovery files.
- MIT license, source build, safe tests and Windows CI.

Known limits: unsigned binary; Windows 11 x64 tested; physical lid-close and unplug tests remain unverified; behavior varies with hardware and policy.
