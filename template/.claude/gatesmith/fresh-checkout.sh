#!/usr/bin/env bash
# fresh-checkout.sh — does the suite pass for anyone but you?
#
#   .claude/gatesmith/fresh-checkout.sh              # untracked-input census only (fast)
#   .claude/gatesmith/fresh-checkout.sh --run "CMD"  # clone HEAD to a temp dir and run CMD there
#
# WHY THIS EXISTS, AND WHY IT IS NOT THE CONCURRENCY PROBLEM
#
#   A run in your working tree can be green because the tree hands it a file the REPOSITORY does not
#   have. Nothing about that run is wrong — the machine was quiet, the tree was yours, every custody
#   check held — and the result is still not a statement about the repository.
#
#   Observed: a control workload that one gate's whole correction rested on had never been
#   committed. Without it that gate reports "instrument unavailable", and because the sabotage
#   matrix re-runs each gate over a mutated copy, all five of its controls then reddened on the
#   MISSING WORKLOAD instead of on their own predicates — so the matrix failed, the meta-gate behind
#   it failed, and the freshness gate behind that failed. **One uncommitted file turned four lines
#   red everywhere except the machine that authored them**, and no working-tree run could have found
#   it, however careful.
#
#   This is a different failure from a second writer corrupting a run. Owning the tree does not
#   help; only tracking does.
#
# THE PREDICATE IS `--others --exclude-standard`, AND THE DISTINCTION MATTERS
#
#   Untracked-AND-NOT-IGNORED. A gitignored input is a DECISION — build output, generated evidence,
#   a large corpus deliberately kept out of git. An input that is neither tracked nor ignored is an
#   OVERSIGHT, and that is exactly the shape of the defect above. Flagging every ignored file would
#   bury the one that matters.
#
# Exit: 0 clean · 1 an untracked input, or the fresh-checkout run failed · 3 not a git repo

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

git rev-parse --git-dir >/dev/null 2>&1 || { echo "fresh-checkout: not a git repository" >&2; exit 3; }

ROOTS_FILE=".gatesmith/fresh-checkout.roots"
DEFAULT_ROOTS=(".claude/gatesmith" ".gatesmith/controls" ".gatesmith/gates.yaml")
ROOTS=()
if [[ -f "$ROOTS_FILE" ]]; then
  while IFS= read -r l; do
    [[ -z "$l" || "$l" == \#* ]] && continue
    ROOTS+=("$l")
  done < "$ROOTS_FILE"
else
  ROOTS=("${DEFAULT_ROOTS[@]}")
fi

rc=0

echo "== untracked inputs (neither tracked nor ignored) =="
loose="$(git ls-files --others --exclude-standard -- "${ROOTS[@]}" 2>/dev/null)"
if [[ -n "$loose" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    echo "  UNTRACKED  $f"
  done <<<"$loose"
  cat <<'EOF'

Every result that depended on one of these is a statement about this working tree, not about the
repository. Commit them, or gitignore them deliberately if they really are generated — but "neither"
is the state that produces a suite which is green only here.
EOF
  rc=1
else
  echo "  none under: ${ROOTS[*]}"
fi

# --run: the real thing. Clone HEAD somewhere else and see whether the suite still stands up.
if [[ "${1:-}" == "--run" ]]; then
  CMD="${2:-}"
  [[ -n "$CMD" ]] || { echo "fresh-checkout: --run needs a command" >&2; exit 3; }
  echo
  echo "== fresh checkout of HEAD =="
  scratch="$(mktemp -d)"
  trap 'rm -rf "$scratch"' EXIT
  if ! git clone --quiet --no-hardlinks --shared "$ROOT" "$scratch/repo" 2>/dev/null; then
    echo "  fresh-checkout: clone failed" >&2; exit 3
  fi
  ( cd "$scratch/repo" && git checkout --quiet --detach HEAD 2>/dev/null )
  echo "  running in $scratch/repo: $CMD"
  if ( cd "$scratch/repo" && eval "$CMD" ); then
    echo "  ok — the suite stands up in a checkout that has only what git has"
  else
    ec=$?
    echo "  FAILED (exit $ec) in a fresh checkout while presumably passing here." >&2
    echo "  That difference IS the finding. Compare what the working tree supplies that git does not." >&2
    rc=1
  fi
fi

exit "$rc"
