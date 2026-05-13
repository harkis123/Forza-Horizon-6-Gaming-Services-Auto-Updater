<#
.SYNOPSIS
    Updates Microsoft Gaming Services to the minimum version required by Forza Horizon 6 (>= 36.113.2002).

.DESCRIPTION
    Designed for unattended deployment across multiple users / machines
    (Intune, GPO, SCCM, or a simple .ps1 run by an end user).

    Workflow:
      1. Checks for admin rights - self-elevates if not present (unless -NoElevate).
      2. Reads the current Microsoft.GamingServices version across all users.
      3. If below the minimum, attempts updates in order:
           a) winget via the msstore source
           b) Microsoft Store WMI UpdateScanMethod trigger
           c) Microsoft Store deep-link (interactive fallback)
      4. Re-verifies and logs the result.

.PARAMETER MinimumVersion
    Minimum acceptable Gaming Services version. Default: 36.113.2002

.PARAMETER ProductId
    Microsoft Store product ID. Default: 9MWPM2CQNLHN (Gaming Services)

.PARAMETER NoElevate
    Do not self-elevate. Use in contexts that already run as SYSTEM
    (Intune platform scripts, GPO computer startup, etc.).

.PARAMETER LogPath
    Path for the log file. Default: $env:TEMP\GamingServicesUpdate.log

.EXAMPLE
    .\Update-GamingServices.ps1

.EXAMPLE
    .\Update-GamingServices.ps1 -NoElevate -Verbose

.NOTES
    Supported: Windows 10 (1809+) and Windows 11
    Requires: administrator privileges
    Exit codes: 0 = OK, 1 = update failed, 2 = no admin rights with -NoElevate
#>

[CmdletBinding()]
param(
    [Version] $MinimumVersion = [Version]'36.113.2002',
    [string]  $ProductId      = '9MWPM2CQNLHN',
    [string]  $PackageName    = 'Microsoft.GamingServices',
    [string]  $LogPath        = (Join-Path $env:TEMP 'GamingServicesUpdate.log'),
    [int]     $WaitSeconds    = 60,
    [switch]  $NoElevate
)

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

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Elevation {
    Write-Log 'Relaunching with administrator privileges...'
    $argList = @(
        '-NoProfile','-ExecutionPolicy','Bypass',
        '-File', ('"{0}"' -f $PSCommandPath),
        '-MinimumVersion', $MinimumVersion.ToString(),
        '-LogPath', ('"{0}"' -f $LogPath)
    )
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -ErrorAction Stop
    } catch {
        Write-Log "Elevation failed: $($_.Exception.Message)" 'ERROR'
        exit 2
    }
    exit 0
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

    # Try upgrade first; if not applicable, try install (acts as upgrade if installed)
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
        # 0 = OK; -1978335189 (0x8A15002B) = no applicable upgrade (already current)
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

# ---------- Main ----------
Write-Log '=== Gaming Services update started ===' 'INFO'
Write-Log "Host: $env:COMPUTERNAME | User: $env:USERNAME"
Write-Log "Required minimum version: $MinimumVersion"

if (-not (Test-Admin)) {
    if ($NoElevate) {
        Write-Log 'Admin rights required, but -NoElevate is set. Aborting.' 'ERROR'
        exit 2
    }
    Invoke-Elevation
}

$current = Get-InstalledVersion
if ($current) {
    Write-Log "Current Microsoft.GamingServices version: $current"
} else {
    Write-Log 'Microsoft.GamingServices not detected on this system.' 'WARN'
}

if (Test-VersionOk -Current $current) {
    Write-Log 'Version is sufficient - nothing to do.' 'OK'
    exit 0
}

# 1. winget
$ok = Update-WithWinget

# 2. Store WMI scan + wait (Store downloads in background)
if (-not $ok) {
    [void](Invoke-StoreUpdateScan)
    Write-Log "Waiting ${WaitSeconds}s for the Store to download..."
    Start-Sleep -Seconds $WaitSeconds
}

# Verify
$current = Get-InstalledVersion
if (Test-VersionOk -Current $current) {
    Write-Log "Successfully updated to: $current" 'OK'
    exit 0
}

# 3. Fallback - manual
Write-Log "Automatic update failed. Current version: $current" 'WARN'
Open-StorePage
Write-Log 'Manual action in the Microsoft Store window is required.' 'WARN'
exit 1
