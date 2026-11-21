#!/usr/bin/env bash
# Print the first real errors of a build log (easy to copy from the job summary).
LOG=$1
[ -f "$LOG" ] || exit 0
echo "::group::First errors in $(basename "$LOG")"
grep -E "error:|error [A-Z]+[0-9]+|Error:|ERROR:|fatal error|Undefined symbols|ld: " "$LOG" \
  | grep -vE "Wno-error|-Werror|0 error\(s\)|Error: Command-line contains" | head -60 || true
echo "::endgroup::"
{
  echo "### First errors in \`$(basename "$LOG")\`"
  echo '```'
  grep -E "error:|Error:|ERROR:|fatal error|Undefined symbols" "$LOG" | grep -vE "Wno-error|-Werror" | head -30 || true
  echo '```'
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
