# --------------------------------- LƯU Ý ------------------------------------------------------------
# Để lấy đường dẫn file zip: vào folder chứa file zip, mở CMD, kéo file vào CMD sẽ hiện đường dẫn đầy đủ
# Để lấy đường dẫn folder: sau khi giải nén xong, mở folder vừa giải nén và copy đường dẫn
# Nếu bị lỗi unauthorized access thì chạy lệnh: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
# Link đến file zip hoặc link folder sau khi giải nén (vào bên trong folder rồi copy link)

param(
    [string]$FilePath,
    [string]$macFile = ""
)

Set-StrictMode -Version Latest

# ================================= KHỞI TẠO CỬA SỔ =================================
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

# ================================= HÀM TIỆN ÍCH =================================
function pr {
    param ([string]$p)
    Write-Host "=========== $p ============" -ForegroundColor Cyan
}
write-Host "new 1" -ForegroundColor Green
start-sleep -Seconds 3
function Auto-Detect-Version {
    param (
        [string]$logFolder,
        [string]$pattern,
        [int]$threshold
    )
    
    $versionCount = @{}
    $logFiles = Get-ChildItem -Path $logFolder -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in @(".log", ".txt") }
    
    Write-Host "Dang quet $($logFiles.Count) file de tim version..." -ForegroundColor Yellow
    
    foreach ($file in $logFiles) {
        try {
            $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
            if ($content -match $pattern) {
                $version = $matches[1].Trim()
                
                if ($versionCount.ContainsKey($version)) {
                    $versionCount[$version]++
                } else {
                    $versionCount[$version] = 1
                }
                
                if ($versionCount[$version] -ge $threshold) {
                    Write-Host "Da tim thay version pho bien: $version (>= $threshold file)" -ForegroundColor Green
                    return $version
                }
            }
        }
        catch {
            # Bo qua file loi
        }
    }
    
    if ($versionCount.Count -gt 0) {
        $mostCommon = $versionCount.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
        Write-Host "Version pho bien nhat: $($mostCommon.Key) ($($mostCommon.Value) file)" -ForegroundColor Green
        
        Write-Host "Cac version tim thay:" -ForegroundColor Cyan
        $versionCount.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
            Write-Host "  $($_.Key): $($_.Value) file" -ForegroundColor Gray
        }
        
        return $mostCommon.Key
    }
    
    Write-Host "Khong tim thay version nao!" -ForegroundColor Red
    return $null
}

function is_FTU_correct {
    param ([string]$path, [string]$ftu)
    if ([string]::IsNullOrEmpty($ftu)) { return $true }
    
    $content = Get-Content -Path $path -Raw
    $pattern = "FTU version *: *(FTU_.*)"

    if ($content -match $pattern) {
        $ftu_in_file = $matches[1].Trim()
        return ($ftu_in_file -eq $ftu)
    }
    return $true
}

function is_FCD_correct {
    param ([string]$path, [string]$fcd)
    if ([string]::IsNullOrEmpty($fcd)) { return $true }
    
    $content = Get-Content -Path $path -Raw
    $pattern = "FCD version *: *(FCD_.*)"
    
    if ($content -match $pattern) {
        $fcd_in_file = $matches[1].Trim()
        return ($fcd_in_file -eq $fcd)
    }
    return $true
}

function join_and_move_fail {
    param ([string]$log_dir, [string]$file_name, [string]$state, [string]$failFolder)
    $path_to_file = Join-Path $log_dir $file_name
    $path_to_des = [System.IO.Path]::Combine($failFolder, $state, $file_name)
    try {
        Copy-Item -Path $path_to_file -Destination $path_to_des -ErrorAction Stop
    }
    catch {
        Write-Host "Error moving file $path_to_file to $state" -ForegroundColor Red
    }
}

function join_and_move_pass {
    param ([string]$log_dir, [string]$file_name, [string]$state, [string]$passFolder)
    $path_to_file = Join-Path $log_dir $file_name
    $path_to_des = [System.IO.Path]::Combine($passFolder, $state, $file_name)
    try {
        Copy-Item -Path $path_to_file -Destination $path_to_des -ErrorAction Stop
    }
    catch {
        Write-Host "Error moving file $path_to_file to $state" -ForegroundColor Red
    }
}

