#requires -version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0

$Script:ToolRoot = Split-Path -Parent $PSScriptRoot
$Script:Version = 'unknown'
$versionFile = Join-Path $Script:ToolRoot 'VERSION'
if (Test-Path -LiteralPath $versionFile) {
    $Script:Version = (Get-Content -LiteralPath $versionFile -TotalCount 1).Trim()
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$desktop = [Environment]::GetFolderPath('Desktop')
if ([string]::IsNullOrWhiteSpace($desktop)) {
    $desktop = (Get-Location).Path
}
$Script:ReportRoot = Join-Path $desktop ("BlueScreen_Report_{0}" -f $timestamp)
$Script:ReportFile = Join-Path $Script:ReportRoot 'BlueScreen_Report.txt'
$Script:ErrorFile = Join-Path $Script:ReportRoot 'Script_Errors.txt'
$Script:ModuleFailures = New-Object System.Collections.Generic.List[string]

New-Item -ItemType Directory -Path $Script:ReportRoot -Force | Out-Null

function Write-ReportLine {
    param([AllowNull()][string]$Text = '')
    Add-Content -LiteralPath $Script:ReportFile -Value $Text -Encoding UTF8
}

function Write-Section {
    param([string]$Title)
    Write-ReportLine ''
    Write-ReportLine ("==== {0} ====" -f $Title)
}

function Write-Status {
    param(
        [string]$Name,
        [ValidateSet('OK','NO_EVENTS','WARNING','FAILED','NOT_AVAILABLE','SKIPPED')]
        [string]$Status,
        [AllowNull()][string]$Message = ''
    )
    Write-ReportLine ("[{0}] {1}: {2}" -f $Status, $Name, $Message)
}

function Write-ScriptError {
    param(
        [string]$Module,
        [string]$Command,
        [string]$Message
    )
    $line = "[{0}] Module={1}; Command={2}; Error={3}" -f (Get-Date -Format 's'), $Module, $Command, $Message
    Add-Content -LiteralPath $Script:ErrorFile -Value $line -Encoding UTF8
    [void]$Script:ModuleFailures.Add($Module)
    Write-Status -Name $Module -Status FAILED -Message "Detection failed. See Script_Errors.txt."
}

function Invoke-Collector {
    param(
        [string]$Name,
        [scriptblock]$ScriptBlock
    )
    try {
        Write-Section $Name
        & $ScriptBlock
    }
    catch {
        Write-ScriptError -Module $Name -Command $MyInvocation.Line -Message $_.Exception.Message
    }
}

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        Write-ScriptError -Module 'Administrator Check' -Command 'WindowsIdentity.GetCurrent' -Message $_.Exception.Message
        return $false
    }
}

function Get-CimEvidence {
    param(
        [string]$ClassName,
        [string]$Module,
        [string[]]$Property
    )
    try {
        $items = Get-CimInstance -ClassName $ClassName -ErrorAction Stop
        if ($null -eq $items) {
            Write-Status -Name $Module -Status NO_EVENTS -Message "No CIM instances returned for $ClassName."
            return
        }
        foreach ($item in $items) {
            $item | Select-Object -Property $Property | Format-List | Out-String | ForEach-Object { Write-ReportLine $_.TrimEnd() }
        }
        Write-Status -Name $Module -Status OK -Message "Collected from $ClassName."
    }
    catch {
        Write-ScriptError -Module $Module -Command "Get-CimInstance $ClassName" -Message $_.Exception.Message
    }
}

