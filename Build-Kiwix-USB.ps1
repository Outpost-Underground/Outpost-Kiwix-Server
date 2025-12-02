<# 
  Build-Kiwix-USB.ps1
  --------------------
  This script:

    - Detects USB-attached drives (thumbdrives AND USB hard drives)
    - Lets the user pick one BY DRIVE LETTER (e.g. D)
    - Downloads official Kiwix tools for Windows
      from https://download.kiwix.org
    - Creates an Outpost-Kiwix-Server folder on that drive
    - Sets up:

        \Outpost-Kiwix-Server\
          kiwix-tools-win\
          ZIMs\
          OUTPOST-KIWIX-MENU.bat
          README-OUTPOST.txt

  It does NOT format or erase the USB drive. It only creates / updates
  the Outpost-Kiwix-Server folder.

  The batch menu on the USB lets a non-technical user:

    - Open ZIMs folder
    - (Optionally) download a curated “prepper pack” of ZIMs
    - Rebuild the Kiwix library
    - Start/stop the server (port 8090)
    - See an auto-detected LAN URL based on Get-NetIPAddress
#>

$ErrorActionPreference = 'Stop'

Write-Host "=============================================="
Write-Host "  Outpost Kiwix USB Builder (Windows)"
Write-Host "=============================================="
Write-Host ""

# 1. Detect USB drives (thumb drives AND USB HDDs)
#    - Any volume whose underlying disk BusType is USB
#    - Plus classic Removable volumes
$volCandidates = @{}

# Classic removable volumes
Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Removable' } | ForEach-Object {
    $volCandidates[$_.DriveLetter] = $_
}

# Volumes on USB bus-type disks
$usbDisks = Get-Disk | Where-Object { $_.BusType -eq 'USB' -and $_.OperationalStatus -eq 'Online' }
foreach ($disk in $usbDisks) {
    Get-Partition -DiskNumber $disk.Number | Where-Object DriveLetter | ForEach-Object {
        $v = Get-Volume -DriveLetter $_.DriveLetter
        if ($v) { $volCandidates[$v.DriveLetter] = $v }
    }
}

$removable = $volCandidates.GetEnumerator() | ForEach-Object { $_.Value } | Sort-Object DriveLetter

if (-not $removable) {
    Write-Host "No USB drives with a drive letter detected."
    Write-Host "Plug in a USB thumbdrive or USB hard drive and run this script again." -ForegroundColor Yellow
    exit 1
}

Write-Host "Detected USB drives:" -ForegroundColor Cyan
foreach ($vol in $removable) {
    $letter = $vol.DriveLetter
    $label  = $vol.FileSystemLabel
    $sizeGB = "{0:N1}" -f ($vol.Size/1GB)
    $freeGB = "{0:N1}" -f ($vol.SizeRemaining/1GB)
    if (-not $label) { $label = "(no label)" }
    Write-Host ("  {0}:  Label: {1}  Size: {2} GB  Free: {3} GB" -f $letter, $label, $sizeGB, $freeGB)
}
Write-Host ""

# 2. Let user choose by DRIVE LETTER
$targetVolume = $null

while (-not $targetVolume) {
    $inputLetter = Read-Host "Type the DRIVE LETTER of the USB you want to use (for example: D)"
    if ([string]::IsNullOrWhiteSpace($inputLetter)) {
        Write-Host "Please type a drive letter like D and press ENTER." -ForegroundColor Yellow
        continue
    }

    # Normalize: strip colon and whitespace, uppercase single-letter string
    $letter = ($inputLetter.Trim().TrimEnd(':')).ToUpper()

    $candidate = $removable | Where-Object { "$($_.DriveLetter)" -eq $letter }

    if (-not $candidate) {
        Write-Host ("No USB drive found with letter '{0}:'." -f $letter) -ForegroundColor Red
        Write-Host "Please pick one of the listed letters above." -ForegroundColor Yellow
        continue
    }

    $targetVolume = $candidate
}

$driveLetter = $targetVolume.DriveLetter
$driveRoot   = ("{0}:\\" -f $driveLetter)

Write-Host ""
Write-Host ("You selected drive {0}:  ({1})" -f $driveLetter, $targetVolume.FileSystemLabel) -ForegroundColor Green
Write-Host "A folder 'Outpost-Kiwix-Server' will be created on this drive."
Write-Host "Existing files on the drive will NOT be erased."
Write-Host ""
$confirm = Read-Host "Type YES to continue, or anything else to cancel"
if ($confirm -ne "YES") {
    Write-Host "Cancelled by user."
    exit 0
}

# 3. Prepare target paths
$targetRoot  = Join-Path $driveRoot "Outpost-Kiwix-Server"
$kiwixDir    = Join-Path $targetRoot "kiwix-tools-win"
$zimDir      = Join-Path $targetRoot "ZIMs"
$readmePath  = Join-Path $targetRoot "README-OUTPOST.txt"
$menuBatPath = Join-Path $targetRoot "OUTPOST-KIWIX-MENU.bat"

Write-Host ""
Write-Host "Creating folder structure on $driveLetter`: ..." -ForegroundColor Cyan
New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
New-Item -ItemType Directory -Path $kiwixDir   -Force | Out-Null
New-Item -ItemType Directory -Path $zimDir     -Force | Out-Null

# 4. Download Kiwix tools
$kiwixUrl    = "https://download.kiwix.org/release/kiwix-tools/kiwix-tools_win-i686.zip"
$tempZip     = Join-Path $env:TEMP "kiwix-tools_win-i686.zip"
$tempExtract = Join-Path $env:TEMP ("kiwix-tools-extract-" + [guid]::NewGuid().ToString())

Write-Host ""
Write-Host "Downloading Kiwix tools from:" -ForegroundColor Cyan
Write-Host "  $kiwixUrl" -ForegroundColor Yellow

Invoke-WebRequest -Uri $kiwixUrl -OutFile $tempZip

Write-Host "Download complete. Extracting..." -ForegroundColor Cyan
New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null
Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

