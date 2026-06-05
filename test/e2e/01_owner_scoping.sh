#!/usr/bin/env bash
# Owner scoping: cross-owner dependency resolution + per-owner write discipline.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib_assert.sh"
echo "01 owner scoping"
R="$(mkrepo)"; G="$R/.gatesmith/gates.yaml"; trap 'rm -rf "$R"' EXIT

# Cross-owner dep: b_consumer (team-b) depends on a_api (team-a).
assert_false pickable_for_owner "$G" b_consumer team-b   # a_api still pending -> blocked
ok "b_consumer blocked by cross-owner dep a_api (pending)"

# team-a advances a_skeleton then a_api.
set_status "$G" a_skeleton passed
set_status "$G" a_api passed
assert_true pickable_for_owner "$G" b_consumer team-b     # now the cross-owner dep is satisfied
ok "b_consumer becomes pickable once team-a's a_api passes"

# Owner filter: a_api is not pickable under the WRONG scope.
set_status "$G" a_api pending
assert_false pickable_for_owner "$G" a_api team-b
assert_true  pickable_for_owner "$G" a_api team-a

# Write discipline: a team-a write must not touch team-b's row.
before="$(gate_block "$G" b_consumer)"
set_status "$G" a_skeleton failed         # a team-a single-row edit
after="$(gate_block "$G" b_consumer)"
assert_eq "$after" "$before" "team-a write left b_consumer (team-b) byte-identical"

finish
