#!/usr/bin/env bash
# Rebuilds PUBG_BP_Project/Content from the split archive.   ./AssetParts/restore.sh
set -euo pipefail
cd "$(dirname "$0")"
cat Content.tar.gz.part* > Content.tar.gz
sha256sum -c Content.tar.gz.sha256
tar -xzf Content.tar.gz -C ..
rm Content.tar.gz
echo "Done: PUBG_BP_Project/Content restored and verified."
