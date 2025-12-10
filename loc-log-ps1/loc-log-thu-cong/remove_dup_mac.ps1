#Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
param (
    [string]$TARGET_DIR
)

Set-StrictMode -Version Latest

#================= Ham in mau ===================
function Print-Header {
    param ([string]$text)
    Write-Host "`n=========== $text ===========" -ForegroundColor Cyan
}

function Print-Success {
    param ([string]$text)
    Write-Host $text -ForegroundColor Green
}

function Print-Warning {
    param ([string]$text)
    Write-Host $text -ForegroundColor Yellow
}

function Print-Error {
    param ([string]$text)
    Write-Host $text -ForegroundColor Red
}

#================= Ham remove duplicate MAC ===================
function Remove-DuplicateMac {
    param ([string]$folderPath)
    
    if (-not (Test-Path $folderPath)) { 
        Print-Warning "Folder khong ton tai: $folderPath"
        return 0 
    }

    $logFiles = Get-ChildItem -Path $folderPath -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in @(".log", ".txt") }

    if (-not $logFiles -or $logFiles.Count -eq 0) {
        return 0
    }

    # Nhom file theo MAC address (12+ ky tu truoc dau gach duoi)
    $groups = $logFiles | Group-Object {
        if ($_.Name -match "([^_]{12,}_)") { 
            $matches[1].TrimEnd("_") 
        }
        else { 
            "NO_MAC_$($_.Name)" # Moi file khong co MAC se co key rieng
        }
    }

    $duplicateCount = 0
    $deletedFiles = @()

    foreach ($g in $groups) {
        # Chi xu ly nhom co > 1 file VA co MAC hop le
        if ($g.Count -gt 1 -and $g.Name -notlike "NO_MAC_*") {
            # Sap xep theo timestamp (14 chu so) - giu file moi nhat
            $sorted = $g.Group | Sort-Object {
                if ($_.Name -match "_(\d{14})") { 
                    [int64]$matches[1] 
                }
                else { 
                    0 
                }
            } -Descending

            # Lay tat ca file tru file dau tien (moi nhat)
            $duplicates = $sorted | Select-Object -Skip 1

            foreach ($dup in $duplicates) {
                try {
                    $fileName = $dup.Name
                    Remove-Item -Path $dup.FullName -Force -ErrorAction Stop
                    $deletedFiles += $fileName
                    $duplicateCount++
                }
                catch {
                    Print-Error "Loi khi xoa file: $($dup.FullName)"
                }
            }
        }
    }

    # Hien thi chi tiet file da xoa
    if ($deletedFiles.Count -gt 0) {
        Print-Warning "`n  Da xoa $duplicateCount file trung MAC:"
        foreach ($file in $deletedFiles) {
            Write-Host "    - $file" -ForegroundColor DarkYellow
        }
    }

    return $duplicateCount
}

#================= MAIN LOGIC ===================
Print-Header "REMOVE DUPLICATE MAC - STANDALONE TOOL"