function remove_duplicate_mac {
    param ([string]$tramFolder, [string]$duplicateMacFolder)
    if (-not (Test-Path $tramFolder)) { return }

    $logFiles = Get-ChildItem -Path $tramFolder -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in @(".log", ".txt",".bin",".png",".wav",".jpg",".xlsx") }

    $groups = $logFiles | Group-Object {
        if ($_.Name -match "([^_]{12,}_)") { $matches[1].TrimEnd("_") }
        else { "NO_MAC" }
    }

    foreach ($g in $groups) {
        if ($g.Count -gt 1 -and $g.Name -ne "NO_MAC") {
            $sorted = $g.Group | Sort-Object {
                if ($_.Name -match "_(\d{14})") { [int64]$matches[1] }
                else { 0 }
            } -Descending

            $keep = $sorted[0]
            $duplicates = $sorted | Select-Object -Skip 1

            foreach ($dup in $duplicates) {
                try {
                    Move-Item -Path $dup.FullName -Destination $duplicateMacFolder -Force
                    Write-Host "Moved duplicate MAC file $($dup.Name)" -ForegroundColor Yellow
                    $script:total_duplicate++
                }
                catch {
                    Write-Host "Error moving duplicate file $($dup.FullName)" -ForegroundColor Red
                }
            }
        }
    }
}

# ================================= KIỂM TRA INPUT =================================
if (-not (Test-Path $FilePath)) {
    Write-Host "Path khong ton tai. Vui long kiem tra lai!" -ForegroundColor Red
    exit
}

# ================================= XỬ LÝ FILE ZIP =================================
$isZipFile = $false
$final_LOG_FOLDER = ""
$parent_of_log = ""

if (Test-Path $FilePath -PathType Leaf) {
    Write-Host "Phat hien file ZIP, dang xu ly..." -ForegroundColor Green
    $isZipFile = $true
    
    $nameFolder = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    $folder_containing_zip = Split-Path $FilePath
    
    # Tạo folder với timestamp
    $timeStamp = Get-Date -Format "HH-mm"
    $folderName = "Log-$($timeStamp)"
    $locLogPath = Join-Path -Path $folder_containing_zip -ChildPath $folderName
    
    if (Test-Path $locLogPath) {
        Write-Host "Remove folder $($folderName) old..."
        Remove-Item -Path $locLogPath -Recurse -Force
    }
    
    Write-Host "Tao folder $($folderName)..."
    New-Item -Path $locLogPath -ItemType Directory -Force | Out-Null
    
    pr -p $FilePath
    pr -p $nameFolder
    
    Write-Host "Dang giai nen..."
    & "C:\Program Files\7-Zip\7z.exe" x $FilePath -aoa -o"$locLogPath" -y
    
    # Tìm file MAC nếu chưa có
    if ([string]::IsNullOrEmpty($macFile)) {
        $names = @("data.txt", "mac.txt", "maclist.txt")
        
        foreach ($name in $names) {
            $file = Get-ChildItem -Path $locLogPath -Recurse -File |
                Where-Object { $_.Name -ieq $name } | Select-Object -First 1
            
            if ($file) {
                $macFile = $file.FullName
                break
            }
        }
        
        if ($macFile.Length -gt 0) {
            Write-Host "Da tim thay: $macFile" -ForegroundColor Green
            Start-Sleep -Seconds 2
        } else {
            Write-Host "Khong tim thay file mac!" -ForegroundColor Yellow
            Start-Sleep -Seconds 2
        }
    }
    
    # Tìm folder LOG trong folder giải nén
    $found = Get-ChildItem -Path $locLogPath -Recurse -Directory -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -imatch "^log$" }
    
    if ($found) {
        $final_LOG_FOLDER = $found[0].FullName
        Write-Host "Da tim thay folder log: $final_LOG_FOLDER" -ForegroundColor Green
    }
    else {
        Write-Host "Khong tim thay folder log trong loc_log!" -ForegroundColor Yellow
        Write-Host "Hay dam bao file zip chua folder LOG hoac log!" -ForegroundColor Yellow
        exit
    }
    
    $parent_of_log = (Get-Item $final_LOG_FOLDER).Parent.FullName
}
# ================================= XỬ LÝ FOLDER =================================
elseif (Test-Path $FilePath -PathType Container) {
    Write-Host "Phat hien FOLDER, dang xu ly..." -ForegroundColor Green
    
    # Tìm folder LOG
    $found = Get-ChildItem -Path $FilePath -Recurse -Directory -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -imatch "^log$" }
    
    if ($found) {
        $final_LOG_FOLDER = $found[0].FullName
        Write-Host "Da tim thay folder log: $final_LOG_FOLDER" -ForegroundColor Green
    }
    else {
        Write-Host "Khong tim thay folder log!" -ForegroundColor Yellow
        Write-Host "Hay dat ten folder chua file LOG thanh LOG hoac log!" -ForegroundColor Yellow
        exit
    }
    
    $parent_of_log = (Get-Item $final_LOG_FOLDER).Parent.FullName
}

