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
$Script:ChineseSummaryFile = Join-Path $Script:ReportRoot 'Chinese_Summary_CN.txt'
$Script:ErrorFile = Join-Path $Script:ReportRoot 'Script_Errors.txt'
$Script:ModuleFailures = New-Object System.Collections.Generic.List[string]
$Script:StatusRecords = New-Object System.Collections.Generic.List[object]

New-Item -ItemType Directory -Path $Script:ReportRoot -Force | Out-Null

function Write-ReportLine {
    param([AllowNull()][string]$Text = '')
    Add-Content -LiteralPath $Script:ReportFile -Value $Text -Encoding UTF8
}

function Write-ChineseSummaryLine {
    param([AllowNull()][string]$Text = '')
    Add-Content -LiteralPath $Script:ChineseSummaryFile -Value $Text -Encoding UTF8
}

function ConvertFrom-Utf8Base64 {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Text))
}

function Write-Zh {
    param([string]$Text)
    Write-ChineseSummaryLine (ConvertFrom-Utf8Base64 $Text)
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
    [void]$Script:StatusRecords.Add([pscustomobject]@{
        Name = $Name
        Status = $Status
        Message = $Message
    })
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
    $allEvents = @()
    $notAvailable = New-Object System.Collections.Generic.List[string]
    $providersToQuery = @($ProviderName)
    if (-not $ProviderName) { $providersToQuery = @($null) }

    foreach ($provider in $providersToQuery) {
        try {
            $filter = @{ LogName = $LogName; StartTime = $StartTime }
            if ($provider) { $filter.ProviderName = $provider }
            if ($Id) { $filter.Id = $Id }
            if ($Level) { $filter.Level = $Level }
            $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxEvents -ErrorAction Stop)
            if ($events.Count -gt 0) {
                $allEvents += $events
            }
        }
        catch [System.Diagnostics.Eventing.Reader.EventLogNotFoundException] {
            Write-Status -Name $Name -Status NOT_AVAILABLE -Message "Log not available: $LogName."
            return
        }
        catch {
            $message = $_.Exception.Message
            if ($_.FullyQualifiedErrorId -match 'NoMatchingEventsFound' -or $message -match 'No events were found that match the specified selection criteria') {
                continue
            }
            if ($message -match 'There is not an event provider') {
                if ($provider) { [void]$notAvailable.Add($provider) }
                continue
            }
            Write-ScriptError -Module $Name -Command "Get-WinEvent -FilterHashtable" -Message $message
            return
        }
    }

    $allEvents = @($allEvents | Sort-Object TimeCreated -Descending | Select-Object -First $MaxEvents)
    if ($allEvents.Count -eq 0) {
        if ($notAvailable.Count -gt 0 -and $notAvailable.Count -eq $providersToQuery.Count) {
            Write-Status -Name $Name -Status NOT_AVAILABLE -Message ("Provider(s) not available: {0}." -f ($notAvailable -join ', '))
        }
        else {
            $suffix = ''
            if ($notAvailable.Count -gt 0) {
                $suffix = " Provider(s) not available: {0}." -f ($notAvailable -join ', ')
            }
            Write-Status -Name $Name -Status NO_EVENTS -Message ("No matching events since {0}.{1}" -f $StartTime.ToString('s'), $suffix)
        }
        return
    }

    Write-Status -Name $Name -Status WARNING -Message ("Found {0} matching event(s)." -f $allEvents.Count)
    if ($notAvailable.Count -gt 0) {
        Write-Status -Name "$Name provider availability" -Status NOT_AVAILABLE -Message ("Provider(s) not available: {0}." -f ($notAvailable -join ', '))
    }
    foreach ($event in $allEvents) {
        Write-ReportLine ("TimeCreated={0}; Provider={1}; Id={2}; Level={3}" -f $event.TimeCreated, $event.ProviderName, $event.Id, $event.LevelDisplayName)
        $message = ($event.Message -replace "`r?`n", ' ')
        if ($message.Length -gt 800) { $message = $message.Substring(0, 800) + '...' }
        Write-ReportLine ("Message={0}" -f $message)
        Write-ReportLine ''
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

function Get-StatusRecord {
    param([string]$Name)
    $Script:StatusRecords | Where-Object { $_.Name -eq $Name } | Select-Object -Last 1
}

function Write-ChineseCheck {
    param(
        [string]$Title64,
        [string]$StatusName,
        [string]$NoEvents64,
        [string]$Warning64
    )
    $title = ConvertFrom-Utf8Base64 $Title64
    $noEvents = ConvertFrom-Utf8Base64 $NoEvents64
    $warning = ConvertFrom-Utf8Base64 $Warning64
    $record = Get-StatusRecord -Name $StatusName
    if ($null -eq $record) {
        Write-ChineseSummaryLine ("- {0}: not recorded." -f $title)
        return
    }
    if ($record.Status -eq 'WARNING') {
        Write-ChineseSummaryLine ("- {0}: {1}" -f $title, $warning)
    }
    elseif ($record.Status -eq 'FAILED') {
        Write-ChineseSummaryLine ("- {0}: {1}" -f $title, (ConvertFrom-Utf8Base64 '6L+Z6aG55qOA5rWL5omn6KGM5aSx6LSl77yM5bu66K6u5p+l55yLIFNjcmlwdF9FcnJvcnMudHh044CC'))
    }
    elseif ($record.Status -eq 'NOT_AVAILABLE') {
        Write-ChineseSummaryLine ("- {0}: {1}" -f $title, (ConvertFrom-Utf8Base64 '5b2T5YmN57O757uf5rKh5pyJ5o+Q5L6b6L+Z6aG55L+h5oGv77yM6YCa5bi45LiN5Luj6KGo5pWF6Zqc44CC'))
    }
    else {
        Write-ChineseSummaryLine ("- {0}: {1}" -f $title, $noEvents)
    }
}

function Write-ChineseSummary {
    Write-Zh '6JOd5bGP6K+K5pat5Lit5paH5pGY6KaB'
    Write-ChineseSummaryLine ((ConvertFrom-Utf8Base64 '55Sf5oiQ5pe26Ze077yaezB9') -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    Write-ChineseSummaryLine ((ConvertFrom-Utf8Base64 '5oql5ZGK55uu5b2V77yaezB9') -f $Script:ReportRoot)
    Write-ChineseSummaryLine ''

    $failed = @($Script:StatusRecords | Where-Object { $_.Status -eq 'FAILED' })
    $majorSignals = @($Script:StatusRecords | Where-Object {
        $_.Status -eq 'WARNING' -and $_.Name -in @('BugCheck Event ID 1001','Kernel-Power Event ID 41','Unexpected Shutdown Event ID 6008','WHEA Logger','GPU Display/nvlddmkm','Storage disk/nvme/ahci/ntfs','Minidump','MEMORY.DMP')
    })

    Write-Zh '5YWI55yL57uT6K6677ya'
    if ($failed.Count -gt 0) {
        Write-Zh '6L+Z5qyh6ISa5pys5pyJ6YOo5YiG6aG555uu5rKh5pyJ5p+l5oiQ5Yqf77yM5LiN6IO95oqK5aSx6LSl6aG555uu5b2T5oiQ4oCc5rKh5pyJ6Zeu6aKY4oCd44CC6K+35p+l55yLIFNjcmlwdF9FcnJvcnMudHh044CC'
    }
    elseif ($majorSignals.Count -eq 0) {
        Write-Zh '6L+Z5qyh5rKh5pyJ5Y+R546w5piO5pi+55qE6JOd5bGP44CB56Gs5Lu26ZSZ6K+v44CB5pi+5Y2h6amx5Yqo6ZSZ6K+v44CB56Gs55uY6ZSZ6K+v5oiWIER1bXAg5paH5Lu257q/57Si44CC'
        Write-Zh '5aaC5p6c5L2g5Y+q5piv5Li65LqG5rWL6K+V6ISa5pys5piv5ZCm6IO96L+Q6KGM77yM6YKj5LmI6L+Z5bGe5LqO5q2j5bi457uT5p6c44CC'
    }
    else {
        Write-Zh '6L+Z5qyh5Y+R546w5LqG5LiA5Lqb6ZyA6KaB5YWz5rOo55qE6K6w5b2V44CC5a6D5Lus5Y+q5piv57q/57Si77yM5LiN562J5LqO5bey57uP56Gu6K6k5p+Q5Liq56Gs5Lu25o2f5Z2P44CC'
    }

    Write-ChineseSummaryLine ''
    Write-Zh '5YWz6ZSu6aG555uu77ya'
    Write-ChineseCheck '6JOd5bGP6K6w5b2V' 'BugCheck Event ID 1001' '6L+H5Y67IDMwIOWkqeayoeacieafpeWIsCBXaW5kb3dzIOiTneWxjyBCdWdDaGVjayDorrDlvZXjgII=' '5p+l5Yiw5LqG6JOd5bGPIEJ1Z0NoZWNrIOiusOW9le+8jOW7uuiurue7k+WQiOWPkeeUn+aXtumXtOWSjCBEdW1wIOaWh+S7tui/m+S4gOatpeWIhuaekOOAgg=='
    Write-ChineseCheck '5byC5bi45pat55S15oiW5by65Yi26YeN5ZCv6K6w5b2V' 'Kernel-Power Event ID 41' '6L+H5Y67IDMwIOWkqeayoeacieafpeWIsCBLZXJuZWwtUG93ZXIgNDEg6K6w5b2V44CC5rOo5oSP77ya5Y2z5L2/5p+l5Yiw5a6D77yM5Lmf5Y+q6IO96K+05piO5pu+57uP6Z2e5q2j5bi45YWz5py65oiW6YeN5ZCv77yM5LiN6IO955u05o6l6K+05piO55S15rqQ5Z2P5LqG44CC' '5p+l5Yiw5LqGIEtlcm5lbC1Qb3dlciA0Me+8jOivtOaYjuezu+e7n+abvue7j+mdnuato+W4uOWFs+acuuaIlumHjeWQr++8m+Wug+S4jeiDveebtOaOpeivgeaYjueUtea6kOaNn+Wdj+OAgg=='
    Write-ChineseCheck 'V0hFQSDnoazku7bplJnor68=' 'WHEA Logger' '6L+H5Y67IDMwIOWkqeayoeacieafpeWIsCBXSEVBIOehrOS7tumUmeivr+iusOW9leOAgg==' '5p+l5Yiw5LqGIFdIRUEg56Gs5Lu26ZSZ6K+v77yM6L+Z5piv6YeN6KaB57q/57Si77yM5Y+v6IO95LiOIENQVeOAgeWGheWtmOOAgVBDSWXjgIHkuLvmnb/jgIFCSU9TIOaIluebuOWFs+mpseWKqOacieWFs++8jOS9huS4jeiDveS7heWHrei/meS4gOmhueS4i+WumuiuuuOAgg=='
    Write-ChineseCheck '5pi+5Y2h5oiWIE5WSURJQSDpqbHliqjkuovku7Y=' 'GPU Display/nvlddmkm' '6L+H5Y67IDMwIOWkqeayoeacieafpeWIsCBEaXNwbGF5L252bGRkbWttIOebuOWFs+S6i+S7tuOAgg==' '5p+l5Yiw5LqG5pi+5Y2h5oiWIE5WSURJQSDpqbHliqjnm7jlhbPkuovku7bvvIzpnIDopoHnu5PlkIjok53lsY/ml7bpl7TjgIHpqbHliqjniYjmnKzjgIHmuKnluqbjgIHkvpvnlLXlkozlvZPml7bov5DooYznmoTnqIvluo/liKTmlq3jgII='
    Write-ChineseCheck '56Gs55uY44CBTlZNZeOAgVNBVEHjgIFOVEZTIOWtmOWCqOS6i+S7tg==' 'Storage disk/nvme/ahci/ntfs' '6L+H5Y67IDMwIOWkqeayoeacieafpeWIsOWMuemFjeeahOWtmOWCqOmUmeivr+S6i+S7tuOAgg==' '5p+l5Yiw5LqG5a2Y5YKo55u45YWz5LqL5Lu277yM5bu66K6u6L+b5LiA5q2l5qOA5p+l56Gs55uY5YGl5bq344CB5Zu65Lu244CB5o6l5Y+j44CB57q/5p2Q44CB5o6n5Yi25Zmo6amx5Yqo5ZKM5paH5Lu257O757uf44CC'
    Write-ChineseCheck '5bCP5Z6L6L2s5YKoIE1pbmlkdW1w' 'Minidump' '5rKh5pyJ5Y+R546w5Y+v5aSN5Yi255qE5bCP5Z6L6JOd5bGP6L2s5YKo5paH5Lu244CC' '5Y+R546w5LqGIE1pbmlkdW1wIOaWh+S7tu+8jOiEmuacrOWPquWkjeWItuacgOi/kSA1IOS4quWIsOaKpeWRiuebruW9le+8jOWOn+Wni+aWh+S7tuayoeacieiiq+enu+WKqOaIluWIoOmZpOOAgg=='
    Write-ChineseCheck '5a6M5pW05YaF5a2Y6L2s5YKoIE1FTU9SWS5ETVA=' 'MEMORY.DMP' '5rKh5pyJ5Y+R546wIE1FTU9SWS5ETVDjgII=' '5Y+R546w5LqGIE1FTU9SWS5ETVDvvIzkvYbohJrmnKzlj6rorrDlvZXlroPmmK/lkKblrZjlnKjlkozmlofku7blpKflsI/vvIzkuI3kvJrlpI3liLbov5nkuKrlpKfmlofku7bjgII='
    Write-ChineseSummaryLine ''
    Write-Zh '5YW25LuW5o+Q6YaS77ya'
    Write-Zh '5aaC5p6c5p+Q6aG55YaZ552A4oCc5pyq5Y+R546w55u45YWz6K6w5b2V4oCd77yM5oSP5oCd5piv5oyJ5b2T5YmN5p2h5Lu25rKh5pyJ5p+l5Yiw77yM5LiN5Luj6KGo55S16ISR6KKr5YWo6Z2i6K+B5piO57ud5a+55rKh6Zeu6aKY44CC'
    Write-Zh '5aaC5p6c5p+Q6aG55YaZ552A4oCc5qOA5rWL5aSx6LSl4oCd77yM6K+05piO6ISa5pys5rKh6IO95a6M5oiQ6YKj6aG55p+l6K+i77yM5LiN6IO95oqK5a6D55CG6Kej5oiQ5rKh5pyJ5byC5bi444CC'
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

Write-ChineseSummary

Write-Host "Report created: $Script:ReportRoot"
exit 0