# Kiem tra tham so dau vao
if ([string]::IsNullOrWhiteSpace($TARGET_DIR)) {
    Print-Error "Vui long nhap duong dan thu muc!"
    Print-Warning "Cach su dung: .\remove_dup_mac.ps1 -TARGET_DIR `"C:\Path\To\Folder`""
    exit
}

if (-not (Test-Path $TARGET_DIR)) {
    Print-Error "Thu muc khong ton tai: $TARGET_DIR"
    exit
}

Print-Success "Dang xu ly thu muc: $TARGET_DIR"
Write-Host ""

#================= Lay danh sach folder con (chi cap 1, khong de quy) ===================
$subFolders = Get-ChildItem -Path $TARGET_DIR -Directory -ErrorAction SilentlyContinue

# Kiem tra xem folder goc co file log/txt khong
$rootLogFiles = Get-ChildItem -Path $TARGET_DIR -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in @(".log", ".txt") }

$foldersToProcess = @()

if ($rootLogFiles -and $rootLogFiles.Count -gt 0) {
    # Truong hop 3: Folder goc chua file log -> Xu ly luon folder goc
    Print-Warning "Phat hien $($rootLogFiles.Count) file log/txt trong folder goc. Xu ly truc tiep..."
    $foldersToProcess += $TARGET_DIR
}
elseif ($subFolders -and $subFolders.Count -gt 0) {
    # Truong hop 1-2: Folder goc khong chua file -> Xu ly cac folder con
    Print-Success "Phat hien $($subFolders.Count) folder con. Dang xu ly..."
    $foldersToProcess = $subFolders | ForEach-Object { $_.FullName }
}
else {
    Print-Warning "Khong tim thay folder con hoac file log nao trong: $TARGET_DIR"
    exit
}

#================= Xu ly tung folder ===================
$totalDuplicate = 0
$processedFolders = 0
$statistics = @()

Print-Header "BAT DAU LOC TRUNG MAC"

foreach ($folder in $foldersToProcess) {
    $folderName = Split-Path $folder -Leaf
    
    # Dem so file log/txt truoc khi xu ly
    $logFilesBefore = Get-ChildItem -Path $folder -File -ErrorAction SilentlyContinue |
                      Where-Object { $_.Extension -in @(".log", ".txt") }
    $countBefore = if ($logFilesBefore) { $logFilesBefore.Count } else { 0 }
    
    if ($countBefore -eq 0) {
        Write-Host "  [$folderName] Khong co file log/txt" -ForegroundColor Gray
        continue
    }
    
    Write-Host "`n  Dang xu ly: $folderName ($countBefore file log/txt)..." -ForegroundColor Cyan
    
    $removed = Remove-DuplicateMac -folderPath $folder
    
    # Dem lai sau khi xu ly
    $logFilesAfter = Get-ChildItem -Path $folder -File -ErrorAction SilentlyContinue |
                     Where-Object { $_.Extension -in @(".log", ".txt") }
    $countAfter = if ($logFilesAfter) { $logFilesAfter.Count } else { 0 }
    
    $totalDuplicate += $removed
    $processedFolders++
    
    # Luu thong ke
    $statistics += [PSCustomObject]@{
        Folder = $folderName
        Before = $countBefore
        Removed = $removed
        After = $countAfter
    }
    
    if ($removed -gt 0) {
        Print-Success "  -> Da xoa $removed file trung"
    }
    else {
        Write-Host "  -> Khong co file trung" -ForegroundColor Gray
    }
}

#================= TONG HOP KET QUA ===================
Print-Header "TONG HOP KET QUA"
Write-Host ""

if ($statistics.Count -gt 0) {
    # Hien thi bang thong ke
    Write-Host "CHI TIET TUNG FOLDER:" -ForegroundColor Yellow
    Write-Host ("{0,-30} {1,10} {2,10} {3,10}" -f "Folder", "Truoc", "Da xoa", "Sau") -ForegroundColor Cyan
    Write-Host ("-" * 62) -ForegroundColor Gray
    
    foreach ($stat in $statistics) {
        $color = if ($stat.Removed -gt 0) { "Yellow" } else { "Gray" }
        Write-Host ("{0,-30} {1,10} {2,10} {3,10}" -f $stat.Folder, $stat.Before, $stat.Removed, $stat.After) -ForegroundColor $color
    }
    Write-Host ("-" * 62) -ForegroundColor Gray
    Write-Host ""
}

# Tong ket
Print-Success "Thu muc goc: $TARGET_DIR"
Print-Success "So folder da xu ly: $processedFolders"
Print-Success "Tong so file trung MAC da xoa: $totalDuplicate"

Write-Host ""
Print-Header "HOAN THANH"

[System.Console]::Out.Flush()
Start-Sleep -Milliseconds 500