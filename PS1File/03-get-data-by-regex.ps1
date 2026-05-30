param (
    [string]$prefixRegex,
    [string]$valueRegex,
    [string]$LogFolderPath,
    [string]$SaveLocation
)

$joinRegex = $prefixRegex + $valueRegex
$OutputCsv = Join-Path $SaveLocation ("data-{0}.csv" -f (Get-Date -Format "HH-mm"))


if (Test-Path $OutputCsv) { Remove-Item $OutputCsv -Force }

function Is-EmptyObject($obj) {
    if ($null -eq $obj) { return $true }
    if ($obj -is [pscustomobject] -and $obj.psobject.Properties.Count -eq 0) { return $true }
    if ($obj -is [array] -and $obj.Count -eq 0) { return $true }
    if ($obj -is [string] -and $obj.Trim() -eq '') { return $true }
    return $false
}

function Get-FanSpeedArray {
    param([string]$LogPath)

    $list_fan = @()
    $list_field = @()

    if (Test-Path $LogPath) {
        $content = Get-Content $LogPath -Raw
        $matches = [regex]::Matches($content, $joinRegex)

        foreach ($m in $matches) {
            $field = $m.Groups[1].Value
            $fan   = $m.Groups[2].Value

            if (-not (Is-EmptyObject $field)) { $list_field += $field }
            if (-not (Is-EmptyObject $fan))   { $list_fan   += $fan }
        }

        return [PSCustomObject]@{
            FirstArray  = $list_field
            SecondArray = $list_fan
        }
    }
    return $null
}

function Get-AllTextLogFiles {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FolderPath
    )

    if (-not (Test-Path $FolderPath -PathType Container)) {
        Write-Error "Folder $FolderPath doesnt esxit!"
        return @()
    }

    Get-ChildItem -Path $FolderPath -Recurse -File |
        Where-Object { $_.Extension -match '\.(txt|log)$' } |
        Select-Object -ExpandProperty FullName
}

$ValidHeader = $false
$list_file_log = Get-AllTextLogFiles $LogFolderPath

foreach ($file in $list_file_log) {
    $x = Get-FanSpeedArray -LogPath $file

    if ($x -and $x.SecondArray.Count -gt 0) {

        if (-not $ValidHeader) {
            ("file_name," + ($x.FirstArray -join ",")) |
                Set-Content -Path $OutputCsv -Encoding UTF8
            $ValidHeader = $true
        }

        ((Split-Path $file -Leaf) + "," + ($x.SecondArray -join ",")) |
            Add-Content -Path $OutputCsv -Encoding UTF8

        Write-Host "$(Split-Path $file -Leaf) --- OK" -ForegroundColor Green
    }
}

Write-Host "`n`n`n`n" -ForegroundColor Magenta
Write-Host "        XONG ROI NHANH VAI LON " -ForegroundColor Magenta
Write-Host "`n`n`n`n" -ForegroundColor Magenta
