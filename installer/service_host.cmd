@echo off
rem Hosts the XkScreen driver for the scheduled task. The task targets this
rem script (this machine's Task Scheduler refuses unsigned .exe targets), and
rem the service runs in the foreground so the task instance lives exactly as
rem long as the driver does.
"%~dp0XkScreen.Service.exe" >nul 2>&1