function Get-SafeWinEvent {
    param(
        [string]$Name,
        [string]$LogName,
        [string[]]$ProviderName,
        [int[]]$Id,
        [int[]]$Level,
        [datetime]$StartTime,
        [int]$MaxEvents = 50
    )
    try {
        $filter = @{ LogName = $LogName; StartTime = $StartTime }
        if ($ProviderName) { $filter.ProviderName = $ProviderName }
        if ($Id) { $filter.Id = $Id }
        if ($Level) { $filter.Level = $Level }
        $events = Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxEvents -ErrorAction Stop
        if ($null -eq $events -or @($events).Count -eq 0) {
            Write-Status -Name $Name -Status NO_EVENTS -Message "No matching events since $($StartTime.ToString('s'))."
            return
        }
        Write-Status -Name $Name -Status WARNING -Message ("Found {0} matching event(s)." -f @($events).Count)
        foreach ($event in $events) {
            Write-ReportLine ("TimeCreated={0}; Provider={1}; Id={2}; Level={3}" -f $event.TimeCreated, $event.ProviderName, $event.Id, $event.LevelDisplayName)
            $message = ($event.Message -replace "`r?`n", ' ')
            if ($message.Length -gt 800) { $message = $message.Substring(0, 800) + '...' }
            Write-ReportLine ("Message={0}" -f $message)
            Write-ReportLine ''
        }
    }
    catch [System.Diagnostics.Eventing.Reader.EventLogNotFoundException] {
        Write-Status -Name $Name -Status NOT_AVAILABLE -Message "Log not available: $LogName."
    }
    catch {
        Write-ScriptError -Module $Name -Command "Get-WinEvent -FilterHashtable" -Message $_.Exception.Message
    }
}

function Get-DumpEvidence {
    $miniDumpPath = 'C:\Windows\Minidump'
    $memoryDumpPath = 'C:\Windows\MEMORY.DMP'
    $targetMiniDump = Join-Path $Script:ReportRoot 'Minidump'

    if (Test-Path -LiteralPath $miniDumpPath) {
        try {
            $dumps = Get-ChildItem -LiteralPath $miniDumpPath -File -Filter '*.dmp' -ErrorAction Stop | Sort-Object LastWriteTime -Descending
            if (@($dumps).Count -eq 0) {
                Write-Status -Name 'Minidump' -Status NO_EVENTS -Message 'Minidump directory exists but contains no .dmp files.'
            }
            else {
                Write-Status -Name 'Minidump' -Status WARNING -Message ("Found {0} minidump file(s). Copying latest 5 only." -f @($dumps).Count)
                New-Item -ItemType Directory -Path $targetMiniDump -Force | Out-Null
                foreach ($dump in $dumps) {
                    Write-ReportLine ("Name={0}; Size={1}; CreationTime={2}; LastWriteTime={3}" -f $dump.Name, $dump.Length, $dump.CreationTime, $dump.LastWriteTime)
                }
                foreach ($dump in ($dumps | Select-Object -First 5)) {
                    Copy-Item -LiteralPath $dump.FullName -Destination (Join-Path $targetMiniDump $dump.Name) -ErrorAction Stop
                }
            }
        }
        catch {
            Write-ScriptError -Module 'Minidump' -Command 'Get-ChildItem/Copy-Item C:\Windows\Minidump' -Message $_.Exception.Message
        }
    }
    else {
        Write-Status -Name 'Minidump' -Status NOT_AVAILABLE -Message 'C:\Windows\Minidump does not exist.'
    }

    try {
        if (Test-Path -LiteralPath $memoryDumpPath) {
            $memoryDump = Get-Item -LiteralPath $memoryDumpPath -ErrorAction Stop
            Write-Status -Name 'MEMORY.DMP' -Status WARNING -Message ("Exists; Size={0}; CreationTime={1}; LastWriteTime={2}. Metadata only, not copied." -f $memoryDump.Length, $memoryDump.CreationTime, $memoryDump.LastWriteTime)
        }
        else {
            Write-Status -Name 'MEMORY.DMP' -Status NO_EVENTS -Message 'C:\Windows\MEMORY.DMP does not exist.'
        }
    }
    catch {
        Write-ScriptError -Module 'MEMORY.DMP' -Command 'Get-Item C:\Windows\MEMORY.DMP' -Message $_.Exception.Message
    }
}

function Get-NvidiaSmiEvidence {
    $command = Get-Command -Name 'nvidia-smi.exe' -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        Write-Status -Name 'NVIDIA nvidia-smi' -Status NOT_AVAILABLE -Message 'nvidia-smi.exe was not found in PATH.'
        return
    }
    try {
        Write-Status -Name 'NVIDIA nvidia-smi' -Status OK -Message $command.Source
        & $command.Source 2>&1 | Out-String | ForEach-Object { Write-ReportLine $_.TrimEnd() }
    }
    catch {
        Write-ScriptError -Module 'NVIDIA nvidia-smi' -Command 'nvidia-smi.exe' -Message $_.Exception.Message
    }
}