$Tong_file_log = @((Get-Item $final_LOG_FOLDER).GetFiles()).Count
Write-Host "Tong so file log: $Tong_file_log" -ForegroundColor Cyan

# ================================= TỰ ĐỘNG PHÁT HIỆN FTU VÀ FCD =================================
Write-Host "`n"
pr -p "TU DONG PHAT HIEN FTU VA FCD"
Write-Host "`n"

$allLogFiles = Get-ChildItem -Path $final_LOG_FOLDER -File -ErrorAction SilentlyContinue |
               Where-Object { $_.Extension -in @(".log", ".txt") }
$totalLogFiles = $allLogFiles.Count
$dynamicThreshold = [Math]::Max(1, [Math]::Ceiling($totalLogFiles * 0.15))

Write-Host "Tong so file log/txt: $totalLogFiles" -ForegroundColor Yellow
Write-Host "Nguong dong (15%): $dynamicThreshold file" -ForegroundColor Yellow
Write-Host "`n"

$FTU_PATTERN = "FTU version *: *(FTU_.*)"
$FCD_PATTERN = "FCD version *: *(FCD_.*)"

Write-Host "Dang quet FTU..." -ForegroundColor Cyan
$FTU = Auto-Detect-Version -logFolder $final_LOG_FOLDER -pattern $FTU_PATTERN -threshold $dynamicThreshold

Write-Host "`nDang quet FCD..." -ForegroundColor Cyan
$FCD = Auto-Detect-Version -logFolder $final_LOG_FOLDER -pattern $FCD_PATTERN -threshold $dynamicThreshold

if (-not $FTU) {
    Write-Host "CANH BAO: Khong tim thay FTU! Script se tiep tuc nhung khong loc FTU." -ForegroundColor Red
    $FTU = ""
}

if (-not $FCD) {
    Write-Host "CANH BAO: Khong tim thay FCD! Script se tiep tuc nhung khong loc FCD." -ForegroundColor Red
    $FCD = ""
}

Write-Host "`n"
pr -p "FTU da chon: $FTU"
pr -p "FCD da chon: $FCD"
Write-Host "`n"
Start-Sleep -Seconds 2

# ================================= TẠO CÁC FOLDER =================================
$passFolder = Join-Path $parent_of_log "PASS"
$failFolder = Join-Path $parent_of_log "FAIL"

if (Test-Path $passFolder) {
    Remove-Item $passFolder -Recurse -Force
}
if (Test-Path $failFolder) {
    Remove-Item $failFolder -Recurse -Force
}

New-Item -Path $passFolder -ItemType Directory -Force | Out-Null
New-Item -Path $failFolder -ItemType Directory -Force | Out-Null

$cac_tram_test = @("DL","PT" ,"PT0", "PT1", "PT2", "PT3", "PT4","PT5","PT6", "BURN", "FT1", "FT2", "FT3", "FT4", "FT5", "FT6", "FT7", "FT8", "FT9", "FT10", "FT11", "FT12", "FT13", "FT14","FT15","FT","600I","25G")
$cac_tram_test | ForEach-Object {
    New-Item -Path (Join-Path $passFolder $_) -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $failFolder $_) -ItemType Directory -Force | Out-Null
}

# ================================= PHÂN LOẠI LOG =================================
Write-Host "`n"
Write-Host "============ Phan loai log PASS va FAIL =============" -ForegroundColor Cyan
Start-Sleep -Seconds 1

