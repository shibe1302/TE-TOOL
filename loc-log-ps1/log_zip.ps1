#Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
param (
    [string]$zipFile
)


Set-StrictMode -Version Latest

#================= Ham print ===================
function pr {
    param ([string]$p)
    Write-Host "=========== $p ============" -ForegroundColor Cyan
}

#================= AUTO-DETECT FTU/FCD ===================
function Auto-Detect-Version {
    param (
        [string]$logFolder,
        [string]$pattern,
        [int]$threshold = 150
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
                
                # Neu dat nguong thi thoat ngay
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
    
    # Neu khong co version nao dat nguong, lay version nhieu nhat
    if ($versionCount.Count -gt 0) {
        $mostCommon = $versionCount.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
        Write-Host "Version pho bien nhat: $($mostCommon.Key) ($($mostCommon.Value) file)" -ForegroundColor Green
        
        # Hien thi tat ca version tim thay
        Write-Host "Cac version tim thay:" -ForegroundColor Cyan
        $versionCount.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
            Write-Host "  $($_.Key): $($_.Value) file" -ForegroundColor Gray
        }
        
        return $mostCommon.Key
    }
    
    Write-Host "Khong tim thay version nao!" -ForegroundColor Red
    return $null
}

#================= giai nen file va don dep ===================
$nameFolder = [System.IO.Path]::GetFileNameWithoutExtension($zipFile)
$folder_containing_zip = Split-Path $zipFile

# Kiểm tra và xóa folder loc_log nếu tồn tại
$locLogPath = Join-Path -Path $folder_containing_zip -ChildPath "loc_log"
if (Test-Path $locLogPath) {
    Write-Host "Đang xóa folder loc_log cũ..."
    Remove-Item -Path $locLogPath -Recurse -Force
}

# Tạo folder loc_log mới
Write-Host "Tạo folder loc_log..."
New-Item -Path $locLogPath -ItemType Directory -Force | Out-Null

pr -p $zipFile
pr -p $nameFolder

# Giải nén vào folder loc_log
Write-Host "Đang giải nén..."
& "C:\Program Files\7-Zip\7z.exe" x $zipFile -aoa -o"$locLogPath" -y

#================= Tim folder LOG ===================
$locLogPath = Join-Path -Path $folder_containing_zip -ChildPath "loc_log"

# Tìm folder có tên là "log" hoặc "LOG" trong loc_log
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
Write-Output "Parent cua log: $parent_of_log"

$Tong_file_log = (Get-ChildItem -Path $final_LOG_FOLDER -File).Count
Write-Output "Tong so file log: $Tong_file_log"

#================= TU DONG PHAT HIEN FTU VA FCD ===================
Write-Host "`n"
pr -p "TU DONG PHAT HIEN FTU VA FCD"
Write-Host "`n"

# Tinh nguong 15% tong so file log/txt
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

#================= Tao cac folder cua cac tram test ===================
$passFolder = Join-Path $parent_of_log "PASS"
$failFolder = Join-Path $parent_of_log "FAIL"
New-Item -Path $passFolder -ItemType Directory -Force | Out-Null
New-Item -Path $failFolder -ItemType Directory -Force | Out-Null
$cac_tram_test = @("DL", "PT", "PT0", "PT1", "PT2", "PT3", "PT4", "BURN", "FT1", "FT2", "FT3", "FT4", "FT5", "FT6")
$cac_tram_test | ForEach-Object {
    New-Item -Path (Join-Path $passFolder $_) -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $failFolder $_) -ItemType Directory -Force | Out-Null
}

#================= Kiem tra FTU ========================
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

#================= Ham di chuyen file ===================
function join_and_move_fail {
    param ([string]$log_dir, [string]$file_name, [string]$state)
    $path_to_file = Join-Path $log_dir $file_name
    $path_to_des = [System.IO.Path]::Combine($failFolder, $state, $file_name)
    try {
        Move-Item -Path $path_to_file -Destination $path_to_des
    }
    catch {
        Write-Host "Error moving file $path_to_file to $state : " -ForegroundColor Red
    }
}

function join_and_move_pass {
    param ([string]$log_dir, [string]$file_name, [string]$state)
    $path_to_file = Join-Path $log_dir $file_name
    $path_to_des = [System.IO.Path]::Combine($passFolder, $state, $file_name)
    try {
        Move-Item -Path $path_to_file -Destination $path_to_des
    }
    catch {
        Write-Host "Error moving file $path_to_file to $state : " -ForegroundColor Red
    }
}

