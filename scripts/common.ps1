Set-StrictMode -Version 2.0

$Script:ProjectRoot = Split-Path -Parent $PSScriptRoot

function Write-Check {
    param([string]$Message)
    Write-Host "[CHECK] $Message"
}

function Write-Pass {
    param([string]$Message)
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[FAIL] $Message" -ForegroundColor Red
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw $Message
    }
}

function Get-ProjectVersion {
    $versionFile = Join-Path $Script:ProjectRoot 'VERSION'
    Assert-True (Test-Path -LiteralPath $versionFile) 'VERSION file is missing.'
    $version = (Get-Content -LiteralPath $versionFile -TotalCount 1).Trim()
    Assert-True ($version -match '^\d+\.\d+\.\d+$') "VERSION must be SemVer X.Y.Z, got '$version'."
    return $version
}

function Get-PowerShellParseResult {
    param([string]$Path)
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    [pscustomobject]@{ Ast = $ast; Tokens = $tokens; Errors = $errors }
}

function Test-SafeRelativePath {
    param([string]$Root, [string]$Path)
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $pathFull = [System.IO.Path]::GetFullPath($Path)
    return $pathFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-RequiredProjectFiles {
    @(
        'src\BlueScreen_Check.ps1',
        'scripts\init.ps1',
        'scripts\build.ps1',
        'scripts\test.ps1',
        'scripts\clean.ps1',
        'scripts\package.ps1',
        'Run_BlueScreen_Check.bat',
        'build.bat',
        'test.bat',
        'dev-check.bat',
        'README.md',
        'CHANGELOG.md',
        'VERSION',
        'LICENSE',
        '.gitignore',
        '.github\workflows\ci.yml'
    )
}

function Test-ProjectStructure {
    foreach ($relativePath in (Get-RequiredProjectFiles)) {
        $path = Join-Path $Script:ProjectRoot $relativePath
        Assert-True (Test-Path -LiteralPath $path) "Missing required file: $relativePath"
    }
}

function Get-DangerousCommandNames {
    @(
        'Remove-Item',
        'Clear-EventLog',
        'Set-ItemProperty',
        'New-ItemProperty',
        'Remove-ItemProperty',
        'bcdedit',
        'shutdown',
        'Restart-Computer',
        'Stop-Computer',
        'sfc',
        'DISM',
        'winget',
        'pnputil'
    )
}

function Test-MainScriptSafety {
    $main = Join-Path $Script:ProjectRoot 'src\BlueScreen_Check.ps1'
    $parse = Get-PowerShellParseResult -Path $main
    Assert-True (@($parse.Errors).Count -eq 0) ("Parser errors: {0}" -f (($parse.Errors | ForEach-Object Message) -join '; '))

    $dangerousNames = Get-DangerousCommandNames
    $commands = $parse.Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true)
    foreach ($command in $commands) {
        $name = $command.GetCommandName()
        if ($dangerousNames -contains $name) {
            throw "Dangerous command found in executable AST: $name"
        }
        if ($name -eq 'wevtutil') {
            $text = $command.Extent.Text
            if ($text -match '(?i)\bcl\b') { throw "Dangerous event log clear command found: $text" }
        }
        if ($name -eq 'chkdsk') {
            $text = $command.Extent.Text
            if ($text -match '(?i)\s/[fr]\b') { throw "Dangerous chkdsk repair command found: $text" }
        }
    }

    $content = Get-Content -LiteralPath $main -Raw
    Assert-True ($content -notmatch '\$ErrorActionPreference\s*=\s*["'']SilentlyContinue["'']') 'Global SilentlyContinue is not allowed.'
    Assert-True ($content -notmatch 'Copy-Item[^\r\n]+MEMORY\.DMP') 'MEMORY.DMP must not be copied.'
    Assert-True ($content -notmatch '(Move-Item|Remove-Item)[^\r\n]+(Minidump|MEMORY\.DMP|\.dmp)') 'Original dump files must not be moved or removed.'
}