Write-ReportLine 'Windows-BlueScreen-Diagnostic Report'
Write-ReportLine ("ToolVersion={0}" -f $Script:Version)
Write-ReportLine ("Generated={0}" -f (Get-Date -Format 's'))
Write-ReportLine ("ReportRoot={0}" -f $Script:ReportRoot)
Write-ReportLine 'Mode=READ ONLY / EVIDENCE COLLECTION'

Invoke-Collector -Name 'Runtime' -ScriptBlock {
    Write-Status -Name 'PowerShell Version' -Status OK -Message $PSVersionTable.PSVersion.ToString()
    Write-Status -Name 'Administrator' -Status OK -Message (Test-IsAdministrator).ToString()
}

Invoke-Collector -Name 'Windows Version' -ScriptBlock { Get-CimEvidence -ClassName Win32_OperatingSystem -Module 'Windows Version' -Property Caption,Version,BuildNumber,OSArchitecture,InstallDate,LastBootUpTime }
Invoke-Collector -Name 'CPU' -ScriptBlock { Get-CimEvidence -ClassName Win32_Processor -Module 'CPU' -Property Name,Manufacturer,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed,SocketDesignation }
Invoke-Collector -Name 'Motherboard' -ScriptBlock { Get-CimEvidence -ClassName Win32_BaseBoard -Module 'Motherboard' -Property Manufacturer,Product,Version,SerialNumber }
Invoke-Collector -Name 'BIOS' -ScriptBlock { Get-CimEvidence -ClassName Win32_BIOS -Module 'BIOS' -Property Manufacturer,SMBIOSBIOSVersion,ReleaseDate,SerialNumber }
Invoke-Collector -Name 'Physical Memory' -ScriptBlock { Get-CimEvidence -ClassName Win32_PhysicalMemory -Module 'Physical Memory' -Property BankLabel,DeviceLocator,Capacity,Speed,ConfiguredClockSpeed,Manufacturer,PartNumber,SerialNumber }
Invoke-Collector -Name 'Memory Capacity' -ScriptBlock { Get-CimEvidence -ClassName Win32_ComputerSystem -Module 'Memory Capacity' -Property TotalPhysicalMemory,Manufacturer,Model,SystemType }
Invoke-Collector -Name 'GPU' -ScriptBlock { Get-CimEvidence -ClassName Win32_VideoController -Module 'GPU' -Property Name,DriverVersion,DriverDate,AdapterRAM,PNPDeviceID }
Invoke-Collector -Name 'Logical Disks' -ScriptBlock { Get-CimEvidence -ClassName Win32_LogicalDisk -Module 'Logical Disks' -Property DeviceID,DriveType,FileSystem,Size,FreeSpace,VolumeName }
Invoke-Collector -Name 'Physical Disks' -ScriptBlock {
    Get-CimEvidence -ClassName Win32_DiskDrive -Module 'Physical Disks' -Property Model,InterfaceType,MediaType,Size,SerialNumber,FirmwareRevision,Status,PNPDeviceID
    if (Get-Command -Name Get-PhysicalDisk -ErrorAction SilentlyContinue) {
        try {
            Get-PhysicalDisk -ErrorAction Stop | Select-Object FriendlyName,SerialNumber,MediaType,BusType,HealthStatus,OperationalStatus,Size | Format-List | Out-String | ForEach-Object { Write-ReportLine $_.TrimEnd() }
            Write-Status -Name 'Get-PhysicalDisk' -Status OK -Message 'Collected physical disk health status.'
        }
        catch {
            Write-ScriptError -Module 'Get-PhysicalDisk' -Command 'Get-PhysicalDisk' -Message $_.Exception.Message
        }
    }
    else {
        Write-Status -Name 'Get-PhysicalDisk' -Status NOT_AVAILABLE -Message 'Storage module command not available.'
    }
}
Invoke-Collector -Name 'PnP Problem Devices' -ScriptBlock {
    try {
        $devices = Get-CimInstance -ClassName Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' -ErrorAction Stop
        if ($null -eq $devices -or @($devices).Count -eq 0) {
            Write-Status -Name 'PnP Problem Devices' -Status NO_EVENTS -Message 'No PnP devices with ConfigManagerErrorCode <> 0.'
        }
        else {
            Write-Status -Name 'PnP Problem Devices' -Status WARNING -Message ("Found {0} problem device(s)." -f @($devices).Count)
            $devices | Select-Object Name,ConfigManagerErrorCode,PNPDeviceID | Format-List | Out-String | ForEach-Object { Write-ReportLine $_.TrimEnd() }
        }
    }
    catch {
        Write-ScriptError -Module 'PnP Problem Devices' -Command 'Get-CimInstance Win32_PnPEntity' -Message $_.Exception.Message
    }
}
Invoke-Collector -Name 'Crash Dump Configuration' -ScriptBlock { Get-CimEvidence -ClassName Win32_OSRecoveryConfiguration -Module 'Crash Dump Configuration' -Property DebugInfoType,ExpandedDebugFilePath,MiniDumpDirectory,OverwriteExistingDebugFile,AutoReboot }
Invoke-Collector -Name 'NVIDIA SMI' -ScriptBlock { Get-NvidiaSmiEvidence }
Invoke-Collector -Name 'Dump Evidence' -ScriptBlock { Get-DumpEvidence }