$log_files = Get-ChildItem -Path $final_LOG_FOLDER -File

#================= Phan loai log pass ===================
$count_pass = 0
$count_wrong_version = 0
$total_duplicate = 0
foreach ($_ in $log_files) {
    switch -regex ($_) {
        "^PASS.*_DOWNLOAD_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $_ -state "DL"; $count_pass++; break }
        "^PASS.*_PT0_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $_ -state "PT0"; $count_pass++; break }
        "^PASS.*_PT1_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $_ -state "PT1"; $count_pass++; break }
        "^PASS.*_PT2_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $_ -state "PT2"; $count_pass++; break }
        "^PASS.*_PT3_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $_ -state "PT3"; $count_pass++; break }
        "^PASS.*_PT4_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $_ -state "PT4"; $count_pass++; break }
        "^PASS.*_PT_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $_ -state "PT"; $count_pass++; break }
        "^PASS.*_BURN_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $_ -state "BURN"; $count_pass++; break }
        "^PASS.*_FT1_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $_ -state "FT1"; $count_pass++; break }
        "^PASS.*_FT2_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $_ -state "FT2"; $count_pass++; break }
        "^PASS.*_FT3_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $_ -state "FT3"; $count_pass++; break }
        "^PASS.*_FT4_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $_ -state "FT4"; $count_pass++; break }
        "^PASS.*_FT5_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $_ -state "FT5"; $count_pass++; break }
        "^PASS.*_FT6_" { join_and_move_pass -log_dir $final_LOG_FOLDER -file_name $_ -state "FT6"; $count_pass++; break }
    }
}

#================= Phan loai log fail ===================
$count_fail = 0
foreach ($_ in $log_files) {
    switch -regex ($_) {
        "^FAIL.*_DOWNLOAD_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $_ -state "DL"; $count_fail++; break }
        "^FAIL.*_PT0_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $_ -state "PT0"; $count_fail++; break }
        "^FAIL.*_PT1_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $_ -state "PT1"; $count_fail++; break }
        "^FAIL.*_PT2_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $_ -state "PT2"; $count_fail++; break }
        "^FAIL.*_PT3_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $_ -state "PT3"; $count_fail++; break }
        "^FAIL.*_PT4_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $_ -state "PT4"; $count_fail++; break }
        "^FAIL.*_PT_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $_ -state "PT"; $count_fail++; break }
        "^FAIL.*_BURN_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $_ -state "BURN"; $count_fail++; break }
        "^FAIL.*_FT1_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $_ -state "FT1"; $count_fail++; break }
        "^FAIL.*_FT2_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $_ -state "FT2"; $count_fail++; break }
        "^FAIL.*_FT3_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $_ -state "FT3"; $count_fail++; break }
        "^FAIL.*_FT4_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $_ -state "FT4"; $count_fail++; break }
        "^FAIL.*_FT5_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $_ -state "FT5"; $count_fail++; break }
        "^FAIL.*_FT6_" { join_and_move_fail -log_dir $final_LOG_FOLDER -file_name $_ -state "FT6"; $count_fail++; break }
    }
}

#================ Kiểm tra nếu folder rỗng thì xóa ===============
foreach ($tram in $cac_tram_test) {
    $folderPath_P = Join-Path $passFolder $tram
    $folderPath_F = Join-Path $failFolder $tram
    $items_P = Get-ChildItem -Path $folderPath_P -ErrorAction SilentlyContinue
    $items_F = Get-ChildItem -Path $folderPath_F -ErrorAction SilentlyContinue

    if (-not $items_P) { Remove-Item -Path $folderPath_P -Recurse -Force }
    if (-not $items_F) { Remove-Item -Path $folderPath_F -Recurse -Force }
}

# =================== Gom file 600I vào folder riêng ======================
$path_600I=""
foreach ($tram in $cac_tram_test) {
    $folderPath_P = Join-Path $passFolder $tram
    if (Test-Path $folderPath_P) {
        $files600I = Get-ChildItem -Path $folderPath_P -File -Filter "*_600I_*" -ErrorAction SilentlyContinue
        if ($files600I -and $files600I.Count -gt 0) {
            $newFolder = Join-Path $folderPath_P "600I_Files"
            $path_600I=$nameFolder
            New-Item -Path $newFolder -ItemType Directory -Force | Out-Null
            foreach ($f in $files600I) {
                try { Move-Item -Path $f.FullName -Destination $newFolder -Force }
                catch { Write-Host "Error moving file $($f.FullName) to $newFolder" -ForegroundColor Red }
            }
            Write-Host "Moved $($files600I.Count) file 600I  $tram to 600I_Files folder " -ForegroundColor Green
        }
    }
}

