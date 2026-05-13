<#
.SYNOPSIS
    Updates Microsoft Gaming Services to the minimum version required by Forza Horizon 6 (>= 36.113.2002).

.DESCRIPTION
    Designed to be compiled into a single .exe with PS2EXE so end users can
    simply double-click and follow the UAC prompt. Also runs fine as a raw .ps1
    for unattended deployment (Intune, GPO, SCCM) via the -NoElevate switch.

    Workflow:
      1. Self-elevates via UAC if needed (skipped with -NoElevate).
      2. Reads the current Microsoft.GamingServices version across all users.
      3. If below the minimum, attempts updates in order:
           a) winget via the msstore source
           b) Microsoft Store WMI UpdateScanMethod trigger
           c) Microsoft Store deep-link (interactive fallback)
      4. Re-verifies, logs the result, and waits for a keypress before exiting
         (so the user can read the outcome).
#>

[CmdletBinding()]
param(
    [Version] $MinimumVersion = [Version]'36.113.2002',
    [string]  $ProductId      = '9MWPM2CQNLHN',
    [string]  $PackageName    = 'Microsoft.GamingServices',
    [string]  $LogPath        = (Join-Path $env:TEMP 'GamingServicesUpdate.log'),
    [int]     $WaitSeconds    = 60,
    [switch]  $NoElevate,
    [switch]  $NoPause
)

$script:exitCode = 0

# ---------- Helpers ----------
function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR','OK')][string]$Level = 'INFO'
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
    switch ($Level) {
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'OK'    { Write-Host $line -ForegroundColor Green }
        default { Write-Host $line }
    }
}

function Write-Banner {
    Write-Host ''
    Write-Host '================================================================' -ForegroundColor Cyan
    Write-Host '  Forza Horizon 6 - Gaming Services Updater' -ForegroundColor Cyan
    Write-Host '================================================================' -ForegroundColor Cyan
    Write-Host ''
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Elevation {
    Write-Log 'Relaunching with administrator privileges...'
    $exe = if ($PSCommandPath) { 'powershell.exe' } else { (Get-Process -Id $PID).Path }
    $argList = if ($PSCommandPath) {
        @('-NoProfile','-ExecutionPolicy','Bypass','-File', ('"{0}"' -f $PSCommandPath))
    } else {
        @()  # compiled .exe - just relaunch itself elevated
    }
    try {
        Start-Process -FilePath $exe -ArgumentList $argList -Verb RunAs -ErrorAction Stop
    } catch {
        Write-Log "Elevation failed or was cancelled: $($_.Exception.Message)" 'ERROR'
        $script:exitCode = 2
        return $false
    }
    return $true
}

function Get-InstalledVersion {
    try {
        $pkg = Get-AppxPackage -Name $PackageName -AllUsers -ErrorAction Stop |
               Sort-Object { [Version]$_.Version } -Descending |
               Select-Object -First 1
        if ($pkg) { return [Version]$pkg.Version }
    } catch {
        Write-Log "Get-AppxPackage error: $($_.Exception.Message)" 'WARN'
    }
    return $null
}

function Test-VersionOk {
    param([Version]$Current)
    return ($Current -and $Current -ge $MinimumVersion)
}

# ---------- Update methods ----------
function Update-WithWinget {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log 'winget not found on this system - skipping.' 'WARN'
        return $false
    }

    Write-Log "Trying winget (msstore: $ProductId)..."

    $cmds = @(
        @('upgrade','--id',$ProductId,'--exact','--source','msstore',
          '--accept-source-agreements','--accept-package-agreements',
          '--silent','--disable-interactivity'),
        @('install','--id',$ProductId,'--exact','--source','msstore',
          '--accept-source-agreements','--accept-package-agreements',
          '--silent','--disable-interactivity')
    )

    foreach ($args in $cmds) {
        $output = & winget @args 2>&1
        $code = $LASTEXITCODE
        $output | ForEach-Object { Write-Log "  winget> $_" }
        Write-Log "  winget exit code: 0x$('{0:X8}' -f $code) ($code)"
        if ($code -in 0, -1978335189) { return $true }
    }
    return $false
}

function Invoke-StoreUpdateScan {
    Write-Log 'Triggering Microsoft Store update scan (MDM WMI)...'
    try {
        $ns  = 'root\cimv2\mdm\dmmap'
        $cls = 'MDM_EnterpriseModernAppManagement_AppManagement01'
        $obj = Get-CimInstance -Namespace $ns -ClassName $cls -ErrorAction Stop
        $res = Invoke-CimMethod -InputObject $obj -MethodName UpdateScanMethod -ErrorAction Stop
        Write-Log "UpdateScanMethod return: $($res.ReturnValue)"
        return $true
    } catch {
        Write-Log "WMI Store scan failed: $($_.Exception.Message)" 'WARN'
        return $false
    }
}

function Open-StorePage {
    Write-Log 'Opening Microsoft Store page for manual update...'
    try {
        Start-Process "ms-windows-store://pdp/?productid=$ProductId"
    } catch {
        Write-Log "Could not open Store: $($_.Exception.Message)" 'WARN'
    }
}

function Wait-ForKeypress {
    if ($NoPause -or -not [Environment]::UserInteractive) { return }
    Write-Host ''
    Write-Host 'Press any key to exit...' -ForegroundColor Cyan
    try   { $null = [System.Console]::ReadKey($true) }
    catch { Read-Host | Out-Null }
}

# ---------- Main ----------
try {
    Write-Banner
    Write-Log '=== Gaming Services update started ==='
    Write-Log "Host: $env:COMPUTERNAME | User: $env:USERNAME"
    Write-Log "Required minimum version: $MinimumVersion"

    if (-not (Test-Admin)) {
        if ($NoElevate) {
            Write-Log 'Admin rights required, but -NoElevate is set. Aborting.' 'ERROR'
            $script:exitCode = 2
            return
        }
        $null = Invoke-Elevation
        # the elevated copy takes over; this instance exits
        return
    }

    $current = Get-InstalledVersion
    if ($current) {
        Write-Log "Current Microsoft.GamingServices version: $current"
    } else {
        Write-Log 'Microsoft.GamingServices not detected on this system.' 'WARN'
    }

    if (Test-VersionOk -Current $current) {
        Write-Log 'Version is sufficient - nothing to do.' 'OK'
        Write-Host ''
        Write-Host 'You are ready to play Forza Horizon 6.' -ForegroundColor Green
        $script:exitCode = 0
        return
    }

    # 1. winget
    $ok = Update-WithWinget

    # 2. Store WMI scan + wait
    if (-not $ok) {
        [void](Invoke-StoreUpdateScan)
        Write-Log "Waiting ${WaitSeconds}s for the Store to download..."
        Start-Sleep -Seconds $WaitSeconds
    }

    $current = Get-InstalledVersion
    if (Test-VersionOk -Current $current) {
        Write-Log "Successfully updated to: $current" 'OK'
        Write-Host ''
        Write-Host 'You are ready to play Forza Horizon 6.' -ForegroundColor Green
        $script:exitCode = 0
        return
    }

    # 3. Manual fallback
    Write-Log "Automatic update failed. Current version: $current" 'WARN'
    Open-StorePage
    Write-Host ''
    Write-Host 'The Microsoft Store has been opened.' -ForegroundColor Yellow
    Write-Host 'Please click "Update" or "Get" on the Gaming Services page,' -ForegroundColor Yellow
    Write-Host 'wait for it to finish, then launch Forza Horizon 6 again.' -ForegroundColor Yellow
    $script:exitCode = 1
}
finally {
    Wait-ForKeypress
}

exit $script:exitCode
