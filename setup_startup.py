import os
import sys

def setup_startup():
    startup_dir = os.path.join(os.environ['APPDATA'], 'Microsoft', 'Windows', 'Start Menu', 'Programs', 'Startup')
    bat_path = os.path.join(startup_dir, 'StartCortexServer.bat')
    work_dir = os.path.abspath(os.path.dirname(__file__))
    
    bat_template = """@echo off
set "WORKDIR={work_dir}"
cd /d "%WORKDIR%"

:: Check with PowerShell dialog box
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "$wshell = New-Object -ComObject Wscript.Shell; $wshell.Popup('Do you want to start the Cortex Server?', 0, 'Cortex Server Startup', 4 + 32)"`) do set "CHOICE=%%I"

if "%CHOICE%"=="6" (
    echo Starting Cortex services...
    if exist ".venv\\Scripts\\python.exe" (
        start "" ".venv\\Scripts\\pythonw.exe" launch_gui.py
    ) else if exist "venv\\Scripts\\python.exe" (
        start "" "venv\\Scripts\\pythonw.exe" launch_gui.py
    ) else (
        start "" "pythonw" launch_gui.py
    )
) else (
    echo Cortex Server startup cancelled.
)
"""
    
    bat_content = bat_template.replace('{work_dir}', work_dir)
    
    try:
        with open(bat_path, 'w', encoding='utf-8') as f:
            f.write(bat_content)
        print(f"Startup script successfully created at: {bat_path}")
    except Exception as e:
        print(f"Error creating startup script: {e}")

if __name__ == '__main__':
    setup_startup()
