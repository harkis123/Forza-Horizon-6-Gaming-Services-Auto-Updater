# Update-GamingServices

PowerShell automation that brings **Microsoft Gaming Services** up to the version required by **Forza Horizon 6** on PC (Xbox app or Steam).

## Why this exists

Before Forza Horizon 6 will launch on PC, the `Microsoft.GamingServices` AppX package must be at version **36.113.2002 or higher**. If it isn't, the game refuses to start and shows:

> *Forza Horizon 6 must be run with a later version of Gaming Services.*
> *It has been detected that your system is running an older version.*

Microsoft's [official fix](https://support.forza.net/hc/en-us/articles/51646424423827) tells the user to open the Microsoft Store, click *Library* → *Get updates*, find Gaming Services in the list, and click Update. That works for one machine and one user. It does not scale when you need to update several machines, push the fix to friends, or deploy it through Intune / GPO.

This script automates that update path with sensible fallbacks and proper logging.

## What it does

1. Reads the installed `Microsoft.GamingServices` version across **all users** on the machine.
2. If it's already at or above the minimum required version, exits cleanly.
3. Otherwise, attempts updates in this order:
   - **winget** with the `msstore` source — fastest, fully silent.
   - **Microsoft Store WMI update scan** via `MDM_EnterpriseModernAppManagement_AppManagement01` — fallback for systems without winget, or where winget fails.
   - **Direct Store deep-link** (`ms-windows-store://pdp/?productid=...`) — last-resort interactive fallback.
4. Re-checks the installed version and writes everything to `%TEMP%\GamingServicesUpdate.log`.

## Requirements

- Windows 10 (1809+) or Windows 11
- Administrator rights — the script self-elevates by default
- Microsoft Store available and not blocked by policy

## Quick start

From a regular PowerShell prompt:

```powershell
powershell -ExecutionPolicy Bypass -File .\Update-GamingServices.ps1
```

If it isn't already running as admin, a UAC prompt will appear and the script will re-launch itself elevated.

You can also just right-click `Update-GamingServices.ps1` → *Run with PowerShell*.

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `MinimumVersion` | `36.113.2002` | Minimum acceptable Gaming Services version |
| `ProductId` | `9MWPM2CQNLHN` | Microsoft Store product ID for Gaming Services |
| `LogPath` | `$env:TEMP\GamingServicesUpdate.log` | Where the log file is written |
| `WaitSeconds` | `60` | How long to wait for the Store to finish downloading after a WMI scan |
| `NoElevate` | *(off)* | Skip self-elevation — use when already running as SYSTEM (Intune, GPO) |

## Deployment scenarios

### One-off (share with a friend)
Send the `.ps1`, they double-click, accept UAC.

### Microsoft Intune
*Devices → Scripts and remediations → Platform scripts → Add*
- Run as: **System**
- Run in 64-bit PowerShell: **Yes**
- Pass `-NoElevate` since SYSTEM is already privileged.

### Group Policy
*Computer Configuration → Policies → Windows Settings → Scripts → Startup*
Add the `.ps1` with `-NoElevate`.

### SCCM / MECM
Standard package with this program:
```
powershell.exe -ExecutionPolicy Bypass -File Update-GamingServices.ps1 -NoElevate
```

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Already up to date, or successfully updated |
| `1` | Automatic update failed — manual intervention needed |
| `2` | Admin rights required but `-NoElevate` was set |

## Troubleshooting

- **`winget` not found** — install [App Installer](https://apps.microsoft.com/detail/9NBLGGH4NNS1) from the Store. The script falls back to the WMI method automatically.
- **Store blocked by policy** — no automated path can work; the Microsoft Store has to be reachable.
- **Script reports OK but the game still complains** — reboot. AppX manifest re-registration can lag behind the actual install.
- **Stuck on "spinning wheel" after the game launches** — separate problem from this script. Try resetting Gaming Services from *Settings → Apps → Installed apps → Gaming Services → Advanced options → Reset*.

## License

MIT — do whatever you want with it, no warranty.
