#!/usr/bin/env bash
# Supersede transaction: mark old superseded, append replacement, repoint dependents.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib_assert.sh"
echo "05 supersede"
R="$(mkrepo)"; G="$R/.gatesmith/gates.yaml"; trap 'rm -rf "$R"' EXIT

# supersede a_api -> a_api_v2 as one transaction (the documented protocol).
supersede() {
  local old="$1" new="$2" tmp="$G.tmp.$$"
  # id-collision guard
  if grep -q "id: $new$" "$G"; then echo "supersede-id-collision"; return 1; fi
  # 1+2: mark OLD superseded, add superseded_by; then append NEW gate.
  awk -v old="$old" -v new="$new" '
    $1=="-" && $2=="id:" { ingate=($3==old) }
    ingate && $1=="status:" { print "    status: superseded"; print "    superseded_by: " new; ingate=0; next }
    { print }
  ' "$G" > "$tmp"
  cat >> "$tmp" <<EOF

  - id: $new
    phase: 1
    owner_agent: core
    owner: team-a
    depends_on: [a_skeleton]
    status: pending
    failure_count: 0
    verification_cmd: "grep -q 'API v2' core/api.txt"
    pass_criteria:
      regex_match: "API v2"
    human_checkpoint: false
    description: "replacement for $old"
EOF
  mv "$tmp" "$G"
  # 3: repoint direct, non-superseded dependents old -> new
  local tmp2="$G.tmp2.$$"
  awk -v old="$old" -v new="$new" '
    $1=="-" && $2=="id:" { cur=$3; sup=0 }
    $1=="status:" && $2=="superseded" { sup=1 }
    {
      if ($1=="depends_on:" && sup==0) { gsub("\\[" old "\\]", "[" new "]"); gsub("(\\[|, )" old "(, |\\])", "&") }
      print
    }
  ' "$G" > "$tmp2" && mv "$tmp2" "$G"
}

before_qa="$(gate_block "$G" qa_signoff)"
supersede a_api a_api_v2 >/dev/null

assert_eq "$(gate_field "$G" a_api status)" "superseded" "old gate marked superseded"
assert_eq "$(gate_field "$G" a_api superseded_by)" "a_api_v2" "superseded_by points to replacement"
assert_eq "$(gate_field "$G" a_api_v2 status)" "pending" "replacement appended as pending"
assert_eq "$(gate_field "$G" a_api_v2 failure_count)" "0" "replacement starts at failure_count 0"
assert_eq "$(gate_field "$G" b_consumer depends_on)" "[a_api_v2]" "cross-owner dependent repointed to replacement"
assert_eq "$(gate_block "$G" qa_signoff)" "$before_qa" "unrelated gate (qa_signoff) untouched"

# id-collision rejected
assert_false supersede a_skeleton a_api_v2
ok "supersede with a colliding new id is rejected"

# dependent re-blocks: a_api_v2 is pending, so b_consumer is not pickable
assert_false pickable_for_owner "$G" b_consumer team-b
ok "dependent re-blocks until the replacement passes"

finish