Write-Host "Copying Kiwix tools onto the USB drive..." -ForegroundColor Cyan

# The zip extracts into a subfolder; move the CONTENTS into kiwix-tools-win
$innerDir = Get-ChildItem $tempExtract | Where-Object { $_.PSIsContainer } | Select-Object -First 1
if ($innerDir) {
    Get-ChildItem $innerDir.FullName | ForEach-Object {
        Move-Item -Path $_.FullName -Destination $kiwixDir -Force
    }
} else {
    Get-ChildItem $tempExtract | ForEach-Object {
        Move-Item -Path $_.FullName -Destination $kiwixDir -Force
    }
}

Remove-Item $tempZip -Force
Remove-Item $tempExtract -Recurse -Force

# 5. Create README-OUTPOST.txt
$readmeContent = @'
OUTPOST OFFLINE LIBRARY (USB EDITION)
====================================

This USB stick contains the files needed to run a local offline
library server using Kiwix.

On this USB you will find:

  Outpost-Kiwix-Server\
    kiwix-tools-win\
    ZIMs\
    OUTPOST-KIWIX-MENU.bat
    README-OUTPOST.txt

HOW TO USE
----------

1. Plug this USB stick into a Windows computer.
2. Open the "Outpost-Kiwix-Server" folder.
3. Double-click "OUTPOST-KIWIX-MENU.bat".
4. In the menu, you can:

   - [1] "Start server".
   - [2] "Stop server".
   - [3] "Rebuild library from ZIMs".
   - [4] "Open ZIMs folder" and copy your .zim files into that folder.
   - [6] "Download prepper ZIM pack" (if online).

