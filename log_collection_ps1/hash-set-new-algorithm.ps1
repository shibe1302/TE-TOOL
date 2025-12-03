param(
    [string]$ScpHost,
    [string]$Port,
    [string]$ScpUser,
    [string]$ScpPassword,
    [string]$Protocol,
    [string]$RemoteFolder,
    [string]$LocalDestination,
    [string]$winscpDllPath,
    [string]$MacFilePath,
    [int]$MaxScanThreads
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinAPI {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
}
"@

$hwnd = [WinAPI]::GetForegroundWindow()
[WinAPI]::MoveWindow($hwnd, 100, 100, 800, 400, $true)

# ==================== CONFIGURATION ====================
# $ScpHost = "127.0.0.1"
# $ScpUser = "a"
# $ScpPassword = "a"
# $Protocol = "SFTP"                          
# $RemoteFolder = "/tess2/ucg"                          
# $LocalDestination = "E:\download_log"               
# $winscpDllPath = "C:\Program Files (x86)\WinSCP\WinSCPnet.dll"
# $MacFilePath = "E:\nghien_cuu_FTU\UCG_FIBER_40pcs_log\data.txt"          
# $MaxScanThreads = 10  
$MaxDownloadThreads = 10  
$ConnectionTimeout = 5 
# $Port = "22"

# ==================== GLOBAL VARIABLES ====================
$Global:MacRegex = [regex]::new("(_[^_]+_)", [System.Text.RegularExpressions.RegexOptions]::Compiled)

# ==================== VALIDATION FUNCTION ====================
function Validate-Configuration {
    Write-Host "[Validation] Checking configuration..." -ForegroundColor Cyan
    
    $ValidProtocols = @("SFTP", "Scp", "Ftp", "Ftps", "Webdav", "S3")
    if ($Protocol -notin $ValidProtocols) {
        [System.Windows.Forms.MessageBox]::Show(
            "Loi Protocol: '$Protocol' khong hop le!`n`nProtocol hop le: $($ValidProtocols -join ', ')",
            "Configuration Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        exit 1
    }
    
    if (-not (Test-Path $winscpDllPath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Loi: khong tim thay WinSCP DLL tai:`n$winscpDllPath",
            "File Not Found",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        exit 1
    }
    
    if (-not (Test-Path $MacFilePath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Loi: khong tim thay file MAC list tai:`n$MacFilePath",
            "File Not Found",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        exit 1
    }
    
    if (-not (Test-Path $LocalDestination)) {
        try {
            New-Item -ItemType Directory -Path $LocalDestination -Force | Out-Null
            Write-Host "Tao folder dich: $LocalDestination" -ForegroundColor Green
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show(
                "Loi: khong the tao folder dich:`n$LocalDestination",
                "Directory Creation Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            exit 1
        }
    }
    
    Write-Host "Tat ca cau hinh hop le`n" -ForegroundColor Green
}

# ==================== LOAD DLL ====================
function Load-WinSCPDll {
    Write-Host "[Loading] dang tai WinSCP DLL..." -ForegroundColor Cyan
    try {
        Add-Type -Path $winscpDllPath
        Write-Host "WinSCP DLL tai thanh cong" -ForegroundColor Green
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Loi: khong the tai WinSCP DLL:`n`n$($_.Exception.Message)",
            "DLL Loading Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        exit 1
    }
}

# ==================== TEST CONNECTION ====================
function Test-ServerConnection {
    Write-Host "[Connection] dang kiem tra ket noi server..." -ForegroundColor Cyan
    
    try {
        $sessionOptions = New-Object WinSCP.SessionOptions
        $sessionOptions.Protocol = [WinSCP.Protocol]::$Protocol
        $sessionOptions.HostName = $ScpHost
        $sessionOptions.UserName = $ScpUser
        $sessionOptions.Password = $ScpPassword
        $sessionOptions.Timeout = New-TimeSpan -Seconds $ConnectionTimeout
        $sessionOptions.GiveUpSecurityAndAcceptAnySshHostKey = $true
        $sessionOptions.PortNumber = $Port
        
        $testSession = New-Object WinSCP.Session
        
        try {
            $testSession.Open($sessionOptions)
            Write-Host "ket noi server thanh cong" -ForegroundColor Green
            return $true
        }
        catch {
            $errorMsg = $_.Exception.Message
            [System.Windows.Forms.MessageBox]::Show(
                "Loi ket noi server:`n`n$errorMsg",
                "Connection Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            return $false
        }
        finally {
            $testSession.Dispose()
        }
    }
    catch {
        return $false
    }
}

# ==================== DEPTH-BASED REMOTE FOLDER DISCOVERY ====================
function Get-OptimalRemoteFolderList {
    param(
        [object]$Session,
        [string]$RootPath,
        [int]$TargetCount
    )
    
    Write-Host "-> Dang tim kiem folder tren server o cac bac..." -ForegroundColor Cyan
    
    $CurrentLevel = @($RootPath)
    $Level = 0
    
    while ($true) {
        $Level++
        $NextLevel = @()
        
        # Lay tat ca folder con cua level hien tai
        foreach ($folder in $CurrentLevel) {
            try {
                $directoryInfo = $Session.ListDirectory($folder)
                
                foreach ($item in $directoryInfo.Files) {
                    if ($item.Name -eq "." -or $item.Name -eq "..") { continue }
                    
                    if ($item.IsDirectory) {
                        $NextLevel += $item.FullName
                    }
                }
            }
            catch {
                Write-Warning "Khong the truy cap remote folder: $folder"
            }
        }
        
        Write-Host "   Bac $Level : $($NextLevel.Count) folder(s)" -ForegroundColor Gray
        
        # Neu khong con folder nao o level tiep theo
        if ($NextLevel.Count -eq 0) {
            Write-Host "-> Khong con folder con. Su dung bac $($Level - 1) voi $($CurrentLevel.Count) folder(s)" -ForegroundColor Yellow
            return $CurrentLevel
        }
        
        # Neu so luong folder >= target, dung lai va tra ve level nay
        if ($NextLevel.Count -ge $TargetCount) {
            Write-Host "-> Chon bac $Level voi $($NextLevel.Count) folder(s) (>= $TargetCount)" -ForegroundColor Green
            return $NextLevel
        }
        
        # Chua du, tiep tuc xuong bac sau
        $CurrentLevel = $NextLevel
        
        # Gioi han de tranh duyet qua sau (max 10 levels)
        if ($Level -ge 10) {
            Write-Host "-> Dat gioi han bac 10. Su dung bac hien tai voi $($CurrentLevel.Count) folder(s)" -ForegroundColor Yellow
            return $CurrentLevel
        }
    }
}

# ==================== MAIN SCRIPT ====================
Write-Host "`n========== SCP/SFTP PARALLEL FILE SCANNER - DEPTH-OPTIMIZED VERSION ==========" -ForegroundColor Magenta
Validate-Configuration
Load-WinSCPDll

if (-not (Test-ServerConnection)) {
    Write-Host "Validation failed. Exiting." -ForegroundColor Red
    exit 1
}

$start = Get-Date

# ==================== STEP 1: LOAD MAC DATABASE ====================
Write-Host "[1/5] Dang doc danh sach MAC..." -ForegroundColor Cyan
$MacDb = New-Object System.Collections.Generic.HashSet[string]

try {
    if (Test-Path $MacFilePath) {
        $RawMacs = Get-Content $MacFilePath -ErrorAction Stop
        foreach ($mac in $RawMacs) {
            $cleanMac = $mac.Trim().ToUpper()
            if (-not [string]::IsNullOrWhiteSpace($cleanMac)) {
                [void]$MacDb.Add($cleanMac)
            }
        }
        if ($MacDb.Count -eq 0) {
            Write-Host "canh bao: File MAC list rong!" -ForegroundColor Yellow
            exit 1
        }
        Write-Host "-> Da nap $($MacDb.Count) MAC vao bo nho." -ForegroundColor Green
    } 
    else {
        throw "khong tim thay file MAC list"
    }
}
catch {
    Write-Error "Loi khi doc file MAC list: $($_.Exception.Message)"
    exit 1
}

# ==================== STEP 2: GET OPTIMAL REMOTE FOLDERS ====================
Write-Host "[2/5] Dang tim folder toi uu tren server de scan song song..." -ForegroundColor Cyan

$RootFolders = @()
$sessionOptions = New-Object WinSCP.SessionOptions
$sessionOptions.Protocol = [WinSCP.Protocol]::$Protocol
$sessionOptions.HostName = $ScpHost
$sessionOptions.UserName = $ScpUser
$sessionOptions.Password = $ScpPassword
$sessionOptions.GiveUpSecurityAndAcceptAnySshHostKey = $true
$sessionOptions.PortNumber = $Port

$session = New-Object WinSCP.Session

try {
    $session.Open($sessionOptions)
    
    $RootFolders = Get-OptimalRemoteFolderList -Session $session -RootPath $RemoteFolder -TargetCount $MaxScanThreads
    
    if ($RootFolders.Count -eq 0) {
        Write-Host "-> Khong tim thay folder nao. Se scan truc tiep root folder" -ForegroundColor Yellow
        $RootFolders = @($RemoteFolder)
    }
    
    Write-Host "-> Se scan $($RootFolders.Count) folder(s) tren server" -ForegroundColor Green
}
catch {
    Write-Error "Loi khi lay danh sach folder: $($_.Exception.Message)"
    exit 1
}
finally {
    $session.Dispose()
}

# ==================== STEP 3: PARALLEL SCAN WITH EnumerateRemoteFiles ====================
Write-Host "[3/5] Dang khoi tao scan song song voi EnumerateRemoteFiles..." -ForegroundColor Cyan

# Chia folders thanh batches - SUA LAI PHAN NAY
$FolderBatches = @()
$BatchSize = [Math]::Ceiling($RootFolders.Count / $MaxScanThreads)

for ($i = 0; $i -lt $RootFolders.Count; $i += $BatchSize) {
    $count = [Math]::Min($BatchSize, ($RootFolders.Count - $i))
    $batch = $RootFolders[$i..($i + $count - 1)]
    $FolderBatches += , $batch
}

Write-Host "-> Chia $($RootFolders.Count) folder(s) thanh $($FolderBatches.Count) batch de xu ly" -ForegroundColor Cyan

# ScriptBlock cho scan job voi EnumerateRemoteFiles
$ScanJobBlock = {
    param($FolderList, $MacDbArray, $SessionOptsHash, $DllPath, $PortNumber)
    
    Add-Type -Path $DllPath
    
    # Tao HashSet tu array de co O(1) lookup
    $MacDbSet = New-Object System.Collections.Generic.HashSet[string]
    foreach ($mac in $MacDbArray) {
        [void]$MacDbSet.Add($mac)
    }
    
    $LocalResults = @{}
    $ScannedCount = 0
    
    # Tao session options
    $jobOptions = New-Object WinSCP.SessionOptions
    $jobOptions.Protocol = [WinSCP.Protocol]::Sftp
    $jobOptions.HostName = $SessionOptsHash.HostName
    $jobOptions.UserName = $SessionOptsHash.UserName
    $jobOptions.Password = $SessionOptsHash.Password
    $jobOptions.GiveUpSecurityAndAcceptAnySshHostKey = $true
    $jobOptions.PortNumber = $PortNumber
    
    $jobSession = New-Object WinSCP.Session
    
    try {
        $jobSession.Open($jobOptions)
        
        # Duyet qua tung folder trong batch
        foreach ($folder in $FolderList) {
            try {
                # SU DUNG EnumerateRemoteFiles - duyet de quy tu dong
                # "*" = wildcard de lay tat ca file
                # EnumerationOptions.AllDirectories = duyet de quy vao subfolder
                $fileInfos = $jobSession.EnumerateRemoteFiles(
                    $folder, 
                    "*", 
                    [WinSCP.EnumerationOptions]::AllDirectories
                )
                
                # Xu ly tung file duoc tim thay
                foreach ($fileInfo in $fileInfos) {
                    $ScannedCount++
                    
                    # Bo qua thu muc
                    if ($fileInfo.IsDirectory) { continue }
                    
                    # Extract MAC tu filename
                    if (($fileInfo.Name -match "(_[^_]+_)") -or ($fileInfo.Name -match "([^_]+_)")) {
                        $extractedMac = $matches[1].Trim('_').ToUpper()
                        
                        # Kiem tra MAC co trong HashSet khong - O(1) complexity
                        if ($MacDbSet.Contains($extractedMac)) {
                            $LocalResults[$fileInfo.FullName] = $fileInfo.Name
                        }
                    }
                }
            }
            catch {
                Write-Warning "Job: Khong the truy cap folder: $folder - $($_.Exception.Message)"
            }
        }
        
        return @{
            Files        = $LocalResults
            ScannedCount = $ScannedCount
        }
    }
    catch {
        Write-Error "Job Session Error: $($_.Exception.Message)"
        return @{
            Files        = @{}
            ScannedCount = 0
        }
    }
    finally {
        $jobSession.Dispose()
    }
}

# Chuan bi parameters
$SessionOptsHash = @{
    HostName = $ScpHost
    UserName = $ScpUser
    Password = $ScpPassword
}
# Chuyen HashSet thanh array de truyen qua Job
$MacDbArray = @($MacDb)

# Khoi tao scan jobs
$ScanJobs = @()
$jobIndex = 0
foreach ($batch in $FolderBatches) {
    $jobIndex++
    Write-Host "   -> Khoi tao Job #$jobIndex voi $($batch.Count) folder(s)" -ForegroundColor Gray
    $ScanJobs += Start-Job -ScriptBlock $ScanJobBlock -ArgumentList $batch, $MacDbArray, $SessionOptsHash, $winscpDllPath, $Port
}

# Cho jobs hoan thanh
Write-Host "-> Dang cho cac job hoan thanh..." -ForegroundColor Cyan
$ScanJobs | Wait-Job | Out-Null

# Thu thap ket qua
$FilesToDownload = [System.Collections.Generic.List[object]]::new()
$TotalScanned = 0

foreach ($job in $ScanJobs) {
    $result = Receive-Job -Job $job
    
    if ($result -and $result.Files) {
        $TotalScanned += $result.ScannedCount
        
        foreach ($key in $result.Files.Keys) {
            $FilesToDownload.Add(@{
                    RemotePath = $key
                    FileName   = $result.Files[$key]
                })
        }
    }
}

$ScanJobs | Remove-Job

$TotalFiles = $FilesToDownload.Count
Write-Host "-> Scan hoan tat!" -ForegroundColor Green
Write-Host "   - Tong so file da quet: $TotalScanned" -ForegroundColor Yellow
Write-Host "   - File khop MAC: $TotalFiles" -ForegroundColor Yellow

if ($TotalFiles -eq 0) { 
    Write-Host "Khong co file nao de tai xuong. Ket thuc." -ForegroundColor Yellow
    exit 
}

# ==================== STEP 4: PARALLEL DOWNLOAD ====================
Write-Host "[4/5] Dang khoi tao $MaxDownloadThreads luong tai xuong..." -ForegroundColor Cyan

$DownloadBatches = @()
$DownloadBatchSize = [Math]::Ceiling($TotalFiles / $MaxDownloadThreads)
for ($i = 0; $i -lt $TotalFiles; $i += $DownloadBatchSize) {
    $count = [Math]::Min($DownloadBatchSize, ($TotalFiles - $i))
    $DownloadBatches += , $FilesToDownload.GetRange($i, $count)
}

$DownloadJobBlock = {
    param($FileBatch, $SessionOptsHash, $DllPath, $DestDir, $PortNumber)
    
    Add-Type -Path $DllPath
    
    $jobOptions = New-Object WinSCP.SessionOptions
    $jobOptions.Protocol = [WinSCP.Protocol]::Sftp
    $jobOptions.HostName = $SessionOptsHash.HostName
    $jobOptions.UserName = $SessionOptsHash.UserName
    $jobOptions.Password = $SessionOptsHash.Password
    $jobOptions.GiveUpSecurityAndAcceptAnySshHostKey = $true
    $jobOptions.PortNumber = $PortNumber

    $jobSession = New-Object WinSCP.Session
    
    $MaxRetries = 3
    $DelaySeconds = 5
    
    try {
        $jobSession.Open($jobOptions)
        
        foreach ($f in $FileBatch) {
            $localFilePath = Join-Path $DestDir $f.FileName
            
            for ($i = 0; $i -lt $MaxRetries; $i++) {
                try {
                    if (Test-Path $localFilePath) { 
                        Write-Host "File exist: $($f.FileName)"
                        break 
                    }
                    
                    $transferResult = $jobSession.GetFiles($f.RemotePath, $localFilePath, $False)
                    Write-Host $f.RemotePath -ForegroundColor Blue
                    $transferResult.Check()
                    break 
                }
                catch {
                    if ($_.Exception.Message -match "Code: 32") {
                        Write-Warning "Code 32 cho file $($f.FileName). Cho $($DelaySeconds)s... ($($i + 1)/$MaxRetries)"
                        Start-Sleep -Seconds $DelaySeconds
                    }
                    else {
                        Write-Error "Failed download $($f.FileName): $($_.Exception.Message)"
                        break 
                    }
                }
            }
        }
    }
    catch {
        Write-Error "Download Job Error: $($_.Exception.Message)"
    }
    finally {
        $jobSession.Dispose()
    }
}

$DownloadJobs = @()
foreach ($batch in $DownloadBatches) {
    $DownloadJobs += Start-Job -ScriptBlock $DownloadJobBlock -ArgumentList $batch, $SessionOptsHash, $winscpDllPath, $LocalDestination, $Port
}

Write-Host "[5/5] Dang tai xuong..." -ForegroundColor Cyan
$DownloadJobs | Wait-Job | Out-Null
$DownloadJobs | Receive-Job
$DownloadJobs | Remove-Job

# ==================== SUMMARY ====================
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "HOAN TAT! Kiem tra folder: $LocalDestination" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

$end = Get-Date
$duration = $end - $start

Write-Host "`nThong ke:" -ForegroundColor Cyan
Write-Host "  - Tong so file da quet: $TotalScanned" -ForegroundColor Cyan 
Write-Host "  - File khop MAC: $TotalFiles" -ForegroundColor Cyan
Write-Host "  - Scan threads: $($FolderBatches.Count)" -ForegroundColor Cyan
Write-Host "  - Download threads: $($DownloadBatches.Count)" -ForegroundColor Cyan
Write-Host "  - Thoi gian thuc hien: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan