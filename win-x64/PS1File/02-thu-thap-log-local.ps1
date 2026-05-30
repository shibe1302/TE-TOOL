param(
    [string]$SourceFolder,
    [string]$DestinationFolder,
    [string]$MacFilePath,
    [int]$MaxScanThreads

)
    [int]$MaxCopyThreads = 10
# [string]$SourceFolder="E:\SFTP_Data\tess2\ucg"
# [string]$DestinationFolder="E:\download_log"
# [string]$MacFilePath="E:\nghien_cuu_FTU\UCG_FIBER_40pcs_log\data.txt"
# [int]$MaxScanThreads = 10
# [int]$MaxCopyThreads = 10

# ==================== WINDOW POSITIONING ====================
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

# ==================== CONFIGURATION EXAMPLE ====================
# Uncomment và điền thông tin của bạn:
# $SourceFolder = "E:\source_folder"
# $DestinationFolder = "E:\destination_folder"
# $MacFilePath = "E:\mac_list.txt"
# $MaxScanThreads = 10
# $MaxCopyThreads = 10

# ==================== VALIDATION FUNCTION ====================
function Validate-Configuration {
    Write-Host "[Validation] Checking configuration..." -ForegroundColor Cyan
    
    if (-not (Test-Path $SourceFolder)) {
        Write-Host "Loi: Khong tim thay source folder: $SourceFolder" -ForegroundColor Red
        exit 1
    }
    
    if (-not (Test-Path $MacFilePath)) {
        Write-Host "Loi: Khong tim thay file MAC list: $MacFilePath" -ForegroundColor Red
        exit 1
    }
    
    if (-not (Test-Path $DestinationFolder)) {
        try {
            New-Item -ItemType Directory -Path $DestinationFolder -Force | Out-Null
            Write-Host "Tao folder dich: $DestinationFolder" -ForegroundColor Green
        }
        catch {
            Write-Host "Loi: Khong the tao folder dich: $DestinationFolder" -ForegroundColor Red
            exit 1
        }
    }
    
    Write-Host "Tat ca cau hinh hop le`n" -ForegroundColor Green
}

# ==================== MAIN SCRIPT ====================
Write-Host "`n========== LOCAL FILE SCANNER - PARALLEL VERSION ==========" -ForegroundColor Magenta
Validate-Configuration

$start = Get-Date

# ==================== STEP 1: LOAD MAC DATABASE ====================
Write-Host "[1/4] Dang doc danh sach MAC..." -ForegroundColor Cyan
$MacDb = New-Object System.Collections.Generic.HashSet[string]

try {
    $RawMacs = Get-Content $MacFilePath -ErrorAction Stop
    foreach ($mac in $RawMacs) {
        $cleanMac = $mac.Trim().ToUpper()
        if (-not [string]::IsNullOrWhiteSpace($cleanMac)) {
            [void]$MacDb.Add($cleanMac)
        }
    }
    
    if ($MacDb.Count -eq 0) {
        Write-Host "Canh bao: File MAC list rong!" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "-> Da nap $($MacDb.Count) MAC vao bo nho." -ForegroundColor Green
}
catch {
    Write-Error "Loi khi doc file MAC list: $($_.Exception.Message)"
    exit 1
}

# ==================== STEP 2: GET ROOT FOLDERS ====================
Write-Host "[2/4] Dang lay danh sach folder con trong $SourceFolder..." -ForegroundColor Cyan

$RootFolders = @()
try {
    $SubFolders = Get-ChildItem -Path $SourceFolder -Directory -ErrorAction Stop
    
    foreach ($folder in $SubFolders) {
        $RootFolders += $folder.FullName
    }
    
    Write-Host "-> Tim thay $($RootFolders.Count) folder con" -ForegroundColor Green
    
    if ($RootFolders.Count -eq 0) {
        Write-Host "-> Khong co folder con, se scan truc tiep trong $SourceFolder" -ForegroundColor Yellow
        $RootFolders = @($SourceFolder)
    }
}
catch {
    Write-Error "Loi khi lay danh sach folder: $($_.Exception.Message)"
    exit 1
}

# ==================== STEP 3: PARALLEL SCAN ====================
Write-Host "[3/4] Dang khoi tao scan song song..." -ForegroundColor Cyan

# Chia folders thanh batches
$FolderBatches = @()
$BatchSize = [Math]::Ceiling($RootFolders.Count / $MaxScanThreads)

for ($i = 0; $i -lt $RootFolders.Count; $i += $BatchSize) {
    $count = [Math]::Min($BatchSize, ($RootFolders.Count - $i))
    $batch = $RootFolders[$i..($i + $count - 1)]
    $FolderBatches += , $batch
}

Write-Host "-> Chia thanh $($FolderBatches.Count) batch de xu ly" -ForegroundColor Cyan

# ScriptBlock cho scan job
$ScanJobBlock = {
    param($FolderList, $MacDbArray)
    
    # Tao HashSet tu array de co O(1) lookup
    $MacDbSet = New-Object System.Collections.Generic.HashSet[string]
    foreach ($mac in $MacDbArray) {
        [void]$MacDbSet.Add($mac)
    }
    
    $LocalResults = @{}
    $ScannedCount = 0
    
    # Duyet qua tung folder trong batch
    foreach ($folder in $FolderList) {
        try {
            # Lay tat ca file trong folder va subfolder
            $files = Get-ChildItem -Path $folder -File -Recurse -ErrorAction SilentlyContinue
            
            foreach ($file in $files) {
                $ScannedCount++
                
                # Extract MAC tu filename
                if (($file.Name -match "([^_]{12,}_)")) {
                    $extractedMac = $matches[1].Trim('_').ToUpper()
                    write-Host $extractedMac -ForegroundColor Yellow
                    if ($MacDbSet.Contains($extractedMac)) {
                        $LocalResults[$file.FullName] = $file.Name
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

# Chuyen HashSet thanh array de truyen qua Job
$MacDbArray = @($MacDb)

# Khoi tao scan jobs
$ScanJobs = @()
$jobIndex = 0
foreach ($batch in $FolderBatches) {
    $jobIndex++
    Write-Host "   -> Khoi tao Job #$jobIndex voi $($batch.Count) folder(s)" -ForegroundColor Gray
    $ScanJobs += Start-Job -ScriptBlock $ScanJobBlock -ArgumentList $batch, $MacDbArray
}

# Cho jobs hoan thanh
Write-Host "-> Dang cho cac job hoan thanh..." -ForegroundColor Cyan
$ScanJobs | Wait-Job | Out-Null

# Thu thap ket qua
$FilesToCopy = [System.Collections.Generic.List[object]]::new()
$TotalScanned = 0

foreach ($job in $ScanJobs) {
    $result = Receive-Job -Job $job
    
    if ($result -and $result.Files) {
        $TotalScanned += $result.ScannedCount
        
        foreach ($key in $result.Files.Keys) {
            $FilesToCopy.Add(@{
                    SourcePath = $key
                    FileName   = $result.Files[$key]
                })
        }
    }
}

$ScanJobs | Remove-Job

$TotalFiles = $FilesToCopy.Count
Write-Host "-> Scan hoan tat!" -ForegroundColor Green
Write-Host "   - Tong so file da quet: $TotalScanned" -ForegroundColor Yellow
Write-Host "   - File khop MAC: $TotalFiles" -ForegroundColor Yellow

if ($TotalFiles -eq 0) { 
    Write-Host "Khong co file nao de copy. Ket thuc." -ForegroundColor Yellow
    exit 
}

# ==================== STEP 4: PARALLEL COPY ====================
Write-Host "[4/4] Dang khoi tao $MaxCopyThreads luong copy..." -ForegroundColor Cyan

$CopyBatches = @()
$CopyBatchSize = [Math]::Ceiling($TotalFiles / $MaxCopyThreads)
for ($i = 0; $i -lt $TotalFiles; $i += $CopyBatchSize) {
    $count = [Math]::Min($CopyBatchSize, ($TotalFiles - $i))
    $CopyBatches += , $FilesToCopy.GetRange($i, $count)
}

$CopyJobBlock = {
    param($FileBatch, $DestDir)
    
    $SuccessCount = 0
    $SkipCount = 0
    $FailCount = 0
    
    foreach ($f in $FileBatch) {
        $destFilePath = Join-Path $DestDir $f.FileName
        
        try {
            # Kiem tra file da ton tai chua
            if (Test-Path $destFilePath) {
                Write-Host "File da ton tai: $($f.FileName)" -ForegroundColor Yellow
                $SkipCount++
                continue
            }
            
            # Copy file
            Copy-Item -Path $f.SourcePath -Destination $destFilePath -Force -ErrorAction Stop
            Write-Host "Copied: $($f.FileName)" -ForegroundColor Green
            $SuccessCount++
        }
        catch {
            Write-Error "Loi copy file $($f.FileName): $($_.Exception.Message)"
            $FailCount++
        }
    }
    
    return @{
        Success = $SuccessCount
        Skipped = $SkipCount
        Failed  = $FailCount
    }
}

$CopyJobs = @()
foreach ($batch in $CopyBatches) {
    $CopyJobs += Start-Job -ScriptBlock $CopyJobBlock -ArgumentList $batch, $DestinationFolder
}

Write-Host "-> Dang copy file..." -ForegroundColor Cyan
$CopyJobs | Wait-Job | Out-Null

# Thu thap thong ke copy
$TotalSuccess = 0
$TotalSkipped = 0
$TotalFailed = 0

foreach ($job in $CopyJobs) {
    $result = Receive-Job -Job $job
    if ($result) {
        $TotalSuccess += $result.Success
        $TotalSkipped += $result.Skipped
        $TotalFailed += $result.Failed
    }
}

$CopyJobs | Remove-Job

# ==================== SUMMARY ====================
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "HOAN TAT! Kiem tra folder: $DestinationFolder" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

$end = Get-Date
$duration = $end - $start

Write-Host "`nThong ke:" -ForegroundColor Cyan
Write-Host "  - Tong so file da quet: $TotalScanned" -ForegroundColor Cyan 
Write-Host "  - File khop MAC: $TotalFiles" -ForegroundColor Cyan
Write-Host "  - File copy thanh cong: $TotalSuccess" -ForegroundColor Green
Write-Host "  - File da ton tai (bo qua): $TotalSkipped" -ForegroundColor Yellow
Write-Host "  - File loi: $TotalFailed" -ForegroundColor Red
Write-Host "  - Scan threads: $($FolderBatches.Count)" -ForegroundColor Cyan
Write-Host "  - Copy threads: $($CopyBatches.Count)" -ForegroundColor Cyan
Write-Host "  - Thoi gian thuc hien: $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor Cyan