5. The script will show you how to connect:

   - From THIS computer (the server):
       http://localhost:8090

   - From OTHER devices on the same network:
       The menu will try to auto-detect your IPv4 address and
       show a direct link (for example http://192.168.1.100:8090).

IMPORTANT
---------

- PDF viewing can be tricky depending on the browser being used.
  If clicking on a PDF inside a ZIM file results in error then
  try either a different browser such as Duck Duck Go or Firefox,
  or right click the PDF and open in a new tab/window. 

- The Kiwix server set up by this USB does NOT use a username/password
  by default. If your browser asks you for a username and password
  when you open the address above, it is almost certainly coming from
  your network's proxy or filter, not from Kiwix itself.

STOPPING THE SERVER
-------------------

Return to the menu and choose [2] "Stop server", or close the
"Kiwix Server" process.

NOTES
-----

- This USB is NOT locked to a specific computer; you can plug it into
  any Windows machine and run the menu.
- Your ZIM files may be large; ensure the USB has enough free space.
- The optional "prepper pack" downloads a curated set of ZIM files
  (Ready.gov, food prep, knots, medicine, post-disaster, water,
  urban prepper, low-tech magazine, military medicine, etc.)
  that fits easily on a 128 GB drive.

Stay curious and stay prepared.
Outpost Underground
'@

Set-Content -Path $readmePath -Value $readmeContent -Encoding ASCII

# 6. Create OUTPOST-KIWIX-MENU.bat (with improved IP auto-detect via PowerShell)
$menuBat = @'
@echo off
setlocal
title Outpost Offline Library Server (Kiwix USB)
cd /d "%~dp0"

if not exist "ZIMs" mkdir "ZIMs"

:MAIN_MENU
cls
echo =======================================================
echo            OUTPOST OFFLINE LIBRARY SERVER
echo =======================================================
echo  This turns this Windows PC into a local Kiwix server.
echo.
echo  ZIM files go in: %cd%\ZIMs
echo.
echo  MENU:
echo     [1] Start server
echo     [2] Stop server
echo     [3] Rebuild library from ZIMs
echo     [4] Open ZIMs folder
echo     [5] Show connection instructions
echo     [6] Download curated "prepper" ZIM pack (needs internet)
echo     [0] Exit
echo.
set "choice="
set /p "choice=Choose an option and press ENTER: "

if "%choice%"=="1" goto START_SERVER
if "%choice%"=="2" goto STOP_SERVER
if "%choice%"=="3" goto REBUILD_LIBRARY
if "%choice%"=="4" goto OPEN_ZIMS
if "%choice%"=="5" goto SHOW_INFO
if "%choice%"=="6" goto DOWNLOAD_CURATED
if "%choice%"=="0" goto END

echo.
echo Invalid choice. Press any key to return to menu...
pause >nul
goto MAIN_MENU


:REBUILD_LIBRARY
cls
echo =======================================================
echo      Rebuilding Kiwix library from ZIM files
echo =======================================================
echo.
echo Library file: %cd%\library.xml
echo ZIM folder : %cd%\ZIMs
echo.

if not exist "kiwix-tools-win\kiwix-serve.exe" (
    echo ERROR: kiwix-serve.exe not found in kiwix-tools-win.
    echo Make sure the USB was built correctly.
    echo.
    pause
    goto MAIN_MENU
)
if not exist "kiwix-tools-win\kiwix-manage.exe" (
    echo ERROR: kiwix-manage.exe not found in kiwix-tools-win.
    echo Make sure the USB was built correctly.
    echo.
    pause
    goto MAIN_MENU
)

rem Create/reset library.xml
"kiwix-tools-win\kiwix-manage.exe" library.xml new >nul 2>&1

rem Check if there are any ZIMs at all
dir /b "ZIMs\*.zim" >nul 2>&1
if errorlevel 1 (
    echo No .zim files found in the ZIMs folder.
    echo You can still start the server, but there will be no content yet.
    echo.
    pause
    goto MAIN_MENU
)

echo Adding ZIM files to the library...
for %%F in ("ZIMs\*.zim") do (
    echo   %%~nxF
    "kiwix-tools-win\kiwix-manage.exe" library.xml add "%%~fF" >nul 2>&1
)

echo.
echo Done rebuilding the library.
echo.
pause
goto MAIN_MENU


:START_SERVER
cls
echo =======================================================
echo                Starting Kiwix Server
echo =======================================================
echo.

if not exist "kiwix-tools-win\kiwix-serve.exe" (
    echo ERROR: kiwix-serve.exe not found in kiwix-tools-win.
    echo Make sure the USB was built correctly.
    echo.
    pause
    goto MAIN_MENU
)
if not exist "kiwix-tools-win\kiwix-manage.exe" (
    echo ERROR: kiwix-manage.exe not found in kiwix-tools-win.
    echo Make sure the USB was built correctly.
    echo.
    pause
    goto MAIN_MENU
)

if not exist "library.xml" (
    echo No library.xml found. Creating a new library...
    "kiwix-tools-win\kiwix-manage.exe" library.xml new >nul 2>&1

    dir /b "ZIMs\*.zim" >nul 2>&1
    if errorlevel 1 (
        echo No ZIM files found yet. You can add them later and rebuild the library.
    ) else (
        echo Adding all ZIMs in ZIMs\ to the library...
        for %%F in ("ZIMs\*.zim") do (
            echo   %%~nxF
            "kiwix-tools-win\kiwix-manage.exe" library.xml add "%%~fF" >nul 2>&1
        )
    )
)

echo.
echo Starting kiwix-serve on port 8090 in the background...
echo.

rem Start kiwix-serve in the SAME window, in the background (no extra window)
rem Log kiwix output to kiwix-server.log instead of showing it to the user
start "" /b "kiwix-tools-win\kiwix-serve.exe" --library --address=0.0.0.0 --port=8090 --monitorLibrary library.xml >kiwix-server.log 2>&1

rem Use PowerShell to detect a sensible IPv4 address
rem Prefer 192.168.x.x; if none, fall back to any non-loopback/non-APIPA IPv4
set "IP="
for /f "usebackq tokens=* delims=" %%I in (`
  powershell -NoProfile -Command "try { `$ip = Get-NetIPAddress -AddressFamily IPv4 ^| Where-Object { `$_.IPAddress -like '192.168.*' -and `$_.IPAddress -ne '127.0.0.1' -and `$_.IPAddress -notlike '169.254.*' -and `$_.InterfaceAlias -notmatch 'vEthernet^|VirtualBox^|Loopback' } ^| Sort-Object InterfaceMetric ^| Select-Object -First 1 -ExpandProperty IPAddress; if (-not `$ip) { `$ip = Get-NetIPAddress -AddressFamily IPv4 ^| Where-Object { `$_.IPAddress -ne '127.0.0.1' -and `$_.IPAddress -notlike '169.254.*' -and `$_.InterfaceAlias -notmatch 'vEthernet^|VirtualBox^|Loopback' } ^| Sort-Object InterfaceMetric ^| Select-Object -First 1 -ExpandProperty IPAddress; } if (`$ip) { Write-Output `$ip } } catch {}"
`) do set "IP=%%I"

echo =======================================================
echo   Kiwix Server started (command sent to kiwix-serve).
echo.
echo   From THIS computer, open:
echo       http://localhost:8090
echo.

if defined IP (
    echo   From OTHER devices on the same Wi-Fi or network:
    echo       http://%IP%:8090
) else (
    echo   The script could not auto-detect an IPv4 address.
    echo   On THIS computer, open a Command Prompt and type:  ipconfig
    echo   Look for something similar to: 192.168.1.100
    echo   Then look for your IPv4 Address and use:
    echo       http://YOUR-IPv4-ADDRESS:8090
    echo   Live long, and prosper
)

echo.
echo   NOTE: This server does NOT use a username/password.
echo   If your browser asks you to log in, that prompt
echo   is coming from your network (proxy/filter), not Kiwix.
echo =======================================================
echo.
pause
goto MAIN_MENU


:STOP_SERVER
cls
echo Stopping Kiwix server (if running)...
taskkill /IM kiwix-serve.exe /F >nul 2>&1
echo.
echo Kiwix server stopped (if it was running).
echo.
pause
goto MAIN_MENU


:OPEN_ZIMS
cls
echo Opening the ZIMs folder in Explorer...
echo.
start "" "ZIMs"
echo Add or remove .zim files there, then use:
echo   [3] Rebuild library
echo in the main menu.
echo.
pause
goto MAIN_MENU


:SHOW_INFO
cls
echo =======================================================
echo        How to connect to this Kiwix server
echo =======================================================
echo.

set "IP="
for /f "usebackq tokens=* delims=" %%I in (`
  powershell -NoProfile -Command "try { `$ip = Get-NetIPAddress -AddressFamily IPv4 ^| Where-Object { `$_.IPAddress -like '192.168.*' -and `$_.IPAddress -ne '127.0.0.1' -and `$_.IPAddress -notlike '169.254.*' -and `$_.InterfaceAlias -notmatch 'vEthernet^|VirtualBox^|Loopback' } ^| Sort-Object InterfaceMetric ^| Select-Object -First 1 -ExpandProperty IPAddress; if (-not `$ip) { `$ip = Get-NetIPAddress -AddressFamily IPv4 ^| Where-Object { `$_.IPAddress -ne '127.0.0.1' -and `$_.IPAddress -notlike '169.254.*' -and `$_.InterfaceAlias -notmatch 'vEthernet^|VirtualBox^|Loopback' } ^| Sort-Object InterfaceMetric ^| Select-Object -First 1 -ExpandProperty IPAddress; } if (`$ip) { Write-Output `$ip } } catch {}"
`) do set "IP=%%I"

echo From THIS computer (the server):
echo   Open:  http://localhost:8090
echo.

if defined IP (
    echo From OTHER devices on the same Wi-Fi or LAN:
    echo   Open:  http://%IP%:8090
) else (
    echo The script could not auto-detect an IPv4 address.
    echo On THIS computer, open a Command Prompt and type:  ipconfig
    echo Then look for your IPv4 Address and use:
    echo   http://YOUR-IPv4-ADDRESS:8090
)

echo.
echo IMPORTANT:
echo   - Kiwix itself does NOT ask for a username/password.
echo   - If you see a login prompt, it is almost certainly
echo     from your network proxy or content filter.
echo.
echo Make sure:
echo   - This PC and the other devices are on the same network.
echo   - Any firewall allows access to port 8090.
echo.
pause
goto MAIN_MENU


:DOWNLOAD_CURATED
cls
echo =======================================================
echo     Download curated "prepper" ZIM pack to ZIMs\
echo =======================================================
echo.
echo This will download several offline sites including:
echo   - cd3wd project (self-reliance, development)
echo   - Cooking / food prep (FOSS cooking)
echo   - Ready.gov (disaster preparedness)
echo   - WikiHow
echo   - Medicine / NHS medicines
echo   - Post-disaster resources
echo   - Water treatment
echo   - Urban Prepper
echo   - Low-tech Magazine (solar)
echo   - iFixit (repairs)
echo   - Ham radio, outdoors, gardening, DIY, mechanics, woodworking
echo.
echo Total size is on the order of ~61 GB.
echo You MUST be online for this to work.
echo.
set "ans="
set /p "ans=Type YES to start the downloads, or anything else to cancel: "
if /I not "%ans%"=="YES" (
    echo.
    echo Cancelled.
    echo.
    pause
    goto MAIN_MENU
)

if not exist "ZIMs" mkdir "ZIMs"

echo.
echo Starting downloads. This can take a long time depending
echo on your connection speed. Each file will be fetched
echo with PowerShell and saved into the ZIMs folder.
echo.

rem Helper: if PowerShell is missing, fail nicely
where powershell >nul 2>&1
if errorlevel 1 (
    echo ERROR: PowerShell not found on this system.
    echo Cannot download the curated ZIM pack automatically.
    echo.
    pause
    goto MAIN_MENU
)

call :DL_ZIM "https://download.kiwix.org/zim/zimit/cd3wdproject.org_en_all_2025-11.zim"                            "cd3wdproject.org_en_all_2025-11.zim"
call :DL_ZIM "https://download.kiwix.org/zim/zimit/foss.cooking_en_all_2025-11.zim"                               "foss.cooking_en_all_2025-11.zim"
call :DL_ZIM "https://download.kiwix.org/zim/www.ready.gov_en.zim"                                                "www.ready.gov_en.zim"
call :DL_ZIM "https://download.kiwix.org/zim/zimgit-food-preparation_en.zim"                                      "zimgit-food-preparation_en.zim"
call :DL_ZIM "https://download.kiwix.org/zim/zimgit-knots_en.zim"                                                 "zimgit-knots_en.zim"
call :DL_ZIM "https://download.kiwix.org/zim/zimgit-medicine_en.zim"                                              "zimgit-medicine_en.zim"
call :DL_ZIM "https://download.kiwix.org/zim/zimgit-post-disaster_en.zim"                                         "zimgit-post-disaster_en.zim"
call :DL_ZIM "https://download.kiwix.org/zim/zimgit-water_en.zim"                                                 "zimgit-water_en.zim"
call :DL_ZIM "https://download.kiwix.org/zim/urban-prepper_en_all.zim"                                            "urban-prepper_en_all.zim"
call :DL_ZIM "https://download.kiwix.org/zim/zimit/solar.lowtechmagazine.com_mul_all_2025-01.zim"                 "solar.lowtechmagazine.com_mul_all_2025-01.zim"
call :DL_ZIM "https://download.kiwix.org/zim/fas-military-medicine_en.zim"                                        "fas-military-medicine_en.zim"
call :DL_ZIM "https://download.kiwix.org/archive/zim/wikihow/wikihow_en_maxi_2023-03.zim"                        "wikihow_en_maxi_2023-03.zim"
call :DL_ZIM "https://download.kiwix.org/zim/ifixit/ifixit_en_all_2025-06.zim"                                    "ifixit_en_all_2025-06.zim"
call :DL_ZIM "https://download.kiwix.org/zim/zimit/nhs.uk_en_medicines_2025-09.zim"                               "nhs.uk_en_medicines_2025-09.zim"
call :DL_ZIM "https://download.kiwix.org/zim/stack_exchange/homebrew.stackexchange.com_en_all_2025-08.zim"        "homebrew.stackexchange.com_en_all_2025-08.zim"
call :DL_ZIM "https://download.kiwix.org/zim/stack_exchange/cooking.stackexchange.com_en_all_2025-07.zim"         "cooking.stackexchange.com_en_all_2025-07.zim"
call :DL_ZIM "https://download.kiwix.org/zim/stack_exchange/gardening.stackexchange.com_en_all_2025-08.zim"       "gardening.stackexchange.com_en_all_2025-08.zim"
call :DL_ZIM "https://download.kiwix.org/zim/stack_exchange/ham.stackexchange.com_en_all_2025-08.zim"             "ham.stackexchange.com_en_all_2025-08.zim"
call :DL_ZIM "https://download.kiwix.org/zim/stack_exchange/outdoors.stackexchange.com_en_all_2025-08.zim"        "outdoors.stackexchange.com_en_all_2025-08.zim"
<# 
  Build-Kiwix-USB.ps1
  --------------------
  This script:

    - Detects USB-attached drives (thumbdrives AND USB hard drives)
    - Lets the user pick one BY DRIVE LETTER (e.g. D)
    - Downloads official Kiwix tools for Windows
      from https://download.kiwix.org
    - Creates an Outpost-Kiwix-Server folder on that drive
    - Sets up:

        \Outpost-Kiwix-Server\
          kiwix-tools-win\
          ZIMs\
          OUTPOST-KIWIX-MENU.bat
          README-OUTPOST.txt
          detect-ip.ps1

  It does NOT format or erase the USB drive. It only creates / updates
  the Outpost-Kiwix-Server folder.

  The batch menu on the USB lets a non-technical user:

    - Open ZIMs folder
    - (Optionally) download a curated “prepper pack” of ZIMs
    - Rebuild the Kiwix library
    - Start/stop the server (port 8090)
    - See an auto-detected LAN URL
#>

$ErrorActionPreference = 'Stop'

Write-Host "=============================================="
Write-Host "  Outpost Kiwix USB Builder (Windows)"
Write-Host "=============================================="
Write-Host ""

# 1. Detect USB drives (thumb drives AND USB HDDs)
$volCandidates = @{}

# Classic removable volumes
Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Removable' } | ForEach-Object {
    $volCandidates[$_.DriveLetter] = $_
}

# Volumes on USB bus-type disks
$usbDisks = Get-Disk | Where-Object { $_.BusType -eq 'USB' -and $_.OperationalStatus -eq 'Online' }
foreach ($disk in $usbDisks) {
    Get-Partition -DiskNumber $disk.Number | Where-Object DriveLetter | ForEach-Object {
        $v = Get-Volume -DriveLetter $_.DriveLetter
        if ($v) { $volCandidates[$v.DriveLetter] = $v }
    }
}

$removable = $volCandidates.GetEnumerator() | ForEach-Object { $_.Value } | Sort-Object DriveLetter

if (-not $removable) {
    Write-Host "No USB drives with a drive letter detected."
    Write-Host "Plug in a USB thumbdrive or USB hard drive and run this script again." -ForegroundColor Yellow
    exit 1
}

Write-Host "Detected USB drives:" -ForegroundColor Cyan
foreach ($vol in $removable) {
    $letter = $vol.DriveLetter
    $label  = $vol.FileSystemLabel
    $sizeGB = "{0:N1}" -f ($vol.Size/1GB)
    $freeGB = "{0:N1}" -f ($vol.SizeRemaining/1GB)
    if (-not $label) { $label = "(no label)" }
    Write-Host ("  {0}:  Label: {1}  Size: {2} GB  Free: {3} GB" -f $letter, $label, $sizeGB, $freeGB)
}
Write-Host ""

# 2. Let user choose by DRIVE LETTER
$targetVolume = $null

while (-not $targetVolume) {
    $inputLetter = Read-Host "Type the DRIVE LETTER of the USB you want to use (for example: D)"
    if ([string]::IsNullOrWhiteSpace($inputLetter)) {
        Write-Host "Please type a drive letter like D and press ENTER." -ForegroundColor Yellow
        continue
    }

    # Normalize: strip colon and whitespace, uppercase single-letter string
    $letter = ($inputLetter.Trim().TrimEnd(':')).ToUpper()

    $candidate = $removable | Where-Object { "$($_.DriveLetter)" -eq $letter }

    if (-not $candidate) {
        Write-Host ("No USB drive found with letter '{0}:'." -f $letter) -ForegroundColor Red
        Write-Host "Please pick one of the listed letters above." -ForegroundColor Yellow
        continue
    }

    $targetVolume = $candidate
}

$driveLetter = $targetVolume.DriveLetter
$driveRoot   = ("{0}:\" -f $driveLetter)

Write-Host ""
Write-Host ("You selected drive {0}:  ({1})" -f $driveLetter, $targetVolume.FileSystemLabel) -ForegroundColor Green
Write-Host "A folder 'Outpost-Kiwix-Server' will be created on this drive."
Write-Host "Existing files on the drive will NOT be erased."
Write-Host ""
$confirm = Read-Host "Type YES to continue, or anything else to cancel"
if ($confirm -ne "YES") {
    Write-Host "Cancelled by user."
    exit 0
}

# 3. Prepare target paths
$targetRoot      = Join-Path $driveRoot "Outpost-Kiwix-Server"
$kiwixDir        = Join-Path $targetRoot "kiwix-tools-win"
$zimDir          = Join-Path $targetRoot "ZIMs"
$readmePath      = Join-Path $targetRoot "README-OUTPOST.txt"
$menuBatPath     = Join-Path $targetRoot "OUTPOST-KIWIX-MENU.bat"
$detectIpPs1Path = Join-Path $targetRoot "detect-ip.ps1"

Write-Host ""
Write-Host ("Creating folder structure on {0}: ..." -f $driveLetter) -ForegroundColor Cyan
New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
New-Item -ItemType Directory -Path $kiwixDir   -Force | Out-Null
New-Item -ItemType Directory -Path $zimDir     -Force | Out-Null

# 4. Download Kiwix tools
$kiwixUrl    = "https://download.kiwix.org/release/kiwix-tools/kiwix-tools_win-i686.zip"
$tempZip     = Join-Path $env:TEMP "kiwix-tools_win-i686.zip"
$tempExtract = Join-Path $env:TEMP ("kiwix-tools-extract-" + [guid]::NewGuid().ToString())

Write-Host ""
Write-Host "Downloading Kiwix tools from:" -ForegroundColor Cyan
Write-Host "  $kiwixUrl" -ForegroundColor Yellow

Invoke-WebRequest -Uri $kiwixUrl -OutFile $tempZip

Write-Host "Download complete. Extracting..." -ForegroundColor Cyan
New-Item -ItemType Directory -Path $tempExtract -Force | Out-Null
Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

Write-Host "Copying Kiwix tools onto the USB drive..." -ForegroundColor Cyan

# The zip extracts into a subfolder; move the CONTENTS into kiwix-tools-win
$innerDir = Get-ChildItem $tempExtract | Where-Object { $_.PSIsContainer } | Select-Object -First 1
if ($innerDir) {
    Get-ChildItem $innerDir.FullName | ForEach-Object {
        Move-Item -Path $_.FullName -Destination $kiwixDir -Force
    }
} else {
    Get-ChildItem $tempExtract | ForEach-Object {
        Move-Item -Path $_.FullName -Destination $kiwixDir -Force
    }
}

Remove-Item $tempZip -Force
Remove-Item $tempExtract -Recurse -Force

# 5. Create README-OUTPOST.txt
$readmeContent = @'
OUTPOST OFFLINE LIBRARY (USB EDITION)
====================================

This USB stick contains the files needed to run a local offline
library server using Kiwix.

On this USB you will find:

  Outpost-Kiwix-Server\
    kiwix-tools-win\
    ZIMs\
    OUTPOST-KIWIX-MENU.bat
    README-OUTPOST.txt

HOW TO USE
----------

1. Plug this USB stick into a Windows computer.
2. Open the "Outpost-Kiwix-Server" folder.
3. Double-click "OUTPOST-KIWIX-MENU.bat".
4. In the menu, you can:

   - [1] "Start server".
   - [2] "Stop server".
   - [3] "Rebuild library from ZIMs".
   - [4] "Open ZIMs folder" and copy your .zim files into that folder.
   - [6] "Download prepper ZIM pack" (if online).

5. The script will show you how to connect:

   - From THIS computer (the server):
       http://localhost:8090

   - From OTHER devices on the same network:
       The menu will try to auto-detect your IPv4 address and
       show a direct link (for example http://192.168.1.100:8090).

IMPORTANT
---------

- PDF viewing can be tricky depending on the browser being used.
  If clicking on a PDF inside a ZIM file results in error then
  try either a different browser such as Duck Duck Go or Firefox,
  or right click the PDF and open in a new tab/window. 

- The Kiwix server set up by this USB does NOT use a username/password
  by default. If your browser asks you for a username and password
  when you open the address above, it is almost certainly coming from
  your network's proxy or filter, not from Kiwix itself.

STOPPING THE SERVER
-------------------

Return to the menu and choose [2] "Stop server", or close the
"Kiwix Server" process.

NOTES
-----

- This USB is NOT locked to a specific computer; you can plug it into
  any Windows machine and run the menu.
- Your ZIM files may be large; ensure the USB has enough free space.
- The optional "prepper pack" downloads a curated set of ZIM files
  (Ready.gov, food prep, knots, medicine, post-disaster, water,
  urban prepper, low-tech magazine, military medicine, etc.)
  that fits easily on a 128 GB drive.

Stay curious and stay prepared.
Outpost Underground
'@

Set-Content -Path $readmePath -Value $readmeContent -Encoding ASCII

# 6. Create detect-ip.ps1 helper
$detectIpScript = @'
# detect-ip.ps1
# Prefer 192.168.x.x; fall back to any non-loopback, non-APIPA IPv4.
try {
    $ip = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object {
            $_.IPAddress -like '192.168.*' -and
            $_.IPAddress -ne '127.0.0.1' -and
            $_.IPAddress -notlike '169.254.*' -and
            $_.InterfaceAlias -notmatch 'vEthernet|VirtualBox|Loopback'
        } |
        Sort-Object InterfaceMetric |
        Select-Object -First 1 -ExpandProperty IPAddress

    if (-not $ip) {
        $ip = Get-NetIPAddress -AddressFamily IPv4 |
            Where-Object {
                $_.IPAddress -ne '127.0.0.1' -and
                $_.IPAddress -notlike '169.254.*' -and
                $_.InterfaceAlias -notmatch 'vEthernet|VirtualBox|Loopback'
            } |
            Sort-Object InterfaceMetric |
            Select-Object -First 1 -ExpandProperty IPAddress
    }

    if ($ip) {
        Write-Output $ip
    }
} catch {
    # Fail silently; caller will handle missing IP
}
'@

if (-not $targetRoot) {
    throw "targetRoot is not set; cannot write detect-ip.ps1"
}

$detectIpPs1Path = Join-Path $targetRoot "detect-ip.ps1"

Set-Content -Path $detectIpPs1Path -Value $detectIpScript -Encoding ASCII

# 7. Create OUTPOST-KIWIX-MENU.bat (now using detect-ip.ps1)
$menuBat = @'
@echo off
setlocal
title Outpost Offline Library Server (Kiwix USB)
cd /d "%~dp0"

if not exist "ZIMs" mkdir "ZIMs"

:MAIN_MENU
cls
echo =======================================================
echo            OUTPOST OFFLINE LIBRARY SERVER
echo =======================================================
echo  This turns this Windows PC into a local Kiwix server.
echo.
echo  ZIM files go in: %cd%\ZIMs
echo.
echo  MENU:
echo     [1] Start server
echo     [2] Stop server
echo     [3] Rebuild library from ZIMs
echo     [4] Open ZIMs folder
echo     [5] Show connection instructions
echo     [6] Download curated "prepper" ZIM pack (needs internet)
echo     [0] Exit
echo.
set "choice="
set /p "choice=Choose an option and press ENTER: "

if "%choice%"=="1" goto START_SERVER
if "%choice%"=="2" goto STOP_SERVER
if "%choice%"=="3" goto REBUILD_LIBRARY
if "%choice%"=="4" goto OPEN_ZIMS
if "%choice%"=="5" goto SHOW_INFO
if "%choice%"=="6" goto DOWNLOAD_CURATED
if "%choice%"=="0" goto END

echo.
echo Invalid choice. Press any key to return to menu...
pause >nul
goto MAIN_MENU


:REBUILD_LIBRARY
cls
echo =======================================================
echo      Rebuilding Kiwix library from ZIM files
echo =======================================================
echo.
echo Library file: %cd%\library.xml
echo ZIM folder : %cd%\ZIMs
echo.

if not exist "kiwix-tools-win\kiwix-serve.exe" (
    echo ERROR: kiwix-serve.exe not found in kiwix-tools-win.
    echo Make sure the USB was built correctly.
    echo.
    pause
    goto MAIN_MENU
)
if not exist "kiwix-tools-win\kiwix-manage.exe" (
    echo ERROR: kiwix-manage.exe not found in kiwix-tools-win.
    echo Make sure the USB was built correctly.
    echo.
    pause
    goto MAIN_MENU
)

rem Create/reset library.xml
"kiwix-tools-win\kiwix-manage.exe" library.xml new >nul 2>&1

rem Check if there are any ZIMs at all
dir /b "ZIMs\*.zim" >nul 2>&1
if errorlevel 1 (
    echo No .zim files found in the ZIMs folder.
    echo You can still start the server, but there will be no content yet.
    echo.
    pause
    goto MAIN_MENU
)

echo Adding ZIM files to the library...
for %%F in ("ZIMs\*.zim") do (
    echo   %%~nxF
    "kiwix-tools-win\kiwix-manage.exe" library.xml add "%%~fF" >nul 2>&1
)

echo.
echo Done rebuilding the library.
echo.
pause
goto MAIN_MENU


:START_SERVER
cls
echo =======================================================
echo                Starting Kiwix Server
echo =======================================================
echo.

if not exist "kiwix-tools-win\kiwix-serve.exe" (
    echo ERROR: kiwix-serve.exe not found in kiwix-tools-win.
    echo Make sure the USB was built correctly.
    echo.
    pause
    goto MAIN_MENU
)
if not exist "kiwix-tools-win\kiwix-manage.exe" (
    echo ERROR: kiwix-manage.exe not found in kiwix-tools-win.
    echo Make sure the USB was built correctly.
    echo.
    pause
    goto MAIN_MENU
)

if not exist "library.xml" (
    echo No library.xml found. Creating a new library...
    "kiwix-tools-win\kiwix-manage.exe" library.xml new >nul 2>&1

    dir /b "ZIMs\*.zim" >nul 2>&1
    if errorlevel 1 (
        echo No ZIM files found yet. You can add them later and rebuild the library.
    ) else (
        echo Adding all ZIMs in ZIMs\ to the library...
        for %%F in ("ZIMs\*.zim") do (
            echo   %%~nxF
            "kiwix-tools-win\kiwix-manage.exe" library.xml add "%%~fF" >nul 2>&1
        )
    )
)

echo.
echo Starting kiwix-serve on port 8090 in the background...
echo.

rem Start kiwix-serve in the SAME window, in the background (no extra window)
rem Log kiwix output to kiwix-server.log instead of showing it to the user
start "" /b "kiwix-tools-win\kiwix-serve.exe" --library --address=0.0.0.0 --port=8090 --monitorLibrary library.xml >kiwix-server.log 2>&1

rem Use helper PowerShell script to detect IPv4 address
set "IP="
for /f "usebackq tokens=* delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0detect-ip.ps1"`) do set "IP=%%I"

echo =======================================================
echo   Kiwix Server started (command sent to kiwix-serve).
echo.
echo   From THIS computer, open:
echo       http://localhost:8090
echo.

if defined IP (
    echo   From OTHER devices on the same Wi-Fi or network:
    echo       http://%IP%:8090
) else (
    echo   The script could not auto-detect an IPv4 address.
    echo   On THIS computer, open a Command Prompt and type:  ipconfig
    echo   Look for your IPv4 Address and use:
    echo       http://YOUR-IPv4-ADDRESS:8090
)

echo.
echo   NOTE: This server does NOT use a username/password.
echo   If your browser asks you to log in, that prompt
echo   is coming from your network (proxy/filter), not Kiwix.
echo =======================================================
echo.
pause
goto MAIN_MENU


:STOP_SERVER
cls
echo Stopping Kiwix server (if running)...
taskkill /IM kiwix-serve.exe /F >nul 2>&1
echo.
echo Kiwix server stopped (if it was running).
echo.
pause
goto MAIN_MENU


:OPEN_ZIMS
cls
echo Opening the ZIMs folder in Explorer...
echo.
start "" "ZIMs"
echo Add or remove .zim files there, then use:
echo   [3] Rebuild library
echo in the main menu.
echo.
pause
goto MAIN_MENU


:SHOW_INFO
cls
echo =======================================================
echo        How to connect to this Kiwix server
echo =======================================================
echo.

set "IP="
for /f "usebackq tokens=* delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0detect-ip.ps1"`) do set "IP=%%I"

echo From THIS computer (the server):
echo   Open:  http://localhost:8090
echo.

if defined IP (
    echo From OTHER devices on the same Wi-Fi or LAN:
    echo   Open:  http://%IP%:8090
) else (
    echo The script could not auto-detect an IPv4 address.
    echo On THIS computer, open a Command Prompt and type:  ipconfig
    echo Then look for your IPv4 Address and use:
    echo   http://YOUR-IPv4-ADDRESS:8090
)

echo.
echo IMPORTANT:
echo   - Kiwix itself does NOT ask for a username/password.
echo   - If you see a login prompt, it is almost certainly
echo     from your network proxy or content filter.
echo.
echo Make sure:
echo   - This PC and the other devices are on the same network.
echo   - Any firewall allows access to port 8090.
echo.
pause
goto MAIN_MENU


:DOWNLOAD_CURATED
cls
echo =======================================================
echo     Download curated "prepper" ZIM pack to ZIMs\
echo =======================================================
echo.
echo This will download several offline sites including:
echo   - cd3wd project (self-reliance, development)
echo   - Cooking / food prep (FOSS cooking)
echo   - Ready.gov (disaster preparedness)
echo   - WikiHow
echo   - Medicine / NHS medicines
echo   - Post-disaster resources
echo   - Water treatment
echo   - Urban Prepper
echo   - Low-tech Magazine (solar)
echo   - iFixit (repairs)
echo   - Ham radio, outdoors, gardening, DIY, mechanics, woodworking
echo.
echo Total size is on the order of ~61 GB.
echo You MUST be online for this to work.
echo.
set "ans="
set /p "ans=Type YES to start the downloads, or anything else to cancel: "
if /I not "%ans%"=="YES" (
    echo.
    echo Cancelled.
    echo.
    pause
    goto MAIN_MENU
)

if not exist "ZIMs" mkdir "ZIMs"

echo.
echo Starting downloads. This can take a long time depending
echo on your connection speed. Each file will be fetched
echo with PowerShell and saved into the ZIMs folder.
echo.

rem Helper: if PowerShell is missing, fail nicely
where powershell >nul 2>&1
if errorlevel 1 (
    echo ERROR: PowerShell not found on this system.
    echo Cannot download the curated ZIM pack automatically.
    echo.
    pause
    goto MAIN_MENU
)

call :DL_ZIM "https://download.kiwix.org/zim/zimit/cd3wdproject.org_en_all_2025-11.zim"                            "cd3wdproject.org_en_all_2025-11.zim"
call :DL_ZIM "https://download.kiwix.org/zim/zimit/foss.cooking_en_all_2025-11.zim"                               "foss.cooking_en_all_2025-11.zim"
call :DL_ZIM "https://download.kiwix.org/zim/www.ready.gov_en.zim"                                                "www.ready.gov_en.zim"
call :DL_ZIM "https://download.kiwix.org/zim/zimgit-food-preparation_en.zim"                                      "zimgit-food-preparation_en.zim"
call :DL_ZIM "https://download.kiwix.org/zim/zimgit-knots_en.zim"                                                 "zimgit-knots_en.zim"
call :DL_ZIM "https://download.kiwix.org/zim/zimgit-medicine_en.zim"                                              "zimgit-medicine_en.zim"
call :DL_ZIM "https://download.kiwix.org/zim/zimgit-post-disaster_en.zim"                                         "zimgit-post-disaster_en.zim"
call :DL_ZIM "https://download.kiwix.org/zim/zimgit-water_en.zim"                                                 "zimgit-water_en.zim"
call :DL_ZIM "https://download.kiwix.org/zim/urban-prepper_en_all.zim"                                            "urban-prepper_en_all.zim"
call :DL_ZIM "https://download.kiwix.org/zim/zimit/solar.lowtechmagazine.com_mul_all_2025-01.zim"                 "solar.lowtechmagazine.com_mul_all_2025-01.zim"
call :DL_ZIM "https://download.kiwix.org/zim/fas-military-medicine_en.zim"                                        "fas-military-medicine_en.zim"
call :DL_ZIM "https://download.kiwix.org/archive/zim/wikihow/wikihow_en_maxi_2023-03.zim"                        "wikihow_en_maxi_2023-03.zim"
call :DL_ZIM "https://download.kiwix.org/zim/ifixit/ifixit_en_all_2025-06.zim"                                    "ifixit_en_all_2025-06.zim"
call :DL_ZIM "https://download.kiwix.org/zim/zimit/nhs.uk_en_medicines_2025-09.zim"                               "nhs.uk_en_medicines_2025-09.zim"
call :DL_ZIM "https://download.kiwix.org/zim/stack_exchange/homebrew.stackexchange.com_en_all_2025-08.zim"        "homebrew.stackexchange.com_en_all_2025-08.zim"
call :DL_ZIM "https://download.kiwix.org/zim/stack_exchange/cooking.stackexchange.com_en_all_2025-07.zim"         "cooking.stackexchange.com_en_all_2025-07.zim"
call :DL_ZIM "https://download.kiwix.org/zim/stack_exchange/gardening.stackexchange.com_en_all_2025-08.zim"       "gardening.stackexchange.com_en_all_2025-08.zim"
call :DL_ZIM "https://download.kiwix.org/zim/stack_exchange/ham.stackexchange.com_en_all_2025-08.zim"             "ham.stackexchange.com_en_all_2025-08.zim"
call :DL_ZIM "https://download.kiwix.org/zim/stack_exchange/outdoors.stackexchange.com_en_all_2025-08.zim"        "outdoors.stackexchange.com_en_all_2025-08.zim"
call :DL_ZIM "https://download.kiwix.org/zim/stack_exchange/woodworking.stackexchange.com_en_all_2025-08.zim"     "woodworking.stackexchange.com_en_all_2025-08.zim"
call :DL_ZIM "https://download.kiwix.org/zim/stack_exchange/diy.stackexchange.com_en_all_2025-08.zim"             "diy.stackexchange.com_en_all_2025-08.zim"
call :DL_ZIM "https://download.kiwix.org/zim/stack_exchange/mechanics.stackexchange.com_en_all_2025-08.zim"       "mechanics.stackexchange.com_en_all_2025-08.zim"

echo.
echo All downloads attempted. If any file failed, you can
echo delete the partial .zim file in ZIMs\ and run this
echo option again.
echo.
echo Next steps:
echo   1. Run [3] Rebuild library from ZIMs.
echo   2. Run [1] Start server.
echo.
pause
goto MAIN_MENU


:DL_ZIM
setlocal
set "URL=%~1"
set "FILE=%~2"
echo -------------------------------------------------------
echo Downloading:
echo   %FILE%
echo   from %URL%
echo -------------------------------------------------------

rem Prefer curl.exe if available (faster), otherwise use PowerShell
where curl >nul 2>&1
if %errorlevel%==0 (
    curl -L "%URL%" -o "ZIMs\%FILE%"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
     "Invoke-WebRequest -Uri '%URL%' -OutFile 'ZIMs\\%FILE%'"
)

if errorlevel 1 (
    echo ERROR: Download failed for %FILE%.
) else (
    echo Finished: %FILE%
)
echo.
endlocal
goto :eof


:END
endlocal
exit /b
'@

Set-Content -Path $menuBatPath -Value $menuBat -Encoding ASCII

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host " Kiwix USB build complete!" -ForegroundColor Green
Write-Host " Folder created: $targetRoot" -ForegroundColor Green
Write-Host ""
Write-Host "On that USB stick:" -ForegroundColor Yellow
Write-Host "  1. Open 'Outpost-Kiwix-Server'"
Write-Host "  2. Double-click 'OUTPOST-KIWIX-MENU.bat'"
Write-Host "  3. Use the menu to:"
Write-Host "       - Open ZIMs folder"
Write-Host "       - (Optionally) download prepper ZIM pack"
Write-Host "       - Rebuild library"
Write-Host "       - Start the server on port 8090"
Write-Host "==============================================" -ForegroundColor Green
