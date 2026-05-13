# Forza Horizon 6 - Gaming Services Updater

A one-click tool that updates **Microsoft Gaming Services** to the version required by **Forza Horizon 6** on PC (Xbox app and Steam).

## The problem

When you try to launch Forza Horizon 6, you may see this error:

> *Forza Horizon 6 must be run with a later version of Gaming Services.*
> *It has been detected that your system is running an older version.*

The game requires Gaming Services version **36.113.2002 or newer**. Microsoft's official fix tells you to open the Microsoft Store, click *Library*, then *Get updates*, find Gaming Services in a long list, and click Update. Many users either don't know how to do this or can't find the right button.

This tool does it for you.

## How to use it (for players)

1. Go to the [**Releases**](../../releases/latest) page.
2. Download `Update-GamingServices.exe`.
3. Double-click it.
4. Click **Yes** when Windows asks for permission (UAC prompt).
5. Wait until you see *"You are ready to play Forza Horizon 6"*.
6. Press any key to close the window.
7. Launch Forza Horizon 6.

That's it. No installation, no settings, no PowerShell knowledge needed.

## How it works

The tool tries three methods, in order, and stops at the first one that succeeds:

1. **winget** with the `msstore` source — fast and fully silent.
2. **Microsoft Store update scan** triggered via WMI — fallback when winget isn't available.
3. **Microsoft Store page** opened directly — last resort, you click *Update* yourself.

Everything is logged to `%TEMP%\GamingServicesUpdate.log` for troubleshooting.

## Requirements

- Windows 10 (1809 or newer) or Windows 11
- An internet connection
- Microsoft Store available (not blocked by your organization)

## For IT admins / unattended deployment

The same `.exe` (or the raw `.ps1`) works in Intune, GPO, and SCCM:

```
Update-GamingServices.exe -NoElevate -NoPause
```

| Parameter | Default | Description |
|---|---|---|
| `-MinimumVersion` | `36.113.2002` | Required version |
| `-NoElevate` | off | Skip UAC self-elevation (use when already SYSTEM) |
| `-NoPause` | off | Don't wait for keypress on exit |
| `-LogPath` | `%TEMP%\GamingServicesUpdate.log` | Log file location |

Exit codes: `0` = success, `1` = update failed, `2` = no admin rights.

## For developers

### Build the `.exe` locally

```powershell
.\build.ps1
```

This installs the [PS2EXE](https://github.com/MScholtes/PS2EXE) module and compiles `Update-GamingServices.ps1` into `Update-GamingServices.exe` with an embedded admin manifest.

### Build via GitHub Actions

Push a tag like `v1.0.0` and the workflow in `.github/workflows/build.yml` compiles the `.exe` on a Windows runner and attaches it to a GitHub release automatically.

```bash
git tag v1.0.0
git push origin v1.0.0
```

## License

MIT
