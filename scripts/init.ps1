#requires -version 5.1
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'common.ps1')

try {
    Write-Check "Project root: $Script:ProjectRoot"
    Assert-True ([bool](Get-Command git -ErrorAction SilentlyContinue)) 'Git is not installed or not in PATH.'
    Write-Pass "Git found: $((git --version) -join ' ')"

    Assert-True ($PSVersionTable.PSVersion.Major -ge 5) 'Windows PowerShell 5.1 or later is required.'
    Write-Pass "PowerShell version: $($PSVersionTable.PSVersion)"

    Test-ProjectStructure
    Write-Pass 'Project structure is present.'

    $gitDir = Join-Path $Script:ProjectRoot '.git'
    if (Test-Path -LiteralPath $gitDir) {
        Write-Pass 'Git repository exists.'
    }
    else {
        Write-Check 'Git repository has not been initialized yet.'
    }

    $remote = git -C $Script:ProjectRoot remote -v 2>$null
    if ($remote) {
        Write-Pass "Git remote configured:`n$remote"
    }
    else {
        Write-Check 'Git remote is not configured.'
    }

    $version = Get-ProjectVersion
    Write-Pass "VERSION is $version"
    Write-Pass 'Development environment check completed.'
    exit 0
}
catch {
    Write-Fail $_.Exception.Message
    exit 1
}
