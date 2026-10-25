@echo off
setlocal
rem Creates a project-local virtual environment (.venv) with lupa (Lua 5.1) if needed, then runs the suite.
rem Optional environment variables:
rem   ESO_ADDON_ROOT      folder holding DungeoneersLedger.addon (default: found relative to this folder)
rem   ESO_LIBSETS_PATH    installed LibSets folder (default: Documents\Elder Scrolls Online\live\AddOns\LibSets)
rem   ESO_UI_SRC          extracted esoui source folder (enables the "API names exist in the game" checks)
rem   ESO_PACKAGE_SCRIPT  path of tools\package.ps1 (default: searched upwards from this folder)
cd /d "%~dp0"
set "VENV=%~dp0.venv"
set "VPY=%VENV%\Scripts\python.exe"
"%VPY%" -I -c "import lupa.lua51" >nul 2>&1
if errorlevel 1 (
    echo Creating virtual environment in %VENV% ...
    if exist "%VENV%" rmdir /s /q "%VENV%"
    python -m venv "%VENV%" || (echo Could not create the virtual environment. Is Python 3 installed? & exit /b 9)
    "%VPY%" -m pip install --disable-pip-version-check -q -r requirements.txt || (echo pip install failed & exit /b 9)
)
"%VPY%" -I run_tests.py %*
set RC=%ERRORLEVEL%
echo.
if %RC%==0 (echo RESULT: ALL TESTS PASSED) else if %RC%==2 (echo RESULT: only known-bug tests fail ^(see list above^)) else (echo RESULT: FAILURES ^(exit code %RC%^))
exit /b %RC%
