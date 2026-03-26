@echo off
echo ========================================
echo Testing WiFi Connection Setup
echo ========================================
echo.

echo Step 1: Checking your IP address...
echo.
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4 Address" ^| findstr "192.168"') do (
    echo Your WiFi IP:%%a
)
echo.

echo Step 2: Checking if backend is running...
echo.
curl -s http://localhost:3000/health >nul 2>&1
if %errorLevel% equ 0 (
    echo ✅ Backend is running on localhost:3000
) else (
    echo ❌ Backend is NOT running
    echo    Please run START_BACKEND.bat first
    echo.
    pause
    exit /b 1
)
echo.

echo Step 3: Testing backend response...
echo.
curl http://localhost:3000/health
echo.
echo.

echo Step 4: Checking firewall...
echo.
netsh advfirewall firewall show rule name="SenyaMatika Backend" >nul 2>&1
if %errorLevel% equ 0 (
    echo ✅ Firewall rule exists
) else (
    echo ⚠️  Firewall rule not found
    echo    Run SETUP_FIREWALL.bat as administrator
)
echo.

echo Step 5: Checking if port 3000 is listening...
echo.
netstat -an | findstr ":3000" | findstr "LISTENING" >nul 2>&1
if %errorLevel% equ 0 (
    echo ✅ Port 3000 is listening
    netstat -an | findstr ":3000" | findstr "LISTENING"
) else (
    echo ❌ Port 3000 is not listening
)
echo.

echo ========================================
echo Test Complete!
echo ========================================
echo.
echo Next steps:
echo 1. Make sure your phone is on the same WiFi
echo 2. Open phone browser and test: https://senyamtikaback-production.up.railway.app/health
echo 3. If browser test works, install and run the APK
echo.
echo If phone can't connect:
echo - Run SETUP_FIREWALL.bat as administrator
echo - Temporarily disable Windows Firewall
echo - Check if IP address changed (run GET_MY_IP.bat)
echo.
pause
