#requires -version 5.1
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'common.ps1')

try {
    $targets = @(
        (Join-Path $Script:ProjectRoot 'dist'),
        (Join-Path $Script:ProjectRoot 'tests\.tmp')
    )
    foreach ($target in $targets) {
        if (Test-Path -LiteralPath $target) {
            Assert-True (Test-SafeRelativePath -Root $Script:ProjectRoot -Path $target) "Refusing to clean outside project root: $target"
            Remove-Item -LiteralPath $target -Recurse -Force
            Write-Pass "Cleaned $target"
        }
    }
    New-Item -ItemType Directory -Path (Join-Path $Script:ProjectRoot 'dist') -Force | Out-Null
    Write-Pass 'Clean completed.'
    exit 0
}
catch {
    Write-Fail $_.Exception.Message
    exit 1
}
