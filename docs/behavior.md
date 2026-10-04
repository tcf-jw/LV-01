# Behavior and recovery

## Everyday changes

| State 1 | State 2 | Result |
|---|---|---|
| Auto ready, plugged in, Wi-Fi connected | Two successful checks, or click Stay Awake | AC lid-close becomes Do nothing; idle sleep is prevented. |
| On, plugged in | Close or reopen the lid | Work keeps running. The screen may turn off normally. |
| On, lid open | Unplug the charger | Stay Awake turns off after the next power check, normally within one second. Windows handles battery use normally. The app does not request Sleep or hibernation. |
| On, plugged in | Wi-Fi disconnects | Stay Awake turns off at the next Wi-Fi check, normally within five seconds. Windows controls sleep again. |
| On | Click Turn Off or close the panel | The idle-sleep request is released and the previous AC lid action is restored. Turn Off pauses auto; closing exits the app. |

## Other situations

| State 1 | State 2 | Result |
|---|---|---|
| On, lid already closed | Unplug or lose Wi-Fi | The app turns off. Windows resumes its normal rules. An already-closed lid may not cause a new lid-close event, so immediate sleep is not guaranteed. |
| Stopped after unplugging or Wi-Fi loss | Reconnect power and Wi-Fi | Restarts automatically after two successful checks, normally within 5–10 seconds. If you clicked Turn Off, it stays paused. |
| Off, battery power or no Wi-Fi | Try to start | Stay Awake is disabled. The command line also rejects this without changing power settings. |
| On | Minimize the panel or let the display turn off | Stay Awake continues while AC and Wi-Fi remain available. |
| On | Choose Sleep, Hibernate, or Shut down in Windows | Windows controls that action. LV-01 does not wake the laptop. After a manual wake, an existing session rechecks power and Wi-Fi. |

## Recovery and less common changes

| State 1 | State 2 | Result |
|---|---|---|
| On | Another connected Wi-Fi interface replaces the first | Continues if a connected Wi-Fi interface is present at the check. It does not require the same adapter. |
| On | Router loses internet but Wi-Fi stays connected | Continues. The guard checks a Wi-Fi interface with an IP address, not internet reachability or VPN health. |
| On | Power plan or AC lid setting changes | Turns off and pauses auto at the next five-second settings check. Restores its old plan if needed; preserves a new plan or a nonzero external lid setting. |
| On | Panel or worker crashes | A surviving worker notices a missing panel; a surviving panel restores settings after its worker exits. If both terminate, reopen LV-01 to recover the saved AC setting. |
| Starting or stopping | Windows denies a setting change | Shows a warning and blocks automatic retries. Click Stay Awake for a deliberate retry. Failed restoration keeps its recovery file so Turn Off can retry cleanup. |

Battery lid actions, battery timers, screen timeout, power-button behavior, and critical-battery protection are never changed. Your previously configured AC lid action is restored rather than replaced with a fixed Sleep value. 

Use **Windows Shut down** before putting the laptop in a bag. Neither Wi-Fi nor charger state proves that the laptop is safe to pack.


## Recovery files

The executable stores these in `%LOCALAPPDATA%\LV-01`:

- `.lid-vibe-restore.json`: original plan and AC lid action, retained until restoration succeeds.
- `.lid-vibe-status.json`: worker state, PID, session ID and update time.
- `.lid-vibe.stop`: a session-specific stop signal.
- `.lid-vibe-preferences.json`: theme, accent, brightness, tempo, scene and motion.

The internal filenames retain the original project name for compatibility. Running the source scripts directly keeps these files beside the scripts unless `LV01_DATA_DIR` is explicitly set. The app and original Lid Vibe scripts share per-user mutex names so they cannot run duplicate panels or workers. Close the older version before opening the EXE.

If restoration is denied, the app keeps its journal and shows a warning. Use Turn Off to retry. If it remains blocked, check the lid action in Windows power settings. Do not clear the recovery file merely to dismiss a warning.
