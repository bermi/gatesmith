#!/usr/bin/env bash
# Gatesmith loop setup — called by /gatesmith:loop.
# Acquires the per-owner lock and writes the loop state file the Stop hook drives.
#
#   /gatesmith:loop <owner> [--max-iterations N] [--remote-control] [--tick-cmd ./x] [--lock-ttl N] [--force]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

OWNER=""
MAX_ITERATIONS=0
REMOTE_CONTROL=false
TICK_CMD=""
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-iterations) MAX_ITERATIONS="${2:-}"; shift 2 ;;
    --remote-control) REMOTE_CONTROL=true; shift ;;
    --tick-cmd)       TICK_CMD="${2:-}"; shift 2 ;;
    --lock-ttl)       export GATESMITH_LOCK_TTL="${2:-}"; shift 2 ;;
    --force)          FORCE=true; shift ;;
    -h|--help)
      echo "usage: /gatesmith:loop <owner> [--max-iterations N] [--remote-control] [--tick-cmd ./x] [--lock-ttl N] [--force]"
      exit 0 ;;
    --*) echo "gatesmith:loop: unknown flag $1" >&2; exit 1 ;;
    *)
      if [[ -z "$OWNER" ]]; then OWNER="$1"; else
        echo "gatesmith:loop: unexpected argument '$1' (one <owner> only)" >&2; exit 1
      fi
      shift ;;
  esac
done

# No owner given → single-stream mode: loop the unowned ledger (`--owner ""`),
# tracked under the reserved label '_default'.
OWNER_LABEL="$OWNER"
SCOPE_ARG="$OWNER"
if [[ -z "$OWNER" ]]; then
  OWNER_LABEL="_default"
  SCOPE_ARG='--owner ""'
fi
case "$OWNER" in
  __conductor__|__all__) echo "gatesmith:loop: '$OWNER' is a reserved name" >&2; exit 1 ;;
esac
[[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]] || { echo "gatesmith:loop: --max-iterations must be an integer" >&2; exit 1; }

# Validate --tick-cmd: relative, starts with ./, no .. segment, resolves inside the repo.
if [[ -n "$TICK_CMD" ]]; then
  case "$TICK_CMD" in
    ./*) : ;;
    *) echo "gatesmith:loop: --tick-cmd must start with ./ (got: $TICK_CMD)" >&2; exit 1 ;;
  esac
  case "$TICK_CMD" in
    *..*) echo "gatesmith:loop: --tick-cmd must not contain '..'" >&2; exit 1 ;;
  esac
  if ! git ls-files --error-unmatch "$TICK_CMD" >/dev/null 2>&1 && [[ ! -x "$TICK_CMD" ]]; then
    echo "gatesmith:loop: --tick-cmd '$TICK_CMD' is not a tracked or executable file in this repo" >&2
    exit 1
  fi
fi

mkdir -p "$GATESMITH_LOOPS_DIR" "$GATESMITH_LOCKS_DIR"

SESSION="${CLAUDE_CODE_SESSION_ID:-}"
LOCK="$GATESMITH_LOCKS_DIR/$OWNER_LABEL.lock"
STATE="$GATESMITH_LOOPS_DIR/$OWNER_LABEL.loop.md"

# One loop per session: refuse a second, different-owner loop file in this session.
if [[ -n "$SESSION" ]]; then
  shopt -s nullglob
  for f in "$GATESMITH_LOOPS_DIR"/*.loop.md; do
    [[ "$(gs_fm_field "$f" session_id)" == "$SESSION" ]] || continue
    existing="$(gs_fm_field "$f" owner)"
    if [[ "$existing" != "$OWNER_LABEL" ]]; then
      echo "gatesmith:loop: this session already drives owner '$existing'. Cancel it first: /gatesmith:cancel $existing" >&2
      exit 1
    fi
  done
fi

# Acquire the per-owner lock (atomic), reclaiming a stale one.
take_lock() { gs_atomic_create "$LOCK" "$(gs_lock_body "$OWNER_LABEL")"; }
case "$(gs_lock_state "$LOCK")" in
  none)
    take_lock || { echo "gatesmith:loop: lock for '$OWNER_LABEL' was just taken by another process" >&2; exit 1; } ;;
  stale)
    echo "gatesmith:loop: reclaiming stale lock for '$OWNER_LABEL' (prev session $(gs_field "$LOCK" session_id))." >&2
    rm -f "$LOCK"; take_lock || { echo "gatesmith:loop: race reclaiming lock for '$OWNER_LABEL'" >&2; exit 1; } ;;
  live)
    holder="$(gs_field "$LOCK" session_id)"
    if [[ "$FORCE" == true || ( -n "$SESSION" && "$holder" == "$SESSION" ) ]]; then
      rm -f "$LOCK"; take_lock || true   # re-entrant refresh / forced break
    else
      echo "gatesmith:loop: owner '$OWNER_LABEL' is already being looped by session ${holder:-?} on host $(gs_field "$LOCK" hostname) (heartbeat $(gs_field "$LOCK" heartbeat)). Use --force to break it." >&2
      exit 1
    fi ;;
esac

# The literal tick command the Stop hook re-feeds each iteration.
CMD="/gatesmith $SCOPE_ARG"
[[ "$REMOTE_CONTROL" == true ]] && CMD="$CMD --remote-control"
[[ -n "$TICK_CMD" ]] && CMD="$CMD --tick-cmd $TICK_CMD"

cat > "$STATE" <<EOF
---
owner: $OWNER_LABEL
iteration: 1
session_id: ${SESSION}
max_iterations: $MAX_ITERATIONS
remote_control: $REMOTE_CONTROL
tick_cmd: "$TICK_CMD"
started_at: "$(gs_now_iso)"
---

$CMD
EOF

cat <<EOF
Gatesmith loop activated for owner '$OWNER_LABEL' in this session.
  iteration:       1
  max-iterations:  $([[ $MAX_ITERATIONS -gt 0 ]] && echo "$MAX_ITERATIONS" || echo unlimited)
  remote-control:  $REMOTE_CONTROL
  tick-cmd:        ${TICK_CMD:-none}

Run one '$CMD' tick now. When you try to stop, the Stop hook re-feeds it until
this scope has no pickable gates (the tick prints an OWNER COMPLETE / PROJECT
COMPLETE sentinel) or --max-iterations is reached. Do NOT fabricate completion.
Stop early with: /gatesmith:cancel $OWNER_LABEL
EOF
