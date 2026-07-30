#!/usr/bin/env bash
# 06_sabotage — the sabotage runner must distinguish the five ways a control can be worthless.
#
# This is the test the feature exists for. It is not enough that a control "goes red": the runner
# has to tell apart a control that works from four impostors that all look like one from a
# distance. Each case below is a real defect observed in practice, not a hypothetical:
#
#   RED                        the control works
#   INERT_MUTATION             the patch applies, the marker counts, and NOTHING changes
#   RED_FOR_THE_WRONG_REASON   it reddens on a different predicate — a coincidence, not a control
#   SABOTAGE_DID_NOT_APPLY     the find string matched nothing
#   NO_CONTROL_DECLARED        the gate is unfalsifiable
#
# INERT_MUTATION is the one a marker count cannot catch and the reason `sabotage.sh` asserts
# "something moved" separately from "the patch landed".
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/lib_assert.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 1
git init -q . 2>/dev/null

mkdir -p src .claude/gatesmith .gatesmith/evidence \
         .gatesmith/controls/{works,inert,wrong,nomatch}
cp "$TEMPLATE/.claude/gatesmith/sabotage.sh" .claude/gatesmith/
chmod +x .claude/gatesmith/sabotage.sh

# A subject that emits a real evidence envelope with NAMED predicates.
cat > src/check.sh <<'EOF'
#!/usr/bin/env bash
mkdir -p .gatesmith/evidence
V=7
W=3
fails='[]'
[ "$V" -lt 10 ] || fails=$(echo "$fails" | jq '. + [{"name":"value-over-limit"}]')
[ "$W" -lt 5 ]  || fails=$(echo "$fails" | jq '. + [{"name":"width-over-limit"}]')
verdict=PASS; [ "$(echo "$fails" | jq 'length')" -eq 0 ] || verdict=FAIL
jq -n --arg v "$verdict" --argjson f "$fails" --argjson val "$V" --argjson w "$W" \
  '{verdict:$v,failures:$f,metrics:{value:$val,width:$w}}' > .gatesmith/evidence/GATE.json
[ "$verdict" = PASS ]
EOF

for g in works inert wrong nomatch; do
  sed "s/GATE/$g/" src/check.sh > "src/$g.sh"
done
cat > .gatesmith/gates.yaml <<'EOF'
schema_version: 1
gates:
  - id: works
    verification_cmd: "bash src/works.sh"
  - id: inert
    verification_cmd: "bash src/inert.sh"
  - id: wrong
    verification_cmd: "bash src/wrong.sh"
  - id: nomatch
    verification_cmd: "bash src/nomatch.sh"
  - id: bare
    verification_cmd: "true"
EOF

ctl() { # ctl <gate> <name> <expect> <find> <replace> <marker>
  jq -n --arg g "$1" --arg n "$2" --arg e "$3" --arg f "$4" --arg r "$5" --arg m "$6" --arg file "src/$1.sh" \
    '{gate:$g,name:$n,tag:$n,expect:$e,marker:$m,edits:[{file:$file,find:$f,replace:$r,count:1}]}' \
    > ".gatesmith/controls/$1/$2.json"
}
ctl works   c-works   value-over-limit 'V=7'  'V=99'     'V=99'
# Raising a limit that never binds: applies, builds, marker counts 1, changes nothing.
ctl inert   c-inert   value-over-limit '-lt 10' '-lt 999999' '999999'
# Breaks a DIFFERENT predicate than the one it claims.
ctl wrong   c-wrong   value-over-limit 'W=3'  'W=99'     'W=99'
# `find` matches nothing in the file.
ctl nomatch c-nomatch value-over-limit 'V=12345' 'V=99'  'V=99'

out="$(bash .claude/gatesmith/sabotage.sh 2>&1)"; rc=$?
status_of() { grep -F "$1/" <<<"$out" | awk '{print $3}' | head -1; }

assert_eq "$(status_of works)"   RED                      "a working control reports RED"
assert_eq "$(status_of inert)"   INERT_MUTATION           "an inert mutation is caught despite marker count 1"
assert_eq "$(status_of wrong)"   RED_FOR_THE_WRONG_REASON "reddening on another predicate is not a control"
assert_eq "$(status_of nomatch)" SABOTAGE_DID_NOT_APPLY   "a patch that matches nothing fails the CONTROL"
assert_true grep -q "bare .*NO_CONTROL_DECLARED" <<<"$out"
assert_eq "$rc" 1 "the matrix exits non-zero when any control is worthless"

# The working tree must be untouched — mutations happen in a scratch copy or not at all.
assert_true grep -q 'V=7' src/works.sh

# The sabotaged re-runs must not have overwritten canonical evidence.
assert_eq "$(jq -r '.canonical_evidence_clobbered | length' .gatesmith/evidence/_sabotage/_matrix.json)" \
  0 "canonical evidence was not clobbered by the sabotage runs"

# And a scoped run must not slander the gates it was not asked about.
scoped="$(bash .claude/gatesmith/sabotage.sh works 2>&1)"
assert_false grep -q "NO_CONTROL_DECLARED" <<<"$scoped"

finish
