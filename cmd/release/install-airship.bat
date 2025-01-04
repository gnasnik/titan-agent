@echo off
setlocal EnableDelayedExpansion

REM Define the SUPPLIER ID
set AIRSHIP_SUPPLIER_ID=104650

REM Define the URL for the Airship installation script
set AIRSHIP_RUNNER_URL=https://infra-iaas-1312767721.cos.ap-shanghai.myqcloud.com/box-tools/install-on-systemd.sh
set VM_NAME=ubuntu-airship
set PATH=%PATH%;C:\Program Files\Multipass\bin;C:\Windows\System32;C:\Windows;C:\Windows\System32\WindowsPowerShell\v1.0

call :main %*
goto :EOF

:: Function to check if Multipass is installed
:check_multipass
where multipass >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Error: Multipass is not installed.
    exit /b 1
)
multipass --version
exit /b 0

:: Function to create the VM
:create_vm
call :check_multipass
for /f "tokens=*" %%a in ('powershell get-date -format "yyMMddHHmmssff"') do set datetime=%%a
set AIRSHIP_SUPPLIER_DEVICE_ID=TNT%datetime%

echo Creating the virtual machine %VM_NAME%
multipass launch --name %VM_NAME% --cpus 2 --memory 2G --disk 64G -vvvv
if %ERRORLEVEL% NEQ 0 (
    echo Error: Failed to create VM %VM_NAME%.
    exit /b 1
)

echo Fetching the installation script
multipass exec %VM_NAME% -- wget -q %AIRSHIP_RUNNER_URL% -O /tmp/install-on-systemd.sh

echo Setting execute permission on the script
multipass exec %VM_NAME% -- sudo chmod +x /tmp/install-on-systemd.sh

echo Running airship script inside the VM
multipass exec %VM_NAME% -- sudo DEVICE_CLASS=box DEVICE_SUPPLIER=%AIRSHIP_SUPPLIER_ID% DEVICE_SUPPLIER_DEVICE_ID=%AIRSHIP_SUPPLIER_DEVICE_ID% /tmp/install-on-systemd.sh install
if %ERRORLEVEL% NEQ 0 (
    echo Error: Failed to execute script inside the VM.
    exit /b 1
) 


rem Retry logic to check if the airship-box-agent.service is running and fetch BOX_ID
set retry_count=0
set max_retries=10
set BOX_ID=

echo Checking the status of airship-box-agent.service...
for /f "tokens=*" %%a in ('multipass exec "%VM_NAME%" -- sudo systemctl is-active airship-box-agent.service') do set service_status=%%a

if "%service_status%"=="active" (
    echo The airship-box-agent.service is running.
    goto :retry_read_boxid
) else (
    echo The airship-box-agent.service is not active.
    exit /b 1
)

:retry_read_boxid
if %retry_count% lss %max_retries% (
    for /f "tokens=*" %%b in ('multipass exec "%VM_NAME%" -- cat /opt/.airship/id') do set BOX_ID=%%b
    if defined BOX_ID (
        echo Successfully read BOX_ID: %BOX_ID%
        exit /b 0
    ) else (
        echo BOX_ID is not found. Retrying... (Attempt %retry_count%)
        set /a retry_count+=1
        timeout /t 3 > nul
        goto :retry_read_boxid
    )
) else (
    echo Maximum retry attempts reached. Failed to read BOX_ID.
    exit /b 1
)

exit /b 0

:info
for /f "tokens=*" %%i in ('multipass exec "%VM_NAME%" -- cat /opt/.airship/id') do set "BOX_ID=%%i"
if "!BOX_ID!"=="" (
    echo Error: BOX_ID is not found.
    exit /b 1
)
echo BOX_ID: !BOX_ID!
exit /b 0

:reinstall
multipass list | findstr "%VM_NAME%" >nul
if %ERRORLEVEL% equ 0 (
    echo Deleting existing %VM_NAME% VM...
    multipass delete "%VM_NAME%"
    multipass purge
)
echo Creating new VM...
call :create_vm
rem Return the result of create_vm
if %errorlevel% equ 0 (
    echo VM reinstallation successful.
    exit /b 0
) 
echo Error: VM reinstallation failed.
exit /b 1

:restart
echo Restarting service...
multipass restart "%VM_NAME%"
exit /b 0

:delete
echo Deleting service...
multipass delete "%VM_NAME%"
multipass purge
exit /b 0

:: Function to stop the VM
:stop
set VM_NAME=ubuntu-airship
echo Stopping service...
multipass stop "%VM_NAME%"
exit /b %errorlevel%

:: Function to get the status of the VM
:status
set VM_NAME=ubuntu-airship
for /f "tokens=1,2" %%a in ('multipass list ^| findstr /i "%VM_NAME%"') do (
    set "vm_name=%%a"
    set "vm_status=%%b"
)

if not defined vm_status (
    echo STATUS: none
) else (
    if "%vm_status%"=="Running" (
        echo STATUS: running
    ) else if "%vm_status%"=="Stopped" (
        echo STATUS: stopped
    ) else (
        echo STATUS: unknown
    )
)
exit /b 0

:main
if "%1"=="" goto usage
if "%1"=="install" (
    call :create_vm
) else if "%1"=="info" (
    call :info
) else if "%1"=="reinstall" (
    call :reinstall
) else if "%1"=="restart" (
    call :restart
) else if "%1"=="delete" (
    call :delete
) else if "%1"=="status" (
    call :status    
) else if "%1"=="stop" (
    call :stop    
)  else (
    goto usage
)
exit /b 0

:usage
echo Usage: %0 {install^|reinstall^|restart^|delete^|info}
exit /b 1