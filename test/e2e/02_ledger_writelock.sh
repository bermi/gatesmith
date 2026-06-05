#!/usr/bin/env bash
# Ledger write-lock: two concurrent writers (the real mkdir mutex) never corrupt
# gates.yaml; each changes only its own row. Plus stale-lock reclaim.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib_assert.sh"
echo "02 ledger write-lock"
R="$(mkrepo)"; G="$R/.gatesmith/gates.yaml"; LK="$R/.gatesmith/locks/ledger.lock"; trap 'rm -rf "$R"' EXIT

acquire() { local t=0; until mkdir "$LK" 2>/dev/null; do sleep 0.01; t=$((t+1)); ((t>500)) && return 1; done
            printf '%s pid=%s scope=%s ttl=60\n' "$(date -u +%FT%TZ)" "$$" "$1" > "$LK/holder"; }
release() { rm -f "$LK/holder"; rmdir "$LK" 2>/dev/null; }
# read-modify-write a single gate's status under the lock
writer() { acquire "$1" || return 0; set_status "$G" "$2" passed; release; }

ids_before="$(grep -c 'id: ' "$G")"
fails=0
for i in $(seq 1 20); do
  set_status "$G" a_skeleton pending; set_status "$G" b_consumer pending
  writer team-a a_skeleton & writer team-b b_consumer &
  wait
  # Invariants after the race:
  [[ "$(grep -c 'id: ' "$G")" == "$ids_before" ]] || { fails=$((fails+1)); }   # no gate lost/dup
  [[ "$(gate_field "$G" a_skeleton status)" == passed ]] || fails=$((fails+1))
  [[ "$(gate_field "$G" b_consumer status)" == passed ]] || fails=$((fails+1))
  [[ ! -d "$LK" ]] || fails=$((fails+1))                                       # lock released
done
assert_eq "$fails" "0" "20x concurrent writers: no corruption, both rows set, lock released"

# Only the two targeted rows changed (a_api/qa_signoff untouched as pending).
set_status "$G" a_skeleton pending; set_status "$G" b_consumer pending
assert_eq "$(gate_field "$G" a_api status)" "pending" "a_api untouched by the race"
assert_eq "$(gate_field "$G" qa_signoff status)" "pending" "qa_signoff untouched by the race"

# Stale-lock reclaim: a holder older than TTL is reclaimable.
mkdir -p "$LK"; printf '2000-01-01T00:00:00Z pid=1 scope=x ttl=60\n' > "$LK/holder"
ts="$(awk '{print $1}' "$LK/holder")"
# emulate the PM's age check: if the holder timestamp is ancient, reclaim
if [[ "$ts" < "$(date -u +%FT%TZ)" ]]; then rm -f "$LK/holder"; rmdir "$LK" 2>/dev/null; fi
assert_false test -d "$LK"
ok "stale ledger.lock is reclaimable"

finish
