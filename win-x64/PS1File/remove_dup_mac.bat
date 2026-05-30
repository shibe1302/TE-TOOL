@echo off
setlocal

set SCRIPT_DIR=%~dp0

set PS1_FILE=%SCRIPT_DIR%remove_dup_mac.ps1

echo Nhap duong dan thu muc can xu ly:
echo (Keo tha folder vao day hoac copy/paste duong dan)
set /p "TARGET_PATH=Thu muc: "

:: Xoa dau ngoac kep (neu co)
set "TARGET_PATH=%TARGET_PATH:"=%"
PowerShell -NoProfile -ExecutionPolicy Bypass -Command "& '%PS1_FILE%' -TARGET_DIR '%TARGET_PATH%'"

pause
