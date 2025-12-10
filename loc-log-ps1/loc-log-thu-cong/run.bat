@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

:: ========================================
:: Script chay remove_dup_mac.ps1
:: ========================================

echo.
echo ╔═══════════════════════════════════════════════════════════╗
echo ║         REMOVE DUPLICATE MAC - LAUNCHER                   ║
echo ╔═══════════════════════════════════════════════════════════╗
echo.

:: Tim file PS1 trong cung thu muc voi file BAT
set "SCRIPT_DIR=%~dp0"
set "PS1_FILE=%SCRIPT_DIR%remove_dup_mac.ps1"

:: Kiem tra file PS1 co ton tai khong
if not exist "%PS1_FILE%" (
    echo [ERROR] Khong tim thay file: remove_dup_mac.ps1
    echo.
    echo Vui long dam bao file remove_dup_mac.ps1 nam cung thu muc voi file .bat nay
    echo Thu muc hien tai: %SCRIPT_DIR%
    echo.
    pause
    exit /b 1
)

echo [OK] Da tim thay file: remove_dup_mac.ps1
echo.

:: Yeu cau nguoi dung nhap duong dan
echo ┌───────────────────────────────────────────────────────────┐
echo │ Nhap duong dan thu muc can xu ly:                        │
echo │ (Keo tha folder vao day hoac copy/paste duong dan)       │
echo └───────────────────────────────────────────────────────────┘
echo.
set /p "TARGET_PATH=Thu muc: "

:: Xoa dau ngoac kep (neu co)
set "TARGET_PATH=%TARGET_PATH:"=%"

:: Kiem tra duong dan co ton tai khong
if not exist "%TARGET_PATH%" (
    echo.
    echo [ERROR] Thu muc khong ton tai: %TARGET_PATH%
    echo.
    pause
    exit /b 1
)

echo.
echo ┌───────────────────────────────────────────────────────────┐
echo │ Dang chay script...                                       │
echo └───────────────────────────────────────────────────────────┘
echo.

:: Chay PowerShell script
PowerShell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%PS1_FILE%' -TARGET_DIR '%TARGET_PATH%'"

:: Kiem tra ket qua
if %ERRORLEVEL% equ 0 (
    echo.
    echo ╔═══════════════════════════════════════════════════════════╗
    echo ║                HOAN THANH THANH CONG                      ║
    echo ╔═══════════════════════════════════════════════════════════╗
) else (
    echo.
    echo ╔═══════════════════════════════════════════════════════════╗
    echo ║                    CO LOI XAY RA                          ║
    echo ╔═══════════════════════════════════════════════════════════╗
)

echo.
pause