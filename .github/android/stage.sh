#!/usr/bin/env bash
# One resumable stage of the Android build (see android-stage.yml). Phases already
# finished by an earlier stage are skipped (markers in Saved/CI). When the stage
# runs out of time the build stops cleanly and the next stage continues it.
#
# Env: UE, PROJ_DIR, UPROJECT, CONFIG, JOB_START, JOB_MINUTES, RESERVE_MINUTES, OUT_DIR
set -euo pipefail
H=$(cd "$(dirname "$0")" && pwd)
C="$H/../ios"   # shared helpers (deadline runner, error summary)
MARK="$PROJ_DIR/Saved/CI"; mkdir -p "$MARK"
LOGS="$RUNNER_TEMP/logs"; mkdir -p "$LOGS"
DEADLINE=$(( JOB_START + (JOB_MINUTES - RESERVE_MINUTES) * 60 ))
BUILD="$UE/Engine/Build/BatchFiles/Linux/Build.sh"
echo "done=false" >> "$GITHUB_OUTPUT"
echo "Already finished: $(ls "$MARK" 2>/dev/null | tr '\n' ' ')"

run() { # run <log-name> <cmd...>; ends the stage (exit 0) when time is up
  local name=$1; shift
  local code=0
  python3 "$C/run_with_deadline.py" "$DEADLINE" "$LOGS/$name.log" -- "$@" || code=$?
  if [ "$code" -eq 124 ]; then
    echo "::notice::'$name' reached this stage's time limit; the next stage continues it."
    exit 0
  elif [ "$code" -ne 0 ]; then
    echo "::error::'$name' failed (exit code $code)."
    "$C/first_errors.sh" "$LOGS/$name.log"
    exit "$code"
  fi
}

# 0) The game C++ module alone: our compile errors show up in minutes.
if [ ! -f "$MARK/module.checked" ]; then
  code=0
  python3 "$C/run_with_deadline.py" "$DEADLINE" "$LOGS/module-check.log" -- \
    "$BUILD" PUBG_BlueprintEditor Linux Development -project="$UPROJECT" -WaitMutex -Module=PUBG_Blueprint || code=$?
  [ "$code" -eq 124 ] && exit 0
  if [ "$code" -ne 0 ]; then
    if grep -qE "PUBG_BP_Project/Source/.*(error|Error)" "$LOGS/module-check.log"; then
      echo "::error::The game C++ module (PUBG_Blueprint) does not compile."
      "$C/first_errors.sh" "$LOGS/module-check.log"
      exit "$code"
    fi
    echo "::warning::Module-only check failed for another reason (exit $code); continuing with the full build."
  fi
  touch "$MARK/module.checked"
fi

# 1) Editor + tools (needed to cook the content), Linux.
if [ ! -f "$MARK/editor.done" ]; then
  run editor "$BUILD" PUBG_BlueprintEditor Linux Development -project="$UPROJECT" -WaitMutex
  run shadercompileworker "$BUILD" ShaderCompileWorker Linux Development -WaitMutex
  run unrealpak "$BUILD" UnrealPak Linux Development -WaitMutex
  touch "$MARK/editor.done"
fi

# 2) The game for Android (arm64).
if [ ! -f "$MARK/android-$CONFIG.done" ]; then
  run android-game "$BUILD" PUBG_Blueprint Android "$CONFIG" -project="$UPROJECT" -WaitMutex
  touch "$MARK/android-$CONFIG.done"
fi

# 3) Cook + stage + package the APK.
if [ ! -f "$MARK/package-$CONFIG.done" ]; then
  # Real game files come from Git LFS. Level_Battle (~900 MB) is not cooked for
  # Android (Config/Android/AndroidGame.ini).
  if [ "$(stat -c %s "$PROJ_DIR/Content/Maps/Level_Test.umap")" -lt 4096 ]; then
    git -C "$GITHUB_WORKSPACE" lfs pull --exclude="PUBG_BP_Project/Content/Maps/Level_Battle*"
  fi
  rm -f "$PROJ_DIR"/Content/Maps/Level_Battle.umap "$PROJ_DIR"/Content/Maps/Level_Battle_BuiltData.uasset
  ARCHIVE="$RUNNER_TEMP/archive"; rm -rf "$ARCHIVE"
  ITERATE=""; [ -d "$PROJ_DIR/Saved/Cooked" ] && ITERATE="-iterate"
  run cook-package "$UE/Engine/Build/BatchFiles/RunUAT.sh" BuildCookRun \
      -project="$UPROJECT" -noP4 -platform=Android -cookflavor=ASTC -clientconfig="$CONFIG" \
      -cook -stage -pak -package -archive -archivedirectory="$ARCHIVE" \
      -nocompileeditor -unattended -utf8output $ITERATE
  mkdir -p "$OUT_DIR"
  find "$ARCHIVE" "$PROJ_DIR/Binaries/Android" -name '*.apk' -type f -exec cp {} "$OUT_DIR/" \; 2>/dev/null || true
  if ! ls "$OUT_DIR"/*.apk >/dev/null 2>&1; then
    echo "::error::Packaging finished but no .apk was found."
    find "$ARCHIVE" -maxdepth 4 | head -50
    exit 1
  fi
  ls -lh "$OUT_DIR"
  {
    echo "## Android build ready"
    for f in "$OUT_DIR"/*.apk; do echo "- \`$(basename "$f")\` ($(du -h "$f" | cut -f1))"; done
    echo "- Signed with a debug key: install it directly on the phone (allow installing from unknown sources)."
  } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
  touch "$MARK/package-$CONFIG.done"
fi

echo "done=true" >> "$GITHUB_OUTPUT"
