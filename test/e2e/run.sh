#!/usr/bin/env bash
# Gatesmith e2e runner — bash layers (deterministic, no LLM). The agent-driven layers
# (snapdir fleet ping-pong + conductor run) are triggered from a Claude Code session;
# see test/e2e/agent/README.md.
#
#   SNAPDIR_BIN=/abs/path/to/snapdir test/e2e/run.sh
#   GATESMITH_REQUIRE_SNAPDIR=1 test/e2e/run.sh   # treat snapdir-skip as failure
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RC=0

echo "== Gatesmith e2e: bash layer =="
for t in 01_owner_scoping 02_ledger_writelock 03_loop_lifecycle 04_remote_control 05_supersede 06_sabotage; do
  echo "--- $t ---"
  bash "$HERE/$t.sh" || RC=1
done

echo "--- snapdir_pingpong ---"
if command -v "${SNAPDIR_BIN:-snapdir}" >/dev/null 2>&1 || [[ -x "${SNAPDIR_BIN:-snapdir}" ]]; then
  bash "$HERE/snapdir_pingpong.sh" || RC=1
else
  if [[ "${GATESMITH_REQUIRE_SNAPDIR:-0}" == "1" ]]; then
    echo "  FAIL: snapdir required but not found"; RC=1
  else
    echo "  skip: snapdir not found (set SNAPDIR_BIN, or GATESMITH_REQUIRE_SNAPDIR=1 to enforce)"
  fi
fi

echo
echo "== Agent-driven layer (run from a Claude Code session) =="
echo "  See test/e2e/agent/README.md:"
echo "   - PINGPONG_PEER_PROMPT.md   : spawn 2-3 peers, assert convergence"
echo "   - CONDUCTOR_WORKER_PROMPT.md : conductor drives examples/selftest to ALL OWNERS COMPLETE"
echo
[[ $RC -eq 0 ]] && echo "RESULT: PASS" || echo "RESULT: FAIL"
exit $RC
