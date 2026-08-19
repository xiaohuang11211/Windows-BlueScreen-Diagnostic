#requires -version 5.1
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot 'common.ps1')

$failures = New-Object System.Collections.Generic.List[string]

function Invoke-Test {
    param([string]$Name, [scriptblock]$ScriptBlock)
    try {
        Write-Check $Name
        & $ScriptBlock
        Write-Pass $Name
    }
    catch {
        Write-Fail "$Name - $($_.Exception.Message)"
        [void]$failures.Add($Name)
    }
}

Invoke-Test 'Parser Test' {
    foreach ($relativePath in @('src\BlueScreen_Check.ps1','scripts\init.ps1','scripts\build.ps1','scripts\clean.ps1','scripts\package.ps1')) {
        $parse = Get-PowerShellParseResult -Path (Join-Path $Script:ProjectRoot $relativePath)
        Assert-True (@($parse.Errors).Count -eq 0) "Parser errors in ${relativePath}: $($parse.Errors | ForEach-Object Message)"
        Assert-True (@($parse.Tokens).Count -gt 0) "No parser tokens returned for $relativePath"
    }
}

Invoke-Test 'Static Safety Test' {
    Test-MainScriptSafety
}

Invoke-Test 'Required Function Test' {
    $parse = Get-PowerShellParseResult -Path (Join-Path $Script:ProjectRoot 'src\BlueScreen_Check.ps1')
    $functions = $parse.Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object Name
    foreach ($required in @('Write-ReportLine','Get-SafeWinEvent','Write-ScriptError','Test-IsAdministrator','Get-DumpEvidence')) {
        Assert-True ($functions -contains $required) "Missing required function: $required"
    }
}

Invoke-Test 'Structure Test' {
    Test-ProjectStructure
}

Invoke-Test 'Output Safety Test' {
    $content = Get-Content -LiteralPath (Join-Path $Script:ProjectRoot 'src\BlueScreen_Check.ps1') -Raw
    Assert-True ($content -notmatch 'Copy-Item[^\r\n]+MEMORY\.DMP') 'MEMORY.DMP copy behavior detected.'
}

Invoke-Test 'Dump Safety Test' {
    $content = Get-Content -LiteralPath (Join-Path $Script:ProjectRoot 'src\BlueScreen_Check.ps1') -Raw
    Assert-True ($content -notmatch '(Move-Item|Remove-Item)[^\r\n]+(Minidump|MEMORY\.DMP|\.dmp)') 'Dump move/remove behavior detected.'
}

Invoke-Test 'Build Test' {
    & (Join-Path $Script:ProjectRoot 'scripts\build.ps1')
    Assert-True ($LASTEXITCODE -eq 0) 'build.ps1 returned non-zero exit code.'
    $distProject = Join-Path $Script:ProjectRoot 'dist\Windows-BlueScreen-Diagnostic'
    foreach ($file in @('BlueScreen_Check.ps1','Run_BlueScreen_Check.bat','README.md','VERSION','LICENSE')) {
        Assert-True (Test-Path -LiteralPath (Join-Path $distProject $file)) "Missing dist file: $file"
    }
}

if ($failures.Count -gt 0) {
    Write-Fail ("Tests failed: {0}" -f ($failures -join ', '))
    exit 1
}

Write-Pass 'All tests passed.'
exit 0
