#!/usr/bin/env bash
# Copies the multiplayer / mobile layer from this repository into a full
# PUBG-UNREAL checkout (one that has the real Git LFS assets).
#
#   ./Tools/scripts/apply-to-project.sh /path/to/PUBG-UNREAL
#
# Copied: PUBG_BP_Project/Source, PUBG_BP_Project/Config, PUBG_BP_Project/PUBG_Blueprint.uproject.
# Nothing under Content/ is touched. Existing files that are replaced are backed up
# to <target>/.pre-multiplayer-backup/ first.
set -euo pipefail
SRC="$(cd "$(dirname "$0")/../.." && pwd)/PUBG_BP_Project"
DST="${1:?usage: $0 /path/to/PUBG-UNREAL}/PUBG_BP_Project"
[ -d "$DST/Content" ] || { echo "error: $DST/Content not found (wrong path?)"; exit 1; }
if [ -n "$(find "$DST/Content/Blueprints" -name '*.uasset' -size -1024c -print -quit)" ]; then
  echo "warning: $DST/Content contains Git LFS pointer files, not real assets."
  echo "         Run 'git lfs pull' in the target repository first (see Docs/03-Build-And-Run.md)."
fi
BACKUP="$DST/../.pre-multiplayer-backup"
mkdir -p "$BACKUP"
for item in Config PUBG_Blueprint.uproject Source; do
  if [ -e "$DST/$item" ]; then cp -a "$DST/$item" "$BACKUP/" ; fi
done
cp -a "$SRC/Source" "$DST/"
cp -a "$SRC/Config/." "$DST/Config/"
cp -a "$SRC/PUBG_Blueprint.uproject" "$DST/"
echo "Done. Backup of replaced files: $BACKUP"
echo "Next: right-click PUBG_Blueprint.uproject > Generate Visual Studio project files, then build."
