#!/usr/bin/env bash
# ledger-fence.sh — a lane may move its gate's STATUS, never its BAR.
#
#   .claude/gatesmith/ledger-fence.sh              # working tree vs HEAD
#   .claude/gatesmith/ledger-fence.sh <ref>        # working tree vs <ref>
#   .claude/gatesmith/ledger-fence.sh <ref> <ref>  # between two refs
#
# WHY THIS EXISTS
#
#   "Never weaken a threshold to go green" is the rule the whole discipline rests on, and in
#   Gatesmith it is not merely a rule — it is *reachable*. A `/gatesmith <owner>` tick may PICK and
#   MUTATE gates whose owner matches its scope, so the agent with the strongest incentive to move a
#   bar is the one holding the pen. A rule an agent can quietly edit its way around is a suggestion.
#
#   So the fields that define what "passing" MEANS are fenced. A lane may append `failure_reason`,
#   bump `failure_count`, flip `status` — that is its job. If it changes `verification_cmd`,
#   `pass_criteria`, `thresholds` or `controls`, this exits non-zero and names the gate.
#
# THE ESCAPE HATCH IS NOT A FLAG
#
#   Criteria do sometimes have to change — a gate can be wrong. The escape hatch is evidence, not
#   permission: `.gatesmith/CORRECTIONS.md` must contain an entry naming the gate, and that entry
#   must carry the demonstration that the REFERENCE or BASELINE fails the same predicate, with the
#   measurement. An entry that just says "loosened it, was too strict" is the thing this prevents;
#   a human reviewing the diff will see the correction and can judge it.
#
#   This script checks that an entry EXISTS and is non-trivial. It cannot check that the
#   demonstration is honest. That is what "whoever implements does not verify" is for.
#
# Exit: 0 nothing fenced changed, or every change is covered by a corrections entry
#       1 a fenced field moved without one
#       3 the ledger could not be read at one of the revisions

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

LEDGER=".gatesmith/gates.yaml"
CORRECTIONS=".gatesmith/CORRECTIONS.md"

# The fields that define what passing MEANS. `status`, `failure_count`, `failure_reason`,
# `passed_at`, `git_sha`, `snapdir_id` and `pending_question` are deliberately NOT here: those are
# the lane's own bookkeeping and fencing them would stop the loop working.
FENCED_RE='^[[:space:]]*(verification_cmd|pass_criteria|thresholds|controls|expect|human_checkpoint):'

BEFORE_REF="${1:-HEAD}"
AFTER_REF="${2:-}"

# ledger_at <ref|WORKTREE> — flatten the ledger to `gate<TAB>field<TAB>value` for fenced fields, so
# a reordering or a comment edit is not mistaken for a criterion change.
ledger_at() {
  local ref="$1" src
  if [[ "$ref" == "WORKTREE" ]]; then
    src="$(cat "$LEDGER" 2>/dev/null)" || return 1
  else
    src="$(git show "$ref:$LEDGER" 2>/dev/null)" || return 1
  fi
  [[ -n "$src" ]] || return 1
  printf '%s\n' "$src" | awk -v fenced="$FENCED_RE" '
    /^[[:space:]]*-[[:space:]]*id:[[:space:]]*/ {
      gate = $0; sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/, "", gate)
      gsub(/^"|"$|[[:space:]]+$/, "", gate); inblock = 1; next
    }
    inblock && $0 ~ fenced {
      line = $0; sub(/^[[:space:]]+/, "", line); sub(/[[:space:]]+$/, "", line)
      split(line, kv, ":"); key = kv[1]
      val = line; sub(/^[^:]*:[[:space:]]*/, "", val)
      print gate "\t" key "\t" val; next
    }
    # a nested pass_criteria block ("  pass_criteria:" then "    exit_code: 0") — attribute the
    # child lines to pass_criteria so a threshold buried one level down is still fenced.
    inblock && /^[[:space:]]{6,}[a-z_]+:/ && last_fenced != "" {
      line = $0; sub(/^[[:space:]]+/, "", line); sub(/[[:space:]]+$/, "", line)
      print gate "\t" last_fenced ":" line
    }
    { if ($0 ~ /^[[:space:]]*(pass_criteria|thresholds|controls):/) { last_fenced = "pass_criteria" }
      else if ($0 ~ /^[[:space:]]{0,5}[a-z_]+:/) { last_fenced = "" } }
  ' | sort
}

before="$(ledger_at "$BEFORE_REF")" || { echo "ledger-fence: cannot read $LEDGER at $BEFORE_REF" >&2; exit 3; }
after="$(ledger_at "${AFTER_REF:-WORKTREE}")" || { echo "ledger-fence: cannot read $LEDGER at ${AFTER_REF:-the working tree}" >&2; exit 3; }

if [[ "$before" == "$after" ]]; then
  echo "ledger-fence: no fenced field changed"
  exit 0
fi

changed_gates="$(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") \
  | grep -E '^[<>]' | awk -F'\t' '{print $1}' | sed 's/^[<>] //' | sort -u)"

rc=0
while IFS= read -r gate; do
  [[ -n "$gate" ]] || continue
  # A corrections entry must name the gate AND say something. A bare heading is not a demonstration.
  entry=""
  if [[ -f "$CORRECTIONS" ]]; then
    entry="$(awk -v g="$gate" '
      $0 ~ ("^#+.*" g) { on = 1; buf = ""; next }
      on && /^#+ / { on = 0 }
      on { buf = buf $0 "\n" }
      END { print buf }' "$CORRECTIONS")"
  fi
  words="$(printf '%s' "$entry" | wc -w | tr -d ' ')"
  if [[ "$words" -lt 20 ]]; then
    echo "  BLOCKED  $gate — a fenced field changed with no corrections entry (found ${words} words under a heading naming it)"
    rc=1
  else
    echo "  allowed  $gate — covered by $CORRECTIONS (${words} words)"
  fi
done <<<"$changed_gates"

if [[ "$rc" -ne 0 ]]; then
  cat >&2 <<'EOF'

A gate's bar moved. That is allowed, but not silently: add an entry to
.gatesmith/CORRECTIONS.md with a heading naming the gate, and in it

  * what the criterion was, and what it is now;
  * the demonstration that the REFERENCE or BASELINE fails the same predicate — measured,
    on this machine, in this session;
  * why the new criterion is not simply the old one relaxed until the subject fit.

"The implementation is off and the gate wanted tighter" is a bug, not an over-specified gate.
EOF
fi
exit "$rc"
