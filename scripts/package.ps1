#requires -version 5.1
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'common.ps1')

try {
    & (Join-Path $Script:ProjectRoot 'scripts\test.ps1')
    Assert-True ($LASTEXITCODE -eq 0) 'Tests failed; package aborted.'

    & (Join-Path $Script:ProjectRoot 'scripts\build.ps1')
    Assert-True ($LASTEXITCODE -eq 0) 'Build failed; package aborted.'

    $version = Get-ProjectVersion
    $distProject = Join-Path $Script:ProjectRoot 'dist\Windows-BlueScreen-Diagnostic'
    $zipPath = Join-Path (Join-Path $Script:ProjectRoot 'dist') ("Windows-BlueScreen-Diagnostic-v{0}.zip" -f $version)
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($distProject, $zipPath)

    Assert-True (Test-Path -LiteralPath $zipPath) 'ZIP package was not created.'
    Write-Pass "Package created: $zipPath"
    exit 0
}
catch {
    Write-Fail $_.Exception.Message
    exit 1
}
