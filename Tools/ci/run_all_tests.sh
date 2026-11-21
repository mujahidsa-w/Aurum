#!/usr/bin/env bash
# Runs every check that does not need Unreal Engine.
#   1. C++ logic unit tests (anti-cheat math, touch math, default layout)  - g++/clang++
#   2. Unreal convention checker on the C++ module                        - python3
#   3. Mutation test proving the checker detects injected defects          - python3
#   4. Room service unit + end-to-end tests                                - node >= 18
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${TMPDIR:-/tmp}/pubg_logic_tests_$$"
CXX="${CXX:-g++}"

echo "== 1/4 C++ logic tests ($CXX)"
"$CXX" -std=c++17 -Wall -Wextra -Werror -I"$ROOT/PUBG_BP_Project/Source/PUBG_Blueprint/Public" \
  "$ROOT/Tests/LogicTests/test_logic.cpp" -o "$OUT"
"$OUT"
rm -f "$OUT"

echo "== 2/4 Unreal convention checker"
python3 -I "$ROOT/Tools/ci/check_unreal_conventions.py"

echo "== 3/4 checker mutation test"
python3 -I "$ROOT/Tools/ci/test_checker.py"

echo "== 4/4 room service tests"
(cd "$ROOT/Tools/RoomService" && node --test test/*.test.js 2>&1 | tail -8)

echo "ALL CHECKS PASSED"