$log_files = Get-ChildItem -Path $final_LOG_FOLDER -File
$count_pass = 0
$count_fail = 0

foreach ($file in $log_files) {
    $fileName = $file.Name
    
    # Phân loại PASS
    switch -regex ($fileName) {
        "^PASS.*_600I" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "600I" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_25G" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "25G" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_DOWNLOAD_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "DL" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_PT0_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "PT0" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_PT1_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "PT1" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_PT2_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "PT2" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_PT3_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "PT3" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_PT4_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "PT4" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_PT5_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "PT5" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_PT6_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "PT6" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_PT_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "PT" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_FT1_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "FT1" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_FT2_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "FT2" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_FT3_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "FT3" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_FT4_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "FT4" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_FT5_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "FT5" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_FT6_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "FT6" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_FT7_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "FT7" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_FT8_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "FT8" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_FT9_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "FT9" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_FT10_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "FT10" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_FT11_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "FT11" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_FT12_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "FT12" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_FT13_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "FT13" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_FT14_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "FT14" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_FT15_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "FT15" -passFolder $passFolder; $count_pass++; continue }
        "^PASS.*_FT_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $fileName -state "FT" -passFolder $passFolder; $count_pass++; continue }
    }
    
    # Phân loại FAIL
    switch -regex ($fileName) {
        "^FAIL.*_DOWNLOAD_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $fileName -state "DL" -failFolder $failFolder; $count_fail++; continue }
        "^FAIL.*_PT0_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $fileName -state "PT0" -failFolder $failFolder; $count_fail++; continue }
        "^FAIL.*_PT1_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $fileName -state "PT1" -failFolder $failFolder; $count_fail++; continue }
        "^FAIL.*_PT2_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $fileName -state "PT2" -failFolder $failFolder; $count_fail++; continue }
        "^FAIL.*_PT3_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $fileName -state "PT3" -failFolder $failFolder; $count_fail++; continue }
        "^FAIL.*_PT4_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $fileName -state "PT4" -failFolder $failFolder; $count_fail++; continue }
        "^FAIL.*_PT_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $fileName -state "PT" -failFolder $failFolder; $count_fail++; continue }
        "^FAIL.*_BURN_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $fileName -state "BURN" -failFolder $failFolder; $count_fail++; continue }
        "^FAIL.*_FT1_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $fileName -state "FT1" -failFolder $failFolder; $count_fail++; continue }
        "^FAIL.*_FT2_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $fileName -state "FT2" -failFolder $failFolder; $count_fail++; continue }
        "^FAIL.*_FT3_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $fileName -state "FT3" -failFolder $failFolder; $count_fail++; continue }
        "^FAIL.*_FT4_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $fileName -state "FT4" -failFolder $failFolder; $count_fail++; continue }
        "^FAIL.*_FT5_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $fileName -state "FT5" -failFolder $failFolder; $count_fail++; continue }
        "^FAIL.*_FT6_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $fileName -state "FT6" -failFolder $failFolder; $count_fail++; continue }
        "^FAIL.*_FT7_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $fileName -state "FT7" -failFolder $failFolder; $count_fail++; continue }
        "^FAIL.*_600I_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $fileName -state "600I" -failFolder $failFolder; $count_fail++; continue }
    }
}

