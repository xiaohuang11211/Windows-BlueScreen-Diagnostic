# Windows-BlueScreen-Diagnostic

Windows-BlueScreen-Diagnostic is a read-only evidence collection tool for Windows 10 and Windows 11 blue screen, abnormal restart, freeze, WHEA hardware error, memory, motherboard, CPU, PCIe, GPU, NVIDIA driver, SSD, NVMe, SATA, NTFS, and crash dump investigations.

This project collects diagnostic evidence. It does not repair Windows and does not change system configuration.

## Features

- Collects Windows, PowerShell, administrator, CPU, motherboard, BIOS, memory, GPU, disk, PnP, crash dump, and event log evidence.
- Uses targeted `Get-WinEvent -FilterHashtable` queries instead of loading huge logs and filtering afterward.
- Separates states such as `OK`, `NO_EVENTS`, `WARNING`, `FAILED`, `NOT_AVAILABLE`, and `SKIPPED`.
- Records module failures in `Script_Errors.txt` and also references them from the main report.
- Copies only the latest five files from `C:\Windows\Minidump` into the report folder.
- Records `C:\Windows\MEMORY.DMP` metadata only. It does not copy `MEMORY.DMP`.

## Supported Systems

- Windows 10
- Windows 11

## Requirements

- Windows PowerShell 5.1 or later
- Recommended: run as administrator for fuller hardware and event log access

## Quick Start

For normal users, run:

```text
Run_BlueScreen_Check.bat
```

Right-click and choose "Run as administrator" when possible.

## Report Location

Reports are created on the current user's Desktop:

```text
BlueScreen_Report_YYYYMMDD_HHMMSS
```

Each report contains:

```text
BlueScreen_Report.txt
Chinese_Summary_CN.txt
Script_Errors.txt
Minidump\
```

`Chinese_Summary_CN.txt` is the recommended first file for Chinese-speaking users. `Script_Errors.txt` is omitted when no module errors occurred.

## Collected Evidence

The report includes BugCheck event ID 1001, Kernel-Power event ID 41, unexpected shutdown event ID 6008, WHEA logger events, GPU providers such as `Display` and `nvlddmkm`, storage providers such as `disk`, `stornvme`, `storahci`, `storport`, `Ntfs`, and `volmgr`, and dump metadata.

Kernel-Power 41 means the system did not shut down cleanly. The tool does not automatically diagnose it as a power supply failure.

## Safety

The tool reads diagnostic data and writes only to its own report directory. It does not modify registry values, BIOS settings, XMP/DOCP, voltages, memory frequency, GPU drivers, Windows Update, power plans, boot configuration, dump configuration, or event logs.

It does not run `SFC /scannow`, `DISM /RestoreHealth`, `CHKDSK /F`, `CHKDSK /R`, restart, shut down, or upload reports or dumps.

## Privacy Notice

Reports can contain private or identifying information, including computer name, user name, motherboard serial number, disk serial number, memory serial number, PnP instance IDs, and dump files. Review reports carefully before sharing them publicly.

## Development

Run the full development check:

```text
dev-check.bat
```

Run tests:

```text
test.bat
```

Build the distributable folder:

```text
build.bat
```

Create the ZIP package:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\package.ps1
```

## Build

Build validates structure, parses PowerShell, checks PowerShell 5.1 compatibility risks, scans for dangerous commands, reads `VERSION`, cleans `dist`, and creates:

```text
dist\Windows-BlueScreen-Diagnostic\
```

## Test

Tests cover parser validity, AST-based static safety, required functions, project structure, dump safety, output safety, and build generation.

## CI

GitHub Actions runs on `windows-latest` using Windows PowerShell 5.1. It runs tests, builds the project, verifies `dist`, and uploads the distributable as an artifact.

## License

MIT License.
