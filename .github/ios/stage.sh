#!/usr/bin/env bash
# One resumable stage of the iOS build. Each phase is skipped if a previous stage
# already finished it (markers in Saved/CI). When the stage runs out of time the
# build is stopped cleanly, the workflow saves the intermediate files and the
# next stage continues where this one stopped.
#
# Env: UE, PROJ_DIR, UPROJECT, CONFIG, JOB_START, JOB_MINUTES, RESERVE_MINUTES, OUT_DIR
set -euo pipefail
H=$(cd "$(dirname "$0")" && pwd)
MARK="$PROJ_DIR/Saved/CI"; mkdir -p "$MARK"
LOGS="$RUNNER_TEMP/logs"; mkdir -p "$LOGS"
DEADLINE=$(( JOB_START + (JOB_MINUTES - RESERVE_MINUTES) * 60 ))
BUILD="$UE/Engine/Build/BatchFiles/Mac/Build.sh"
echo "done=false" >> "$GITHUB_OUTPUT"
echo "Already finished: $(ls "$MARK" 2>/dev/null | tr '\n' ' ')"

run() { # run <log-name> <cmd...>; stops the stage (exit 0) when time is up
  local name=$1; shift
  local code=0
  python3 "$H/run_with_deadline.py" "$DEADLINE" "$LOGS/$name.log" -- "$@" || code=$?
  if [ "$code" -eq 124 ]; then
    echo "::notice::'$name' reached this stage's time limit; the next stage continues it."
    exit 0
  elif [ "$code" -ne 0 ]; then
    echo "::error::'$name' failed (exit code $code)."
    "$H/first_errors.sh" "$LOGS/$name.log"
    exit "$code"
  fi
}

# 1) Editor + tools (needed to cook the content). Mac only, Development.
if [ ! -f "$MARK/editor.done" ]; then
  # Compile only the game module first: errors in our C++ show up in minutes
  # instead of after hours of engine compiling.
  if [ ! -f "$MARK/module.checked" ]; then
    code=0
    python3 "$H/run_with_deadline.py" "$DEADLINE" "$LOGS/module-check.log" -- \
      "$BUILD" PUBG_BlueprintEditor Mac Development -project="$UPROJECT" -WaitMutex -Module=PUBG_Blueprint || code=$?
    [ "$code" -eq 124 ] && exit 0
    if [ "$code" -ne 0 ]; then
      if grep -qE "PUBG_BP_Project/Source/.*(error|Error)" "$LOGS/module-check.log"; then
        echo "::error::The game C++ module (PUBG_Blueprint) does not compile."
        "$H/first_errors.sh" "$LOGS/module-check.log"
        exit "$code"
      fi
      echo "::warning::Module-only check failed for another reason (exit $code); continuing with the full build."
    fi
    touch "$MARK/module.checked"
  fi
  run editor "$BUILD" PUBG_BlueprintEditor Mac Development -project="$UPROJECT" -WaitMutex
  run shadercompileworker "$BUILD" ShaderCompileWorker Mac Development -WaitMutex
  run unrealpak "$BUILD" UnrealPak Mac Development -WaitMutex
  touch "$MARK/editor.done"
fi

# 2) The game itself for iPhone (arm64).
export XCODE_XCCONFIG_FILE="$H/unsigned.xcconfig"   # no Apple account: build unsigned
if [ ! -f "$MARK/ios-$CONFIG.done" ]; then
  run ios-game "$BUILD" PUBG_Blueprint IOS "$CONFIG" -project="$UPROJECT" -WaitMutex
  touch "$MARK/ios-$CONFIG.done"
fi

# 3) Cook + stage + package, then the unsigned .ipa.
if [ ! -f "$MARK/package-$CONFIG.done" ]; then
  # Real game files come from Git LFS (the checkout only has small pointer files).
  # Level_Battle (~900 MB) is not cooked for iOS (Config/IOS/IOSGame.ini).
  SRC="$GITHUB_WORKSPACE/PUBG_BP_Project/Content"
  if [ "$(stat -f %z "$SRC/Maps/Level_Test.umap")" -lt 4096 ]; then
    git -C "$GITHUB_WORKSPACE" lfs pull --exclude="PUBG_BP_Project/Content/Maps/Level_Battle*"
  fi
  # Copy onto the build volume (the project is built there, see ios-stage.yml).
  rsync -a --delete --exclude 'Maps/Level_Battle.umap' --exclude 'Maps/Level_Battle_BuiltData.uasset' \
    "$SRC/" "$PROJ_DIR/Content/"
  ARCHIVE="$RUNNER_TEMP/archive"; rm -rf "$ARCHIVE"
  ITERATE=""; [ -d "$PROJ_DIR/Saved/Cooked/IOS" ] && ITERATE="-iterate"
  code=0
  python3 "$H/run_with_deadline.py" "$DEADLINE" "$LOGS/cook-package.log" -- \
    "$UE/Engine/Build/BatchFiles/RunUAT.sh" BuildCookRun \
      -project="$UPROJECT" -noP4 -platform=IOS -clientconfig="$CONFIG" \
      -cook -stage -pak -package -archive -archivedirectory="$ARCHIVE" \
      -nocompileeditor -unattended -utf8output $ITERATE || code=$?
  if [ "$code" -eq 124 ]; then
    echo "::notice::Cooking reached this stage's time limit; the next stage continues it."
    exit 0
  fi
  if [ "$code" -ne 0 ]; then
    echo "::warning::BuildCookRun exited with $code (often the signing/packaging step, which is expected without an Apple account). Trying to assemble the unsigned .ipa anyway."
    "$H/first_errors.sh" "$LOGS/cook-package.log"
  fi
  "$H/make_ipa.sh" "$ARCHIVE" "$OUT_DIR"
  touch "$MARK/package-$CONFIG.done"
fi

echo "done=true" >> "$GITHUB_OUTPUT"