$start30 = (Get-Date).AddDays(-30)
Invoke-Collector -Name 'BugCheck Events' -ScriptBlock { Get-SafeWinEvent -Name 'BugCheck Event ID 1001' -LogName 'System' -ProviderName @('Microsoft-Windows-WER-SystemErrorReporting') -Id @(1001) -StartTime $start30 -MaxEvents 30 }
Invoke-Collector -Name 'Kernel-Power Events' -ScriptBlock { Get-SafeWinEvent -Name 'Kernel-Power Event ID 41' -LogName 'System' -ProviderName @('Microsoft-Windows-Kernel-Power') -Id @(41) -StartTime $start30 -MaxEvents 30 }
Invoke-Collector -Name 'Unexpected Shutdown Events' -ScriptBlock { Get-SafeWinEvent -Name 'Unexpected Shutdown Event ID 6008' -LogName 'System' -ProviderName @('EventLog') -Id @(6008) -StartTime $start30 -MaxEvents 30 }
Invoke-Collector -Name 'WHEA Events' -ScriptBlock { Get-SafeWinEvent -Name 'WHEA Logger' -LogName 'System' -ProviderName @('Microsoft-Windows-WHEA-Logger') -StartTime $start30 -MaxEvents 50 }
Invoke-Collector -Name 'GPU Events' -ScriptBlock { Get-SafeWinEvent -Name 'GPU Display/nvlddmkm' -LogName 'System' -ProviderName @('Display','nvlddmkm') -StartTime $start30 -MaxEvents 50 }
Invoke-Collector -Name 'Storage Events' -ScriptBlock { Get-SafeWinEvent -Name 'Storage disk/nvme/ahci/ntfs' -LogName 'System' -ProviderName @('disk','stornvme','storahci','storport','Ntfs','volmgr') -StartTime $start30 -MaxEvents 80 }
Invoke-Collector -Name 'Recent System Critical Error' -ScriptBlock { Get-SafeWinEvent -Name 'Recent System Critical/Error' -LogName 'System' -Level @(1,2) -StartTime $start30 -MaxEvents 80 }
Invoke-Collector -Name 'Recent Application Critical Error' -ScriptBlock { Get-SafeWinEvent -Name 'Recent Application Critical/Error' -LogName 'Application' -Level @(1,2) -StartTime $start30 -MaxEvents 80 }

Write-Section 'Automatic Summary'
if ($Script:ModuleFailures.Count -gt 0) {
    Write-Status -Name 'Collector Failures' -Status WARNING -Message ("One or more modules failed: {0}. See Script_Errors.txt." -f (($Script:ModuleFailures | Select-Object -Unique) -join ', '))
}
Write-ReportLine 'Summary is evidence-only. It identifies signals that may need deeper analysis and does not declare specific hardware as failed without sufficient proof.'
Write-ReportLine 'If WHEA events are present, investigate CPU, RAM, PCIe devices, motherboard, BIOS settings, and related drivers with timestamps.'
Write-ReportLine 'If nvlddmkm or Display events are present, correlate with blue screen time, GPU driver version, temperatures, power state, and workload.'
Write-ReportLine 'If storage events are present, correlate with disk health, firmware, controller driver, cabling, and file system timestamps.'

Write-Host "Report created: $Script:ReportRoot"
exit 0
