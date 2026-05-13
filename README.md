<#
.SYNOPSIS
    Compiles Update-GamingServices.ps1 into a standalone .exe using PS2EXE.

.DESCRIPTION
    Run this once on your Windows machine to produce Update-GamingServices.exe.
    The CI workflow in .github/workflows/build.yml does the same automatically
    on every tag push.

.EXAMPLE
    .\build.ps1
#>

[CmdletBinding()]
param(
    [string]$Version = '1.0.0'
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host 'Installing PS2EXE module...' -ForegroundColor Cyan
    Set-PSRepository PSGallery -InstallationPolicy Trusted
    Install-Module -Name ps2exe -Scope CurrentUser -Force
}

Import-Module ps2exe

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src  = Join-Path $here 'Update-GamingServices.ps1'
$dst  = Join-Path $here 'Update-GamingServices.exe'

Write-Host "Compiling $src -> $dst" -ForegroundColor Cyan

Invoke-PS2EXE `
    -InputFile $src `
    -OutputFile $dst `
    -Title 'Forza Horizon 6 - Gaming Services Updater' `
    -Description 'Updates Microsoft Gaming Services for Forza Horizon 6' `
    -Product 'Update-GamingServices' `
    -Company 'OSS' `
    -Version $Version `
    -RequireAdmin

Write-Host ''
Write-Host "Built: $dst" -ForegroundColor Green
