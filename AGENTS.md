# AGENTS.md

This file is the long-lived development guide for Codex or any other coding agent working on this repository.

## Project Overview

`Windows-BlueScreen-Diagnostic` is a Windows 10 / Windows 11 read-only evidence collection tool for blue screen, abnormal restart, freeze, WHEA hardware error, GPU/NVIDIA driver, storage, dump, and related hardware diagnostic investigations.

The core principle is:

```text
READ ONLY / EVIDENCE COLLECTION
```

The tool is not a repair utility. It must not change Windows configuration or attempt automated fixes.

## Architecture

- `src/BlueScreen_Check.ps1`
  Main Windows PowerShell 5.1 script. It collects system information, hardware evidence, event log evidence, crash dump metadata, and creates reports on the user's Desktop.

- `scripts/common.ps1`
  Shared automation helpers for tests and build scripts, including parser helpers, structure checks, path safety helpers, version parsing, and static safety checks.

- `scripts/init.ps1`
  Development environment and project structure check.

- `scripts/test.ps1`
  Parser, AST safety, required function, structure, dump safety, output safety, and build tests.

- `scripts/build.ps1`
  Validates the project and creates `dist/Windows-BlueScreen-Diagnostic/`.

- `scripts/clean.ps1`
  Cleans only generated project artifacts such as `dist` and test temp directories. It must never delete source, Git data, reports, or anything outside the project root.

- `scripts/package.ps1`
  Runs tests and build, then creates `dist/Windows-BlueScreen-Diagnostic-vX.Y.Z.zip`.

- `.github/workflows/ci.yml`
  Windows GitHub Actions CI using Windows PowerShell 5.1.

- `Run_BlueScreen_Check.bat`
  Normal user entry point.

- `build.bat`, `test.bat`, `dev-check.bat`
  Convenience entry points for local development checks.

## Development Environment

Primary target:

- Windows 10 / Windows 11
- Windows PowerShell 5.1
- Git

Do not require PowerShell 7 for the main script. PowerShell 7 can be used for extra local tooling only if Windows PowerShell 5.1 compatibility remains intact.

## Commands

Run the diagnostic tool:

```powershell
.\Run_BlueScreen_Check.bat
```

Recommended for real diagnostic collection:

```text
Right-click Run_BlueScreen_Check.bat -> Run as administrator
```

Run project environment checks:

```powershell
.\dev-check.bat
```

Run tests:

```powershell
.\test.bat
```

Build:

```powershell
.\build.bat
```

Package:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\package.ps1
```

## Report Files

Reports are generated on the current user's Desktop:

```text
BlueScreen_Report_YYYYMMDD_HHMMSS\
```

Expected files:

- `BlueScreen_Report.txt`: detailed technical report.
- `Chinese_Summary_CN.txt`: Chinese human-readable summary for non-English users.
- `Script_Errors.txt`: only present when a module truly failed.
- `Minidump\`: only present when minidump files exist and are copied.

Important semantics:

- `NO_EVENTS`: the script was able to query the evidence source, but no matching events/files were found.
- `NOT_AVAILABLE`: the current system did not expose that provider, command, directory, or feature.
- `FAILED`: the query itself failed and must not be interpreted as "no problem".
- `WARNING`: evidence was found and needs human review. It is not automatic proof of failed hardware.

## Coding Rules

- Keep `src/BlueScreen_Check.ps1` compatible with Windows PowerShell 5.1.
- Keep `#requires -version 5.1` at the top of the main script.
- Avoid direct Chinese text inside `.ps1` files unless encoding has been tested under Windows PowerShell 5.1. Previous attempts caused parser failures from mojibake. The current Chinese summary uses UTF-8 Base64 strings to keep the source parse-safe.
- Use `Get-WinEvent -FilterHashtable` for event log queries. Do not read huge logs and filter with `Where-Object`.
- Do not set global `$ErrorActionPreference = "SilentlyContinue"`.
- Distinguish `NO_EVENTS`, `NOT_AVAILABLE`, `FAILED`, `WARNING`, `OK`, and `SKIPPED`.
- Module failures must be written to `Script_Errors.txt` and also reflected in the main report/summary.
- If changing event query handling, test localized "no matching events" behavior. Use `FullyQualifiedErrorId` such as `NoMatchingEventsFound` where possible instead of relying only on English error messages.

## Safety Constraints

The main diagnostic script must never:

- Modify registry values.
- Modify BIOS/XMP/DOCP/voltage/frequency settings.
- Install, uninstall, or modify drivers.
- Run Windows Update.
- Change power plans.
- Change boot configuration.
- Change dump configuration.
- Clear event logs.
- Delete system logs.
- Run `SFC /scannow`.
- Run `DISM /RestoreHealth`.
- Run `CHKDSK /F` or `CHKDSK /R`.
- Restart or shut down the computer.
- Automatically upload reports or dumps.
- Move, delete, or rename original dump files.
- Copy `C:\Windows\MEMORY.DMP`.

The only allowed write location for diagnostic output is the tool's own report directory on the user's Desktop.

## Files To Modify Carefully

- `src/BlueScreen_Check.ps1`
  Central user-facing diagnostic behavior. Run `scripts/test.ps1` and a real local execution after changes.

- `scripts/common.ps1`
  Contains static safety rules. Weakening this file can allow dangerous commands into the main script.

- `scripts/clean.ps1`
  Must keep deletion constrained to generated files under the project root.

- `.gitignore`
  Must keep real reports, dump files, zips, logs, and generated artifacts out of Git.

- `.github/workflows/ci.yml`
  Must continue running tests and build on `windows-latest` with Windows PowerShell 5.1.

## Testing Requirements

Before committing meaningful changes:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\test.ps1
```

For changes to the main diagnostic script, also run:

```powershell
.\Run_BlueScreen_Check.bat
```

Then confirm:

- A new Desktop `BlueScreen_Report_*` directory exists.
- `Chinese_Summary_CN.txt` exists and is readable.
- `Script_Errors.txt` is absent when no module truly failed.
- `NO_EVENTS` is used for "queried successfully, no matching records".

## Git / GitHub Notes

Remote:

```text
origin https://github.com/xiaohuang11211/Windows-BlueScreen-Diagnostic.git
```

Current branch is expected to be `main`.

This environment needed a local Git proxy for push:

```powershell
git config http.proxy http://127.0.0.1:7897
git config https.proxy http://127.0.0.1:7897
```

Do not commit credentials or tokens. Do not force push.

