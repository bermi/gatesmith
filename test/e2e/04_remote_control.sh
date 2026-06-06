#!/usr/bin/env bash
# Remote-control answer-drain state machine (the bash mirror of PM_PROMPT "Polling").
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib_assert.sh"
echo "04 remote-control"
R="$(mkrepo)"; G="$R/.gatesmith/gates.yaml"; Q="$R/.gatesmith/questions"; A="$R/.gatesmith/answers"; trap 'rm -rf "$R"' EXIT
mkdir -p "$Q" "$A"

# set/clear a gate's pending_question (insert/remove the line under the gate block)
set_pq() { local id="$1" uuid="$2" tmp="$G.tmp.$$"
  awk -v id="$id" -v u="$uuid" '
    $1=="-" && $2=="id:" { ingate=($3==id) }
    { print }
    ingate && $1=="status:" && u!="" { print "    pending_question: " u; ingate=0 }
  ' "$G" > "$tmp" && mv "$tmp" "$G"; }
clear_pq() { local id="$1" tmp="$G.tmp.$$"
  awk -v id="$id" '
    $1=="-" && $2=="id:" { ingate=($3==id) }
    ingate && $1=="pending_question:" { next }
    { print }
  ' "$G" > "$tmp" && mv "$tmp" "$G"; }

# drain_answer: apply the documented poll rules for one gate.
drain_answer() {
  local id="$1" cur ansfile uuid choice directive
  cur="$(gate_field "$G" "$id" pending_question)"
  [[ -n "$cur" ]] || return 0
  ansfile="$A/$cur.md"; [[ -f "$ansfile" ]] || return 0
  uuid="$cur"
  # stale-answer guard handled by caller (uuid is the gate's CURRENT pending_question)
  choice="$(grep -m1 '^choice:' "$ansfile" | sed 's/^choice: *//')"
  directive="$(grep -m1 '^directive:' "$ansfile" | sed 's/^directive: *//')"
  # malformed: choice must be one of A/B (the offered labels for this question)
  case "$choice" in A|B) : ;; *) echo "bad-answer $uuid"; return 0 ;; esac
  case "$directive" in
    pass) set_status "$G" "$id" passed; clear_pq "$id"; rm -f "$ansfile"; echo "answered $uuid pass" ;;
    fail) set_status "$G" "$id" failed; clear_pq "$id"; rm -f "$ansfile"; echo "answered $uuid fail" ;;
    *)    echo "bad-answer $uuid" ;;
  esac
}

UUID="11111111-1111-1111-1111-111111111111"
set_pq qa_signoff "$UUID"
printf 'uuid: %s\ngate: qa_signoff\noptions:\n  - label: A\n  - label: B\n' "$UUID" > "$Q/$UUID.md"

# valid answer -> consumed
printf 'choice: A\ndirective: pass\n' > "$A/$UUID.md"
drain_answer qa_signoff >/dev/null
assert_eq "$(gate_field "$G" qa_signoff status)" "passed" "valid answer passes the gate"
assert_eq "$(gate_field "$G" qa_signoff pending_question)" "" "pending_question cleared"
assert_false test -f "$A/$UUID.md"
ok "answer file consumed (deleted)"

# stale-uuid answer -> ignored (gate's pending_question differs)
UUID2="22222222-2222-2222-2222-222222222222"
set_status "$G" b_consumer pending
set_pq b_consumer "$UUID2"
STALE="33333333-3333-3333-3333-333333333333"
printf 'choice: A\ndirective: pass\n' > "$A/$STALE.md"
# the gate's current pending_question is UUID2, not STALE -> drain must not act on STALE
drain_answer b_consumer >/dev/null   # no answer file for UUID2 exists -> no-op
assert_eq "$(gate_field "$G" b_consumer status)" "pending" "stale-uuid answer does not pass the gate"
assert_true test -f "$A/$STALE.md"
ok "stale/orphan answer left untouched by the matching-uuid guard"

# malformed answer (bad choice) -> not consumed
rm -f "$A/$STALE.md"
printf 'choice: Z\ndirective: pass\n' > "$A/$UUID2.md"
out="$(drain_answer b_consumer)"
assert_eq "$(gate_field "$G" b_consumer status)" "pending" "malformed choice does not pass"
assert_eq "$(gate_field "$G" b_consumer pending_question)" "$UUID2" "pending_question kept for retry"
assert_true test -f "$A/$UUID2.md"
ok "malformed answer left in place for the controller to overwrite"

finish
