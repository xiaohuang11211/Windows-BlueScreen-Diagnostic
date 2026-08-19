#requires -version 5.1
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'common.ps1')

try {
    Test-ProjectStructure
    Write-Pass 'Required files exist.'

    foreach ($relativePath in @('src\BlueScreen_Check.ps1','scripts\init.ps1','scripts\test.ps1','scripts\clean.ps1','scripts\package.ps1')) {
        $path = Join-Path $Script:ProjectRoot $relativePath
        $parse = Get-PowerShellParseResult -Path $path
        Assert-True (@($parse.Errors).Count -eq 0) "Parser errors in ${relativePath}: $($parse.Errors | ForEach-Object Message)"
    }
    Write-Pass 'PowerShell parser checks passed.'

    Test-MainScriptSafety
    Write-Pass 'Static safety checks passed.'

    $version = Get-ProjectVersion
    Write-Pass "Version: $version"

    $distRoot = Join-Path $Script:ProjectRoot 'dist'
    $distProject = Join-Path $distRoot 'Windows-BlueScreen-Diagnostic'
    if (Test-Path -LiteralPath $distRoot) {
        Assert-True (Test-SafeRelativePath -Root $Script:ProjectRoot -Path $distRoot) "Refusing to delete outside project root: $distRoot"
        Remove-Item -LiteralPath $distRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $distProject -Force | Out-Null

    Copy-Item -LiteralPath (Join-Path $Script:ProjectRoot 'src\BlueScreen_Check.ps1') -Destination (Join-Path $distProject 'BlueScreen_Check.ps1')
    Copy-Item -LiteralPath (Join-Path $Script:ProjectRoot 'Run_BlueScreen_Check.bat') -Destination $distProject
    Copy-Item -LiteralPath (Join-Path $Script:ProjectRoot 'README.md') -Destination $distProject
    Copy-Item -LiteralPath (Join-Path $Script:ProjectRoot 'VERSION') -Destination $distProject
    Copy-Item -LiteralPath (Join-Path $Script:ProjectRoot 'LICENSE') -Destination $distProject

    Assert-True (Test-Path -LiteralPath (Join-Path $distProject 'BlueScreen_Check.ps1')) 'Build output missing main script.'
    Write-Pass "Build completed: $distProject"
    exit 0
}
catch {
    Write-Fail $_.Exception.Message
    exit 1
}
