#!/usr/bin/env bash
# Gatesmith loop cancel — called by /gatesmith:cancel.
# Removes a loop state file and releases its lock so the next Stop lets the session exit.
#
#   /gatesmith:cancel <owner>           cancel one owner (must be owned by this session)
#   /gatesmith:cancel --all             cancel every loop owned by this session
#   /gatesmith:cancel <owner> --force   break a loop/lock held by another (dead) session
#   /gatesmith:cancel --all --force     break every loop and lock repo-wide
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

OWNER=""
ALL=false
FORCE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)     ALL=true; shift ;;
    --force)   FORCE=true; shift ;;
    -h|--help) echo "usage: /gatesmith:cancel <owner> | --all [--force]"; exit 0 ;;
    --*)       echo "gatesmith:cancel: unknown flag $1" >&2; exit 1 ;;
    *)         OWNER="$1"; shift ;;
  esac
done

SESSION="${CLAUDE_CODE_SESSION_ID:-}"
shopt -s nullglob

remove_loop() {
  local owner="$1"
  local state="$GATESMITH_LOOPS_DIR/$owner.loop.md"
  local lock="$GATESMITH_LOCKS_DIR/$owner.lock"
  local it; it="$(gs_fm_field "$state" iteration)"
  rm -f "$state" "$lock"
  echo "Cancelled loop for '$owner' (was at iteration ${it:-?})."
}

session_owns() { [[ "$(gs_fm_field "$1" session_id)" == "$SESSION" ]]; }

if [[ "$ALL" == true ]]; then
  found=false
  for f in "$GATESMITH_LOOPS_DIR"/*.loop.md; do
    if [[ "$FORCE" == true ]] || session_owns "$f"; then
      remove_loop "$(gs_fm_field "$f" owner)"; found=true
    fi
  done
  if [[ "$FORCE" == true ]]; then
    for l in "$GATESMITH_LOCKS_DIR"/*.lock; do
      [[ -f "$l" ]] || continue          # skip the ledger.lock directory
      rm -f "$l"; found=true
    done
  fi
  [[ "$found" == true ]] || echo "No loops to cancel for this session."
  exit 0
fi

[[ -n "$OWNER" ]] || { echo "gatesmith:cancel: give an <owner> or --all" >&2; exit 1; }
STATE="$GATESMITH_LOOPS_DIR/$OWNER.loop.md"
if [[ ! -e "$STATE" ]]; then
  echo "No active loop for '$OWNER'."
  exit 0
fi
if [[ "$FORCE" == true ]] || session_owns "$STATE"; then
  remove_loop "$OWNER"
else
  echo "gatesmith:cancel: loop for '$OWNER' is owned by another session; use --force to break it." >&2
  exit 1
fi
