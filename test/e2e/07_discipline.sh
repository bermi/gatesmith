#!/usr/bin/env bash
# 07_discipline — the three fences that surround the sabotage controls.
#
#   ledger-fence.sh     a lane may move a gate's STATUS, never its BAR
#   baseline.sh         the thing a gate compares against is an input, and it must be pinned
#   fresh-checkout.sh   the suite must pass for someone who is not you
#
# Each is asserted BOTH ways. A fence that never blocks and a fence that always blocks are equally
# useless, and only checking both directions tells them apart — which is the same reason every gate
# here carries a sabotage control.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/lib_assert.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 1
git init -q . && git config user.email t@t && git config user.name t

mkdir -p .claude/gatesmith .gatesmith reference
cp "$TEMPLATE/.claude/gatesmith/ledger-fence.sh" \
   "$TEMPLATE/.claude/gatesmith/baseline.sh" \
   "$TEMPLATE/.claude/gatesmith/fresh-checkout.sh" .claude/gatesmith/
cp "$TEMPLATE/.gatesmith/CORRECTIONS.md" .gatesmith/
chmod +x .claude/gatesmith/*.sh

cat > .gatesmith/gates.yaml <<'EOF'
schema_version: 1
gates:
  - id: alpha
    status: pending
    failure_count: 0
    verification_cmd: "bash src/a.sh"
    pass_criteria:
      exit_code: 0
EOF
git add -A && git commit -qm init

# ---- ledger fence: status may move, the bar may not -------------------------------------------
sed -i.bak 's/status: pending/status: passed/' .gatesmith/gates.yaml && rm -f .gatesmith/gates.yaml.bak
assert_true bash .claude/gatesmith/ledger-fence.sh
git checkout -q -- .gatesmith/gates.yaml

sed -i.bak 's|verification_cmd: "bash src/a.sh"|verification_cmd: "true"|' .gatesmith/gates.yaml && rm -f .gatesmith/gates.yaml.bak
assert_false bash .claude/gatesmith/ledger-fence.sh

# ...and a corrections entry naming the gate unblocks it.
cat >> .gatesmith/CORRECTIONS.md <<'EOF'

## alpha — verification_cmd replaced

The reading that was red: alpha failed on a harness defect, not on its subject. Driving the
reference through the same instrument at the same inputs showed the reference failing the identical
predicate, worse, which is what put the criterion itself in question rather than the subject.
EOF
assert_true bash .claude/gatesmith/ledger-fence.sh
git checkout -q -- .gatesmith/gates.yaml

# ---- baseline: verify, drift, refuse to re-pin without a reason -------------------------------
echo "golden" > reference/oracle.txt
jq -n '{source:{note:"fixture"},paths:["reference/"]}' > .gatesmith/baseline.lock.json
assert_true bash .claude/gatesmith/baseline.sh --pin "initial pin for the fixture"
assert_true bash .claude/gatesmith/baseline.sh --verify

echo "drifted" > reference/oracle.txt
assert_false bash .claude/gatesmith/baseline.sh --verify
assert_false bash .claude/gatesmith/baseline.sh --pin          # a pin with no reason is refused
assert_true  bash .claude/gatesmith/baseline.sh --pin "upstream moved; only oracle.txt changed"
assert_true  bash .claude/gatesmith/baseline.sh --verify
assert_true grep -q "upstream moved" .gatesmith/CORRECTIONS.md

# A stray file changes the baseline's identity even though nothing reads it — the digest covers the
# whole set on purpose, because a leftover from an older sync is exactly how a reference rots.
echo "leftover" > reference/stray.txt
assert_false bash .claude/gatesmith/baseline.sh --verify
rm -f reference/stray.txt

# ---- fresh checkout: untracked-and-not-ignored is the predicate -------------------------------
git add -A && git commit -qm baseline
assert_true bash .claude/gatesmith/fresh-checkout.sh

echo "#!/bin/sh" > .claude/gatesmith/helper.sh      # neither tracked nor ignored → an oversight
assert_false bash .claude/gatesmith/fresh-checkout.sh

printf '.claude/gatesmith/helper.sh\n' > .gitignore  # ignored deliberately → a decision, allowed
assert_true bash .claude/gatesmith/fresh-checkout.sh
rm -f .claude/gatesmith/helper.sh .gitignore

# --run actually executes in a clone of HEAD, and reports a command that only works here.
mkdir -p src && echo 'exit 0' > src/a.sh && git add -A && git commit -qm src
assert_true  bash .claude/gatesmith/fresh-checkout.sh --run "test -f src/a.sh"
echo 'exit 0' > src/uncommitted.sh                  # present here, absent from HEAD
assert_false bash .claude/gatesmith/fresh-checkout.sh --run "test -f src/uncommitted.sh"

finish
