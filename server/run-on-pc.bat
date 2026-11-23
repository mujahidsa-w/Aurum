@echo off
REM Aurum server on your own Windows PC (free). Then share it with playit.gg (see server/README.md).
setlocal
set GV=4.7.2
set DIR=%LOCALAPPDATA%\AurumServer
if not exist "%DIR%" mkdir "%DIR%"
cd /d "%DIR%"
if not exist godot.exe (
  echo Downloading Godot %GV% ...
  powershell -NoProfile -Command "Invoke-WebRequest -UseBasicParsing https://github.com/godotengine/godot-builds/releases/download/%GV%-stable/Godot_v%GV%-stable_win64.exe.zip -OutFile godot.zip; Expand-Archive -Force godot.zip .; Move-Item -Force Godot_v%GV%-stable_win64_console.exe godot.exe"
)
echo Downloading the latest game ...
powershell -NoProfile -Command "Invoke-WebRequest -UseBasicParsing https://github.com/mujahidsa-w/Aurum/archive/refs/heads/claude/awesome-planck-jiaods.zip -OutFile game.zip; if (Test-Path game) { Remove-Item -Recurse -Force game }; Expand-Archive -Force game.zip game"
for /d %%D in (game\*) do set GAME=%%D\AurumGodot
echo Importing (first time takes a few minutes) ...
godot.exe --headless --path "%GAME%" --import >nul 2>&1
echo.
echo Aurum server starting on UDP 7777. Keep this window open while people play.
godot.exe --headless --path "%GAME%" res://scenes/server.tscn -- --server --port=7777 --lobby-seconds=30
pause
