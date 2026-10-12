@echo off
chcp 65001 > nul
echo === 创建屏幕驱动计划任务（登录自启、最高权限） ===
schtasks /Create /TN "XKScreenDriver" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File D:\Code\Xingcan-Xiaolan-Drive\.tools\xkw_driver_loop.ps1" /SC ONLOGON /RL HIGHEST /F
echo.
echo === 立即启动任务 ===
schtasks /Run /TN "XKScreenDriver"
echo.
echo === 任务状态 ===
schtasks /Query /TN "XKScreenDriver" /FO LIST | findstr /i "任务名 Status 状态"
