#!/usr/bin/env bash
# Gatesmith loop Stop hook (vendored, owner-scoped, lock-aware).
#
# Fires on every session-stop in this repo. It re-feeds the owner tick command for
# THIS session's loop until that owner is complete (the tick prints an OWNER COMPLETE
# / PROJECT COMPLETE sentinel) or --max-iterations is hit. Sessions that own no loop
# state file — including the /gatesmith:conduct conductor — fall through and exit.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"

HOOK_INPUT="$(cat)"
HOOK_SESSION="$(printf '%s' "$HOOK_INPUT" | jq -r '.session_id // ""')"
TRANSCRIPT_PATH="$(printf '%s' "$HOOK_INPUT" | jq -r '.transcript_path // ""')"

shopt -s nullglob
matches=()
for f in "$GATESMITH_LOOPS_DIR"/*.loop.md; do
  [[ -n "$HOOK_SESSION" && "$(gs_fm_field "$f" session_id)" == "$HOOK_SESSION" ]] && matches+=("$f")
done

# No loop owned by this session -> allow exit (plain sessions AND the conductor).
[[ ${#matches[@]} -gt 0 ]] || exit 0

# One-session-one-owner is the contract (setup-loop enforces it). If somehow more
# than one matches, drive the lexically-first deterministically and warn.
IFS=$'\n' matches=($(printf '%s\n' "${matches[@]}" | sort)); unset IFS
STATE="${matches[0]}"
if [[ ${#matches[@]} -gt 1 ]]; then
  echo "⚠️  gatesmith: session $HOOK_SESSION owns ${#matches[@]} loops; driving $(gs_fm_field "$STATE" owner) only." >&2
fi

OWNER="$(gs_fm_field "$STATE" owner)"
ITERATION="$(gs_fm_field "$STATE" iteration)"
MAX_ITERATIONS="$(gs_fm_field "$STATE" max_iterations)"
LOCK="$GATESMITH_LOCKS_DIR/$OWNER.lock"

if [[ ! "$ITERATION" =~ ^[0-9]+$ ]]; then
  echo "gatesmith: corrupt iteration in $STATE; stopping loop." >&2
  rm -f "$STATE" "$LOCK"; exit 0
fi
[[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]] || MAX_ITERATIONS=0

if (( MAX_ITERATIONS > 0 && ITERATION >= MAX_ITERATIONS )); then
  echo "🛑 gatesmith loop '$OWNER': max iterations ($MAX_ITERATIONS) reached." >&2
  rm -f "$STATE" "$LOCK"; exit 0
fi

# Last assistant text block (same slurp the ralph-loop hook uses), for sentinel matching.
LAST_OUTPUT=""
if [[ -f "$TRANSCRIPT_PATH" ]] && grep -q '"role":"assistant"' "$TRANSCRIPT_PATH"; then
  LAST_LINES="$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" | tail -n 100)"
  set +e
  LAST_OUTPUT="$(printf '%s' "$LAST_LINES" | jq -rs 'map(.message.content[]? | select(.type=="text") | .text) | last // ""' 2>/dev/null)"
  set -e
fi

# Completion: this owner is done, or the whole project is green.
if printf '%s' "$LAST_OUTPUT" | grep -qE "===== OWNER COMPLETE: ${OWNER} =====|===== PROJECT COMPLETE"; then
  echo "✅ gatesmith loop '$OWNER': complete." >&2
  rm -f "$STATE" "$LOCK"; exit 0
fi

# Not complete (this includes OWNER IDLE remote-wait) -> continue the loop.
NEXT=$((ITERATION + 1))
CMD="$(awk '/^---$/{i++; next} i>=2' "$STATE")"
if [[ -z "$CMD" ]]; then
  echo "gatesmith: no tick command in $STATE; stopping loop." >&2
  rm -f "$STATE" "$LOCK"; exit 0
fi

TMP="${STATE}.tmp.$$"
sed "s/^iteration: .*/iteration: $NEXT/" "$STATE" > "$TMP"
mv "$TMP" "$STATE"

gs_lock_refresh "$LOCK"   # heartbeat — the reliable per-tick pulse

MSG="🔁 gatesmith '$OWNER' iteration $NEXT"
if printf '%s' "$LAST_OUTPUT" | grep -qE "===== OWNER IDLE: ${OWNER} "; then
  MSG="$MSG (remote-wait — polling for answers)"
fi

jq -n --arg prompt "$CMD" --arg msg "$MSG" \
  '{decision:"block", reason:$prompt, systemMessage:$msg}'
exit 0
