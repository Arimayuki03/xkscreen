@echo off
cd /d D:\Code\Xingcan-Xiaolan-Drive
sc stop SystemTemperatureMonitoring
timeout /t 3 /nobreak > nul
where python > .tools\svc_env.txt 2>&1
python -c "import frida; print(frida.__version__)" >> .tools\svc_env.txt 2>&1
python .tools\frida_spawn_svc.py > .tools\svc_init.txt 2>&1
