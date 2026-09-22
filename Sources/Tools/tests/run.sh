#!/usr/bin/env bash
# Runs the script tests against the real sources, with the openmw API faked out (stubs.lua).
#
#   bash Sources/Tools/tests/run.sh
#
# ReAnimation is found next to this mod; set H2H_REANIMATION to point somewhere else.
set -euo pipefail
cd "$(dirname "$0")"
status=0
for test in test_*.lua; do
    printf '%-18s ' "$test"
    if ! lua "$test"; then status=1; fi
done
exit $status
