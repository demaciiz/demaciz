@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Kazz1VPN
color 0A

set "BASE=%~dp0"
set "SUB=%BASE%subscription.txt"
set "XRAY=%BASE%xray.exe"
set "WORK=%BASE%work"
set "LIST=%WORK%\servers.txt"
set "CONFIG=%WORK%\config.json"

if not exist "%SUB%" (
    echo [ERROR] subscription.txt was not found.
    pause
    exit /b 1
)

if not exist "%XRAY%" (
    echo [ERROR] xray.exe was not found.
    echo Put xray.exe next to this BAT file.
    pause
    exit /b 1
)

if not exist "%WORK%" mkdir "%WORK%"

cls
echo ==========================================
echo              Kazz1VPN
echo ==========================================
echo.
echo Reading subscription...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
 "$s=Get-Content -Raw -LiteralPath '%SUB%';" ^
 "$s=$s.Trim();" ^
 "try {$bytes=[Convert]::FromBase64String($s); $s=[Text.Encoding]::UTF8.GetString($bytes)} catch {};" ^
 "$s -split '\r?\n' | ForEach-Object {$_.Trim()} | Where-Object {$_ -like 'vless://*'} | Set-Content -Encoding UTF8 -LiteralPath '%LIST%'"

if not exist "%LIST%" (
    echo [ERROR] No VLESS servers found.
    pause
    exit /b 1
)

for /f %%N in ('powershell.exe -NoProfile -Command "(Get-Content -LiteralPath ''%LIST%'').Count"') do set "COUNT=%%N"

echo Found servers: !COUNT!
echo.
echo Testing servers...
echo.

set "BEST="
set "BESTMS=999999"

for /f "usebackq delims=" %%L in ("%LIST%") do (
    set "URL=%%L"
    set "HOST="
    set "PORT="

    for /f "tokens=1,2" %%A in ('powershell.exe -NoProfile -Command ^
        "$u=[Uri]::new('!URL!'); Write-Output ($u.Host + ' ' + $u.Port)"') do (
        set "HOST=%%A"
        set "PORT=%%B"
    )

    if defined HOST if defined PORT (
        for /f %%T in ('powershell.exe -NoProfile -Command ^
            "$sw=[Diagnostics.Stopwatch]::StartNew(); try {$c=[Net.Sockets.TcpClient]::new(); $r=$c.BeginConnect('!HOST!',!PORT!,$null,$null); if($r.AsyncWaitHandle.WaitOne(2500) -and $c.Connected){$sw.Stop();$c.Close();$sw.ElapsedMilliseconds}else{-1}} catch {-1}"') do (
            set "MS=%%T"
        )

        if not "!MS!"=="-1" (
            echo [OK] !HOST!:!PORT! - !MS! ms

            if !MS! LSS !BESTMS! (
                set "BESTMS=!MS!"
                set "BEST=!URL!"
            )
        ) else (
            echo [FAIL] !HOST!:!PORT!
        )
    ) else (
        echo [SKIP] Invalid VLESS URL
    )
)

echo.
echo ==========================================

if not defined BEST (
    echo No reachable servers found.
    pause
    exit /b 1
)

echo Best server: !BESTMS! ms
echo ==========================================
echo.
echo Generating Xray configuration...

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
 "$u=[Uri]::new('!BEST!');" ^
 "$q=[System.Web.HttpUtility]::ParseQueryString($u.Query);" ^
 "$obj=@{log=@{loglevel='warning'};inbounds=@(@{listen='127.0.0.1';port=10808;protocol='socks';settings=@{auth='noauth';udp=$true}});outbounds=@(@{protocol='vless';settings=@{vnext=@(@{address=$u.Host;port=[int]$u.Port;users=@(@{id=$u.User;encryption='none';flow=$q['flow']})})};streamSettings=@{network=$q['type'];security=$q['security'];realitySettings=@{serverName=$q['sni'];fingerprint=$q['fp'];publicKey=$q['pbk'];shortId=$q['sid']}}})};" ^
 "$obj | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -LiteralPath '%CONFIG%'"

if not exist "%CONFIG%" (
    echo [ERROR] Failed to create Xray config.
    pause
    exit /b 1
)

echo.
echo Starting Xray...
echo.
echo SOCKS5 proxy: 127.0.0.1:10808
echo.

start "Kazz1VPN Xray" /min "%XRAY%" run -c "%CONFIG%"

timeout /t 2 /nobreak >nul

echo ==========================================
echo             Kazz1VPN RUNNING
echo ==========================================
echo.
echo Selected server latency: !BESTMS! ms
echo SOCKS5 proxy: 127.0.0.1:10808
echo.
echo Press any key to stop Kazz1VPN.
pause >nul

taskkill /IM xray.exe /F >nul 2>&1

echo.
echo Xray stopped.
pause
