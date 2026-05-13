name: Build EXE

on:
  push:
    tags: ['v*']
  workflow_dispatch:

permissions:
  contents: write

jobs:
  build:
    runs-on: windows-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install PS2EXE
        shell: powershell
        run: |
          Set-PSRepository PSGallery -InstallationPolicy Trusted
          Install-Module -Name ps2exe -Scope CurrentUser -Force

      - name: Determine version
        id: ver
        shell: powershell
        run: |
          $ref = "${{ github.ref }}"
          if ($ref -like 'refs/tags/v*') {
            $version = $ref -replace '^refs/tags/v',''
          } else {
            $version = '0.0.0-dev'
          }
          "version=$version" | Out-File -FilePath $env:GITHUB_OUTPUT -Append
          Write-Host "Building version $version"

      - name: Compile to EXE
        shell: powershell
        run: |
          Invoke-PS2EXE `
            -InputFile .\Update-GamingServices.ps1 `
            -OutputFile .\Update-GamingServices.exe `
            -Title 'Forza Horizon 6 - Gaming Services Updater' `
            -Description 'Updates Microsoft Gaming Services for Forza Horizon 6' `
            -Product 'Update-GamingServices' `
            -Company 'OSS' `
            -Version '${{ steps.ver.outputs.version }}' `
            -RequireAdmin

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: Update-GamingServices
          path: Update-GamingServices.exe

      - name: Attach to release
        if: startsWith(github.ref, 'refs/tags/')
        uses: softprops/action-gh-release@v2
        with:
          files: Update-GamingServices.exe
          generate_release_notes: true
