#!/usr/bin/env bash
# make_ipa.sh <archive-dir> <out-dir>
# Collects the iOS app produced by Unreal and zips it as an UNSIGNED .ipa
# (Payload/<App>.app). Sign it later with your own Apple account / tool.
set -euo pipefail
ARCHIVE=$1; OUT=$2
NAME="AurumMobile-iOS-${CONFIG}-unsigned.ipa"
mkdir -p "$OUT"
SEARCH=("$ARCHIVE" "$PROJ_DIR/Binaries/IOS" "$PROJ_DIR/Saved/StagedBuilds" "$PROJ_DIR/Intermediate")

has_content() { [ -n "$(find "$1" \( -iname '*.pak' -o -iname '*.utoc' -o -iname '*.ucas' \) -print -quit 2>/dev/null)" ]; }

IPA=$(find "${SEARCH[@]}" -name '*.ipa' -type f -size +10M 2>/dev/null | head -1 || true)
if [ -n "$IPA" ] && unzip -l "$IPA" | grep -qiE '\.(pak|utoc)$'; then
  echo "Unreal produced an .ipa: $IPA"
  cp "$IPA" "$OUT/$NAME"
else
  # Largest .app that has an executable (the packaged one, not a stub).
  APP=""; BEST=0
  while IFS= read -r -d '' A; do
    EXE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$A/Info.plist" 2>/dev/null || true)
    [ -n "$EXE" ] && [ -f "$A/$EXE" ] || continue
    S=$(du -sk "$A" | cut -f1)
    if [ "$S" -gt "$BEST" ]; then BEST=$S; APP=$A; fi
  done < <(find "${SEARCH[@]}" -name '*.app' -type d -prune -print0 2>/dev/null)
  if [ -z "$APP" ]; then
    echo "::error::No iOS .app with an executable was found."
    find "${SEARCH[@]}" -maxdepth 4 2>/dev/null | head -80
    exit 1
  fi
  echo "Using app: $APP"
  WORK=$(mktemp -d); mkdir -p "$WORK/Payload"
  ditto "$APP" "$WORK/Payload/$(basename "$APP")"
  APPW="$WORK/Payload/$(basename "$APP")"
  if ! has_content "$APPW"; then
    STAGED="$PROJ_DIR/Saved/StagedBuilds/IOS"
    echo "The app has no cooked data; copying the staged build from $STAGED"
    [ -d "$STAGED" ] && rsync -a --exclude '*.app' --exclude '*.dSYM' "$STAGED/" "$APPW/"
  fi
  if ! has_content "$APPW"; then
    echo "::error::The iOS app contains no cooked game data (.pak/.utoc)."
    exit 1
  fi
  (cd "$WORK" && zip -qry -X "$OUT/$NAME" Payload)
  rm -rf "$WORK"
fi

echo "::group::IPA contents"
unzip -l "$OUT/$NAME" | tail -n 40
echo "::endgroup::"
ls -lh "$OUT/$NAME"
{
  echo "## iOS build ready (unsigned)"
  echo "- File: \`$NAME\` ($(du -h "$OUT/$NAME" | cut -f1))"
  echo "- It is **not signed**. Sign it with your Apple account (e.g. Sideloadly, AltStore, ESign) before installing."
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