# Xóa folder rỗng
foreach ($tram in $cac_tram_test) {
    $folderPath_P = Join-Path $passFolder $tram
    $folderPath_F = Join-Path $failFolder $tram

    if (Test-Path $folderPath_P) {
        $items_P = Get-ChildItem -Path $folderPath_P -ErrorAction SilentlyContinue
        if (-not $items_P) {
            Remove-Item -Path $folderPath_P -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if (Test-Path $folderPath_F) {
        $items_F = Get-ChildItem -Path $folderPath_F -ErrorAction SilentlyContinue
        if (-not $items_F) {
            Remove-Item -Path $folderPath_F -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ================================= GOM FILE KHÁC =================================
Write-Host "`n"
Write-Host "============ Gom file khac (png, wav) =============" -ForegroundColor Cyan
foreach ($tram in $cac_tram_test) {
    $folderPath_P = Join-Path $passFolder $tram
    if (Test-Path $folderPath_P) {
        $otherFiles = Get-ChildItem -Path $folderPath_P -File -ErrorAction SilentlyContinue |
                      Where-Object { $_.Extension -notin @(".log", ".txt") }
        if ($otherFiles -and @($otherFiles).Count -gt 0) {
            $newFolder = Join-Path $folderPath_P "Other_Files"
            New-Item -Path $newFolder -ItemType Directory -Force | Out-Null
            foreach ($f in $otherFiles) {
                try {
                    Move-Item -Path $f.FullName -Destination $newFolder -Force
                }
                catch {
                    Write-Host "Error moving file $($f.FullName) to $newFolder" -ForegroundColor Red
                }
            }
            Write-Host "Moved $(@($otherFiles).Count) file khac tram $tram to Other_Files folder" -ForegroundColor Green
        }
    }
}

# ================================= LỌC FTU-FCD =================================
Write-Host "`n"
Write-Host "============ Loc FTU-FCD =============" -ForegroundColor Cyan
Start-Sleep -Seconds 1
Write-Host "`n"

$wrongVersionFolder = Join-Path $parent_of_log "WRONG_VERSION"
New-Item -Path $wrongVersionFolder -ItemType Directory -Force | Out-Null

$count_wrong_version = 0

foreach ($tram in $cac_tram_test) {
    $folderPath_P = Join-Path $passFolder $tram
    if (Test-Path $folderPath_P) {
        $logFiles = Get-ChildItem -Path $folderPath_P -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Extension -in @(".log", ".txt") }

        foreach ($f in $logFiles) {
            $isCorrect = $true

            if ($tram -eq "DL") {
                $isCorrect = is_FCD_correct -path $f.FullName -fcd $FCD
            }
            else {
                $isCorrect = is_FTU_correct -path $f.FullName -ftu $FTU
            }

            if (-not $isCorrect) {
                try {
                    Move-Item -Path $f.FullName -Destination $wrongVersionFolder -Force
                    Write-Host "Moved wrong version file $($f.Name) from $tram to WRONG_VERSION" -ForegroundColor Magenta
                    $count_wrong_version++
                }
                catch {
                    Write-Host "Error moving file $($f.FullName)" -ForegroundColor Red
                }
            }
        }
    }
}

# ================================= PHÂN LOẠI CÁC OTHERFILE =================================
function Get-FileExtensions {
    param ([string]$folderPath)
    
    if (-not (Test-Path $folderPath)) { return @() }
    
    $files = Get-ChildItem -Path $folderPath -File -ErrorAction SilentlyContinue
    
    # LẤY UNIQUE THEO PATTERN _XXX.EXTENSION
    $extensions = $files | ForEach-Object {
        $fileName = $_.Name
        # Tìm vị trí dấu _ cuối cùng trước extension
        $lastUnderscoreIndex = $fileName.LastIndexOf('_')
        
        if ($lastUnderscoreIndex -ge 0) {
            # Lấy phần từ dấu _ cuối đến hết (bao gồm extension)
            $pattern = $fileName.Substring($lastUnderscoreIndex)
            return $pattern
        }
        else {
            # Nếu không có dấu _, chỉ lấy extension
            return $_.Extension
        }
    } | Select-Object -Unique |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { 
            # Chuyển _Val.xlsx thành Val_xlsxFile
            # Chuyển _CAL.bin thành CAL_binFile
            $pattern = $_.TrimStart('_')
            $parts = $pattern -split '\.'
            if ($parts.Count -eq 2) {
                return $parts[0] + "_" + $parts[1] + "File"
            }
            else {
                return $pattern.TrimStart('.') + "File"
            }
        }
    
    # ĐẢM BẢO TRẢ VỀ MẢNG
    if ($null -eq $extensions) {
        return @()
    }
    
    return @($extensions)
}

function Organize-FilesByExtension {
    param ([string]$otherFilesPath)
    
    if (-not (Test-Path $otherFilesPath)) { return }
    
    $extensionTypes = Get-FileExtensions -folderPath $otherFilesPath
    $extensionTypes = @($extensionTypes)
    
    if ($extensionTypes.Count -le 1) {
        Write-Host "  Chi co 1 loai file hoac khong co file, bo qua" -ForegroundColor Gray
        return
    }
    
    Write-Host "  Tim thay $($extensionTypes.Count) loai file: $($extensionTypes -join ', ')" -ForegroundColor Yellow
    
    foreach ($extType in $extensionTypes) {
        # Chuyển ngược lại: Val_xlsxFile → _Val.xlsx
        $pattern = $extType -replace 'File$', ''
        $parts = $pattern -split '_'
        
        if ($parts.Count -eq 2) {
            $searchPattern = "_$($parts[0]).$($parts[1])"
        }
        else {
            $searchPattern = ".$pattern"
        }
        
        $subFolder = Join-Path $otherFilesPath $extType
        
        if (-not (Test-Path $subFolder)) {
            New-Item -Path $subFolder -ItemType Directory -Force | Out-Null
        }
        
        # Tìm file theo pattern
        $filesToMove = Get-ChildItem -Path $otherFilesPath -File -ErrorAction SilentlyContinue |
                       Where-Object { $_.Name -like "*$searchPattern" }
        
        foreach ($file in $filesToMove) {
            try {
                Move-Item -Path $file.FullName -Destination $subFolder -Force
            }
            catch {
                Write-Host "  Loi khi move file $($file.Name): $_" -ForegroundColor Red
            }
        }
        
        Write-Host "  Da move $(@($filesToMove).Count) file $searchPattern vao $extType" -ForegroundColor Green
    }
}

function Invoke-OtherFilesInFolder {
    param ([string]$baseFolderPath)
    
    if (-not (Test-Path $baseFolderPath)) { return }
    
    $otherFilesFolders = Get-ChildItem -Path $baseFolderPath -Directory -Recurse -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -eq "Other_Files" }
    
    foreach ($folder in $otherFilesFolders) {
        Write-Host "Dang xu ly: $($folder.FullName)" -ForegroundColor Cyan
        Organize-FilesByExtension -otherFilesPath $folder.FullName
    }
}

Invoke-OtherFilesInFolder -baseFolderPath $passFolder


# ================================= LỌC TRÙNG MAC =================================
Write-Host "`n"
Write-Host "============ Loc trung MAC =============" -ForegroundColor Cyan
Start-Sleep -Seconds 1
Write-Host "`n"

$duplicateMacFolder = Join-Path $parent_of_log "DUPLICATE_MAC"
New-Item -Path $duplicateMacFolder -ItemType Directory -Force | Out-Null
$total_duplicate = 0

$allFolders = Get-ChildItem -Path $passFolder -Directory -Recurse -ErrorAction SilentlyContinue
foreach ($folder in $allFolders) {
    try {
        if (-not [string]::IsNullOrWhiteSpace($folder.FullName)) {
            remove_duplicate_mac -tramFolder $folder.FullName -duplicateMacFolder $duplicateMacFolder
        }
    }
    catch {
        Write-Host "Loi khi loc trung MAC tai folder: $($folder.FullName)" -ForegroundColor Red
        Write-Host "Chi tiet loi: $_" -ForegroundColor Red
    }
}

# ================================= KIỂM TRA MAC THIẾU FILE =================================
Write-Host "`n"
Write-Host "============ Kiem tra MAC thieu file =============" -ForegroundColor Cyan
Start-Sleep -Seconds 1
Write-Host "`n"

$macHashTable = @{}
$totalMac = 0
$missingMacList = @()

if (-not [string]::IsNullOrWhiteSpace($macFile) -and (Test-Path $macFile)) {
    try {
        $macLines = Get-Content -Path $macFile -ErrorAction Stop
        foreach ($line in $macLines) {
            $mac = $line.Trim().ToUpper()
            if (-not [string]::IsNullOrWhiteSpace($mac)) {
                $macHashTable[$mac] = 0
                $totalMac++
            }
        }
        Write-Host "Da nap $totalMac dia chi MAC tu file: $macFile" -ForegroundColor Green
        
        foreach ($tram in $cac_tram_test) {
            $folderPath_P = Join-Path $passFolder $tram
            if (Test-Path $folderPath_P) {
                $logFiles = Get-ChildItem -Path $folderPath_P -File -ErrorAction SilentlyContinue |
                            Where-Object { $_.Extension -in @(".log", ".txt") }
                
                $fileCount = @($logFiles).Count
                
                if ($fileCount -lt $totalMac) {
                    foreach ($key in @($macHashTable.Keys)) {
                        $macHashTable[$key] = 0
                    }
                    
                    foreach ($fileInfo in $logFiles) {
                        if ($fileInfo.Name -match "([^_]{12,}_)") {
                            $extractedMac = $matches[1].Trim('_').ToUpper()
                            if ($macHashTable.ContainsKey($extractedMac)) {
                                $macHashTable[$extractedMac]++
                            }
                        }
                    }
                    
                    foreach ($mac in @($macHashTable.Keys)) {
                        if ($macHashTable[$mac] -eq 0) {
                            $missingMacList += "${mac}_[$tram]"
                        }
                    }
                }
            }
        }
        
        if ($missingMacList.Count -gt 0) {
            $missingMacFile = Join-Path $parent_of_log "mac_thieu_file.txt"
            $missingMacList | Out-File -FilePath $missingMacFile -Encoding UTF8
            Write-Host "Co $($missingMacList.Count) dia chi MAC thieu file" -ForegroundColor Red
            Write-Host "Chi tiet xem tai: $missingMacFile" -ForegroundColor Yellow
            Start-Process notepad.exe $missingMacFile
        }
        else {
            Write-Host "Tat ca dia chi MAC deu co file log" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Loi khi doc file MAC: $_" -ForegroundColor Red
    }
}
else {
    if (-not [string]::IsNullOrWhiteSpace($macFile)) {
        Write-Host "Khong tim thay file MAC: $macFile" -ForegroundColor Yellow
    }
    Write-Host "Bo qua chuc nang kiem tra MAC thieu file" -ForegroundColor Gray
}

# ================================= TỔNG HỢP SỐ LIỆU =================================
Write-Host "`n`n"
Write-Host "============ TONG HOP SO LIEU =============" -ForegroundColor Green
Start-Sleep -Seconds 1

function Get-AllFoldersWithFiles {
    param ([string]$rootPath)
    
    if (-not (Test-Path $rootPath)) { return @() }
    
    $allFolders = Get-ChildItem -Path $rootPath -Directory -Recurse -ErrorAction SilentlyContinue
    $allFolders = @($rootPath) + @($allFolders | Select-Object -ExpandProperty FullName)
    
    $result = @()
    
    foreach ($folder in $allFolders) {
        $files = Get-ChildItem -Path $folder -File -ErrorAction SilentlyContinue
        $fileCount = @($files).Count
        
        if ($fileCount -gt 0) {
            $relativePath = $folder -replace [regex]::Escape($rootPath), ""
            $relativePath = $relativePath.TrimStart('\')
            
            if ([string]::IsNullOrWhiteSpace($relativePath)) {
                $displayName = "[Root PASS]"
            } else {
                $displayName = $relativePath
            }
            
            $result += [PSCustomObject]@{
                Folder = $displayName
                Files = $fileCount
            }
        }
    }
    
    return $result
}

$folderStats = Get-AllFoldersWithFiles -rootPath $passFolder
$folderStats= @($folderStats)
if ($folderStats.Count -gt 0) {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor DarkGray
    Write-Host ("{0,-50} {1,15}" -f "FOLDER", "SO LUONG FILE") -ForegroundColor Yellow
    Write-Host ("=" * 70) -ForegroundColor DarkGray
    
    $folderStats | Sort-Object Folder | ForEach-Object {
        Write-Host ("{0,-50} {1,15}" -f $_.Folder, $_.Files) -ForegroundColor Cyan
    }
    
    Write-Host ("=" * 70) -ForegroundColor DarkGray
    Write-Host ""
} else {
    Write-Host "Khong co folder nao chua file" -ForegroundColor Yellow
}


Write-Host "`n======================================"
try {
    pr -p "PASS: $count_pass"
    pr -p "FAIL: $count_fail"
    pr -p "SAI FTU/FCD: $count_wrong_version"
    pr -p "TRUNG MAC: $total_duplicate"
    pr -p "So file log truoc khi xu li: $Tong_file_log"
    pr -p "Tong so file da xu li: $($count_pass + $count_fail)"
}
catch {
    Write-Host "Error when printing summary: $_" -ForegroundColor Red
}

Write-Host "`n"
Write-Host "============ HOAN THANH =============" -ForegroundColor Green
[System.Console]::Out.Flush()
Start-Sleep -Milliseconds 300