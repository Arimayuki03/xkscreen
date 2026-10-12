@echo off
"C:\Program Files\USBPcap\USBPcapCMD.exe" -d \\.\USBPcap1 -o "D:\Code\Xingcan-Xiaolan-Drive\.tools\cap_test.pcap" --snaplen 256 -A
echo EXITCODE=%ERRORLEVEL% > "D:\Code\Xingcan-Xiaolan-Drive\.tools\cap_err.txt"
