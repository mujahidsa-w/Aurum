#!/usr/bin/env bash
# Aurum server on your own Mac or Linux computer (free). Then share it with playit.gg.
set -euo pipefail
GV=4.7.2
DIR="$HOME/AurumServer"
mkdir -p "$DIR" && cd "$DIR"
if [ "$(uname)" = "Darwin" ]; then
  if [ ! -d Godot.app ]; then
    curl -fsSL -o godot.zip "https://github.com/godotengine/godot-builds/releases/download/${GV}-stable/Godot_v${GV}-stable_macos.universal.zip"
    unzip -q -o godot.zip
  fi
  GODOT="$DIR/Godot.app/Contents/MacOS/Godot"
else
  case "$(uname -m)" in aarch64|arm64) A=arm64 ;; *) A=x86_64 ;; esac
  if [ ! -x godot ]; then
    curl -fsSL -o godot.zip "https://github.com/godotengine/godot-builds/releases/download/${GV}-stable/Godot_v${GV}-stable_linux.${A}.zip"
    unzip -q -o godot.zip && mv Godot_v*_linux.* godot && chmod +x godot
  fi
  GODOT="$DIR/godot"
fi
curl -fsSL -o game.zip "https://github.com/mujahidsa-w/Aurum/archive/refs/heads/claude/awesome-planck-jiaods.zip"
rm -rf game && mkdir game && unzip -q game.zip -d game
GAME=$(ls -d game/*/AurumGodot)
"$GODOT" --headless --path "$GAME" --import >/dev/null 2>&1 || true
echo "Aurum server starting on UDP 7777. Keep this terminal open while people play."
exec "$GODOT" --headless --path "$GAME" res://scenes/server.tscn -- --server --port=7777 --lobby-seconds=30
