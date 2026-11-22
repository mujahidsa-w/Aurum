#!/usr/bin/env bash
# disk_check.sh <dir> <label>: write 1 GB of random data, drop the file cache,
# read it back. A mismatch means the runner's disk returns corrupted data.
DIR=$1; LABEL=$2; F="$DIR/.diskcheck"
dd if=/dev/urandom of="$F" bs=1m count=1024 2>/dev/null
A=$(shasum -a 256 "$F" | cut -d' ' -f1)
sync; sudo purge 2>/dev/null || true
B=$(shasum -a 256 "$F" | cut -d' ' -f1)
rm -f "$F"
if [ "$A" = "$B" ]; then
  echo "Disk check [$LABEL] on $DIR: OK"
else
  echo "::error::Disk check [$LABEL] on $DIR: data read back differs from what was written (runner disk is corrupting data)."
  echo "### Disk check failed: $LABEL" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
  exit 1
fi