# =================== Gom file khác loại (.log/.txt) vào folder riêng ======================
foreach ($tram in $cac_tram_test) {
    $folderPath_P = Join-Path $passFolder $tram
    if (Test-Path $folderPath_P) {
        $otherFiles = Get-ChildItem -Path $folderPath_P -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -notin @(".log", ".txt") }
        if ($otherFiles -and $otherFiles.Count -gt 0) {
            $newFolder = Join-Path $folderPath_P "Other_Files"
            New-Item -Path $newFolder -ItemType Directory -Force | Out-Null
            foreach ($f in $otherFiles) {
                try { Move-Item -Path $f.FullName -Destination $newFolder -Force }
                catch { Write-Host "Error moving file $($f.FullName) to $newFolder" -ForegroundColor Red }
            }
            Write-Host "Move $($otherFiles.Count) file(png,wav) $tram folder Other_Files" -ForegroundColor Green
        }
    }
}

Write-Host "`n"
Write-Host "============ Loc FTU-FCD ============="
Start-Sleep -Seconds 1
Write-Host "`n"

#================= Folder chứa file sai version ===================
$wrongVersionFolder = Join-Path $parent_of_log "WRONG_VERSION"
New-Item -Path $wrongVersionFolder -ItemType Directory -Force | Out-Null

#================= Kiểm tra FTU/FCD trong PASS ===================
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
                    # Tang bien dem file sai version
                    $count_wrong_version++
                }
                catch {
                    Write-Host "Error moving file $($f.FullName)" -ForegroundColor Red
                }
            }
        }
    }
}

Write-Host "`n"
Write-Host "============ Loc trung mac ============="
Start-Sleep -Seconds 1
Write-Host "`n"

#================= Folder chứa file trùng MAC ===================
$duplicateMacFolder = Join-Path $parent_of_log "DUPLICATE_MAC"
New-Item -Path $duplicateMacFolder -ItemType Directory -Force | Out-Null

function remove_duplicate_mac {
    param ([string]$tramFolder)
    if (-not (Test-Path $tramFolder)) { return }

    $logFiles = Get-ChildItem -Path $tramFolder -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in @(".log", ".txt") }

    $groups = $logFiles | Group-Object {
        if ($_.Name -match "(_[^_]+_)") { $matches[1] }
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
                    Write-Host "Moved duplicate MAC file $($dup.Name) (tram $tramFolder)" -ForegroundColor Yellow
                    # Tang bien dem file bi trung MAC (dung script: scope de cap nhat tu trong ham)
                    $script:total_duplicate++
                }
                catch {
                    Write-Host "Error moving duplicate file $($dup.FullName)" -ForegroundColor Red
                }
            }
        }
    }
}

#================= Áp dụng cho tất cả trạm PASS ===================
foreach ($tram in $cac_tram_test) {
    if ([string]::IsNullOrWhiteSpace($cac_tram_test)) {
        Write-Warning "Folder is null or empty, skipping..."
    }
    else {
        $folderPath_P = Join-Path $passFolder $tram
        remove_duplicate_mac -tramFolder $folderPath_P
    }



}
#================= 600I remove dup mac===================
    
if ([string]::IsNullOrWhiteSpace($path_600I)) {
    Write-Warning "Folder is null or empty, skipping..."
    
}
else {
    remove_duplicate_mac -tramFolder $path_600I
}


Write-Host "`n`n"
Write-Host "============ Tong hop so lieu ============="
Start-Sleep -Seconds 1

foreach ($tram in $cac_tram_test) {
    $folderPath_P = Join-Path $passFolder $tram
    if (Test-Path $folderPath_P) {
        $logFiles = Get-ChildItem -Path $folderPath_P -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @(".log", ".txt") }
        $countLogs = @($logFiles).Count
        Write-Host "Tram $tram : $countLogs file log/txt" -ForegroundColor Cyan
    }
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

[System.Console]::Out.Flush()
Start-Sleep -Milliseconds 300