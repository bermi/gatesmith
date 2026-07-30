#!/usr/bin/env bash
# baseline.sh — the thing a gate compares against is an INPUT, and it must be pinned.
#
#   .claude/gatesmith/baseline.sh --verify          # does the baseline still match the lock?
#   .claude/gatesmith/baseline.sh --pin "reason"    # establish or move the lock, deliberately
#   .claude/gatesmith/baseline.sh --show            # what is locked, and what moved
#
# WHY THIS EXISTS
#
#   The discipline says: to change a criterion, first demonstrate that the reference fails the same
#   predicate. That makes the reference load-bearing — and a load-bearing input that nobody pinned
#   will drift, silently, and take every comparison with it.
#
#   Observed, not imagined. A project's golden reference was copied from a sibling checkout by a
#   sync script. Fifteen of its sixteen files came from a directory that was GITIGNORED upstream,
#   and the sixteenth came from whatever the upstream working tree happened to hold. A fresh sync
#   produced a different reference, and every comparison gate cascaded from one drift failure —
#   41 of 41 lines red, none of them about the subject. Worse, the pinned copy of that sixteenth
#   file existed in NO COMMIT of the upstream repository: it had been captured from a dirty working
#   tree and could never be fetched again. An oracle nobody can re-obtain is not a reference.
#
# WHAT IT LOCKS
#
#   `.gatesmith/baseline.lock.json` — the paths that make up the baseline, each file's sha256, a
#   digest over all of them, and where they came from. The digest covers the WHOLE set: a stray
#   file left behind by an older sync changes the baseline's identity even if nothing reads it.
#
#   ```json
#   { "source": { "repo": "../upstream", "commit": "c64015d…", "note": "read with git show" },
#     "paths": ["reference/"],
#     "digest": "…", "files": [{ "path": "reference/mod.js", "sha256": "…" }] }
#   ```
#
# WHY --pin REFUSES WITHOUT A REASON
#
#   Re-pinning to make a run go through is the one thing the lock exists to prevent. The reason is
#   recorded next to what moved, so "the baseline changed" and "somebody made the red go away" are
#   distinguishable afterwards by someone who was not there.
#
# Exit: 0 verified / pinned · 1 drift · 3 misconfigured

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

LOCK=".gatesmith/baseline.lock.json"
CORRECTIONS=".gatesmith/CORRECTIONS.md"

command -v jq >/dev/null 2>&1 || { echo "baseline: jq is required" >&2; exit 3; }

MODE="${1:---verify}"
REASON="${2:-}"

[[ -f "$LOCK" ]] || {
  cat >&2 <<EOF
baseline: no $LOCK

Nothing is pinned, so no gate here can claim its reference is stable. Create it with the paths that
make up your baseline (golden files, a vendored oracle, fixture corpora):

  jq -n '{source:{note:"where these came from, precisely enough to fetch again"},paths:["reference/"]}' > $LOCK
  .claude/gatesmith/baseline.sh --pin "initial pin"
EOF
  exit 3
}

mapfile -t PATHS < <(jq -r '.paths[]?' "$LOCK")
[[ ${#PATHS[@]} -gt 0 ]] || { echo "baseline: $LOCK declares no paths" >&2; exit 3; }

# The file census: every file under every declared path, sorted, with its sha256. Sorting is what
# makes the digest independent of filesystem order.
census() {
  local p
  for p in "${PATHS[@]}"; do
    if [[ -d "$p" ]]; then
      find "$p" -type f -print0 2>/dev/null | sort -z | while IFS= read -r -d '' f; do
        printf '%s %s\n' "$(shasum -a 256 "$f" | cut -d' ' -f1)" "$f"
      done
    elif [[ -f "$p" ]]; then
      printf '%s %s\n' "$(shasum -a 256 "$p" | cut -d' ' -f1)" "$p"
    fi
  done | sort -k2
}

now="$(census)"
[[ -n "$now" ]] || { echo "baseline: the declared paths contain no files — an empty baseline verifies against anything" >&2; exit 3; }
now_digest="$(printf '%s' "$now" | shasum -a 256 | cut -d' ' -f1)"
locked_digest="$(jq -r '.digest // ""' "$LOCK")"

case "$MODE" in
  --show)
    echo "locked digest : ${locked_digest:-<none>}"
    echo "current digest: $now_digest"
    jq -r '.source | to_entries[] | "source.\(.key): \(.value)"' "$LOCK" 2>/dev/null
    echo "files: $(printf '%s\n' "$now" | wc -l | tr -d ' ')"
    ;;

  --verify)
    if [[ -z "$locked_digest" ]]; then
      echo "baseline: $LOCK has no digest yet — run --pin \"reason\"" >&2; exit 3
    fi
    if [[ "$now_digest" == "$locked_digest" ]]; then
      echo "baseline: verified ($(printf '%s\n' "$now" | wc -l | tr -d ' ') files, $now_digest)"
      exit 0
    fi
    echo "baseline: DRIFT — $locked_digest (locked) != $now_digest (now)" >&2
    echo >&2
    echo "moved:" >&2
    diff <(jq -r '.files[]? | "\(.sha256) \(.path)"' "$LOCK" | sort -k2) <(printf '%s\n' "$now") \
      | grep -E '^[<>]' | sed 's/^/  /' >&2 || true
    cat >&2 <<'EOF'

Find out WHAT changed before re-pinning. If the file the comparisons are actually derived from has
moved, every captured expectation is stale and re-pinning turns a real regression into a green tick.
If only an unrelated neighbour moved, say so in the reason.

Do not re-pin to make a run go through. That is the one thing this lock exists to prevent.
EOF
    exit 1
    ;;

  --pin)
    if [[ -z "$REASON" ]]; then
      echo "baseline: --pin requires a reason, as its only argument in quotes." >&2
      echo "  A pin without a recorded reason is indistinguishable from making a red go away." >&2
      exit 3
    fi
    moved=""
    if [[ -n "$locked_digest" && "$locked_digest" != "$now_digest" ]]; then
      moved="$(diff <(jq -r '.files[]? | "\(.sha256) \(.path)"' "$LOCK" | sort -k2) <(printf '%s\n' "$now") \
        | grep -E '^>' | awk '{print $3}' | sort -u | tr '\n' ' ')"
    fi
    files_json="$(printf '%s\n' "$now" | awk '{printf "{\"path\":\"%s\",\"sha256\":\"%s\"}\n", $2, $1}' | jq -s .)"
    tmp="$(mktemp)"
    jq --arg d "$now_digest" --arg r "$REASON" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       --arg moved "$moved" --argjson f "$files_json" \
       '.digest=$d | .files=$f | .pinnedAt=$at | .reason=$r
        | .history = ((.history // []) + [{at:$at, digest:$d, reason:$r, moved:$moved}])' \
       "$LOCK" > "$tmp" && mv "$tmp" "$LOCK"
    echo "baseline: pinned $now_digest"
    [[ -n "$moved" ]] && echo "  moved: $moved"
    printf '\n## baseline re-pinned — %s\n\n%s\n\nDigest %s. Files that moved: %s\n' \
      "$(date -u +%Y-%m-%d)" "$REASON" "$now_digest" "${moved:-none}" >> "$CORRECTIONS"
    echo "  recorded in $CORRECTIONS"
    ;;

  *) echo "usage: baseline.sh [--verify|--pin \"reason\"|--show]" >&2; exit 3 ;;
esac
