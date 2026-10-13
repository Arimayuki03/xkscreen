# Kill duplicate XkScreen.Service instances running in an interactive session
# (the boot-time scheduled task owns the SYSTEM/session-0 instance that holds
# the HTTP port; extra user-session copies would double up the screen frames).
$out = 'D:\Code\Xingcan-Xiaolan-Drive\.tools\kill_dup_result.txt'
"kill-duplicate run $(Get-Date -Format 'HH:mm:ss')" | Out-File -Encoding ascii $out
Get-Process 'XkScreen.Service' -ErrorAction SilentlyContinue |
    Where-Object { $_.SessionId -ne 0 } |
    ForEach-Object {
        Stop-Process -Id $_.Id -Force
        "killed pid $($_.Id) (session $($_.SessionId))" | Out-File -Append -Encoding ascii $out
    }
Get-Process 'XkScreen.Service' -ErrorAction SilentlyContinue |
    ForEach-Object { "still running pid $($_.Id) (session $($_.SessionId))" | Out-File -Append -Encoding ascii $out }
done
