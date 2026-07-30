#!/usr/bin/env bash
# sabotage.sh — run a gate's sabotage controls and assert each one turns the gate RED.
#
#   .claude/gatesmith/sabotage.sh                 # every gate that declares controls
#   .claude/gatesmith/sabotage.sh <gate-id> ...   # only these gates
#   .claude/gatesmith/sabotage.sh --list          # what is declared, without running it
#
# THE PREMISE
#
#   A gate that has never been shown to fail is not evidence. An instrument that has silently
#   stopped measuring is indistinguishable from a clean result. So every gate carries a mutation
#   that MUST turn it red, and this script is what proves the mutation still does.
#
#   Controls rot. A refactor moves the code a mutation was aimed at, the patch lands on something
#   dead, and nothing goes red because nothing ran it. That is why this belongs INSIDE the suite —
#   `/gatesmith --sabotage` runs it as part of the tick, and the `sabotage_controls_all_red` meta
#   gate fails if a declared control was never executed. A control that only runs when someone
#   remembers is already stale.
#
# WHAT IT ASSERTS, PER CONTROL
#
#   1. THE PATCH LANDED.        `grep -c` of a unique marker in the file the build actually
#                               consumed. Never `diff`: an untracked new file produces no diff at
#                               all, and diff has been observed reporting "identical" while the
#                               edit was demonstrably present. Zero occurrences, or a build that
#                               fails, is SABOTAGE_DID_NOT_APPLY — a failure of the CONTROL.
#   2. SOMETHING MOVED.         The gate's own metrics (or its stdout) must differ from the clean
#                               run. This is a SEPARATE assertion from (1) and it is the one that
#                               catches an arithmetically inert mutation — `@max(1.0, x)` where
#                               `x >= 1` always applies, builds, counts its marker, and changes
#                               nothing. A marker count cannot see that. Status: INERT_MUTATION.
#   3. IT WENT RED.             Non-zero exit, or `verdict: FAIL` in the evidence envelope.
#   4. FOR THE RIGHT REASON.    If the gate emits named predicates, the expected one must be in
#                               failures(sabotaged) AND ABSENT from failures(clean). A gate already
#                               red for that reason cannot borrow its own defect as proof of
#                               sensitivity. Status: RED_FOR_THE_WRONG_REASON.
#
# WHY A SCRATCH TREE
#
#   `rsync -a` to a temp dir, patch there, build there, run there, delete it. The working tree is
#   never mutated: a mutation left behind by a crashed run is indistinguishable from a real defect.
#   The re-run also writes its evidence under `.gatesmith/evidence/_sabotage/`, so a sabotaged run
#   can never overwrite the canonical verdict it is being compared against — and the census in the
#   summary measures that rather than asserting it.
#
# STRENGTH LEVELS — this works on a ledger that has never heard of evidence envelopes
#
#   If the gate emits `.gatesmith/evidence/<gate>.json` with a `failures[].name` list, all four
#   assertions above apply. If it emits nothing, the differential falls back to the exit code and
#   the result records `strength: "exit-code-only"`. That is weaker — it cannot tell "red for the
#   right reason" from a coincidence — but it still catches the single biggest failure mode, a
#   gate that cannot fail at all. Adopt incrementally; the report never pretends the weak form is
#   the strong one.
#
# Exit: 0 every executed control went red for its reason · 1 at least one did not
#       3 the UNSABOTAGED scratch copy did not build or run (nothing below is about sabotage)

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

LEDGER=".gatesmith/gates.yaml"
CONTROLS_DIR=".gatesmith/controls"
EVIDENCE_DIR=".gatesmith/evidence"
OUT_DIR="$EVIDENCE_DIR/_sabotage"
EXCLUDES_FILE=".gatesmith/sabotage.excludes"

command -v jq >/dev/null 2>&1 || { echo "sabotage: jq is required" >&2; exit 3; }
command -v rsync >/dev/null 2>&1 || { echo "sabotage: rsync is required" >&2; exit 3; }
[[ -f "$LEDGER" ]] || { echo "sabotage: no $LEDGER" >&2; exit 3; }

LIST_ONLY=0
WANTED=()
for a in "$@"; do
  case "$a" in
    --list) LIST_ONLY=1 ;;
    -*) echo "sabotage: unknown flag $a" >&2; exit 2 ;;
    *) WANTED+=("$a") ;;
  esac
done

# gs_verification_cmd <gate-id> — pull one gate's verification_cmd out of the flat ledger.
# Deliberately a scoped scan rather than a YAML parser: gatesmith's prerequisites are git and jq,
# and adding a YAML dependency to run the controls would be a poor trade.
gs_verification_cmd() {
  awk -v want="$1" '
    /^[[:space:]]*-[[:space:]]*id:[[:space:]]*/ {
      id = $0; sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/, "", id)
      gsub(/^"|"$|[[:space:]]+$/, "", id)
      inblock = (id == want); next
    }
    inblock && /^[[:space:]]*verification_cmd:[[:space:]]*/ {
      line = $0; sub(/^[[:space:]]*verification_cmd:[[:space:]]*/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line ~ /^".*"$/) { line = substr(line, 2, length(line) - 2) }
      else if (line ~ /^'"'"'.*'"'"'$/) { line = substr(line, 2, length(line) - 2) }
      print line; exit
    }
  ' "$LEDGER"
}

# Every gate id in the ledger, in order — used to report gates that declare NO control at all.
gs_all_gate_ids() {
  sed -n 's/^[[:space:]]*-[[:space:]]*id:[[:space:]]*\(.*\)$/\1/p' "$LEDGER" \
    | sed 's/^"\(.*\)"$/\1/' | sed 's/[[:space:]]*$//'
}

# --- what is declared -------------------------------------------------------------------------
declare -a CONTROL_FILES=()
if [[ -d "$CONTROLS_DIR" ]]; then
  while IFS= read -r f; do CONTROL_FILES+=("$f"); done < <(find "$CONTROLS_DIR" -name '*.json' | sort)
fi

if [[ ${#WANTED[@]} -gt 0 ]]; then
  filtered=()
  for f in "${CONTROL_FILES[@]}"; do
    g="$(jq -r '.gate // ""' "$f" 2>/dev/null)"
    for w in "${WANTED[@]}"; do [[ "$g" == "$w" ]] && filtered+=("$f"); done
  done
  CONTROL_FILES=("${filtered[@]:-}")
  [[ -n "${CONTROL_FILES[0]:-}" ]] || CONTROL_FILES=()
fi

if [[ "$LIST_ONLY" -eq 1 ]]; then
  printf '%-34s %-38s %s\n' GATE CONTROL KIND
  for f in "${CONTROL_FILES[@]:-}"; do
    [[ -n "$f" ]] || continue
    jq -r '[.gate, .name, (.kind // "source-mutation")] | @tsv' "$f" \
      | awk -F'\t' '{printf "%-34s %-38s %s\n", $1, $2, $3}'
  done
  echo
  for g in $(gs_all_gate_ids); do
    n=0
    for f in "${CONTROL_FILES[@]:-}"; do
      [[ -n "$f" ]] || continue
      [[ "$(jq -r '.gate // ""' "$f")" == "$g" ]] && n=$((n + 1))
    done
    [[ "$n" -eq 0 ]] && echo "  NO CONTROL DECLARED: $g"
  done
  exit 0
fi

mkdir -p "$OUT_DIR"

# Custody: hash every canonical evidence file before the run, compare after. A sabotage re-run that
# overwrote a clean verdict would invalidate the very baseline it is measured against, so this is
# measured rather than assumed.
census_before="$(find "$EVIDENCE_DIR" -maxdepth 1 -name '*.json' -exec shasum -a 256 {} \; 2>/dev/null | sort)"

RSYNC_EXCLUDES=(--exclude '.git' --exclude 'node_modules' --exclude 'target'
                --exclude '.gatesmith/evidence' --exclude '.gatesmith/loops'
                --exclude '.gatesmith/locks')
if [[ -f "$EXCLUDES_FILE" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    RSYNC_EXCLUDES+=(--exclude "$line")
  done < "$EXCLUDES_FILE"
fi

# run_in <dir> <cmd> — run a gate's verification and capture exit, stdout, and its envelope.
# Echoes five US-separated fields: <exit> <stdout-sha> <verdict> <failures-csv> <metrics-sha>
#
# THE SEPARATOR IS ASCII UNIT SEPARATOR, NOT TAB, AND THAT IS NOT A STYLE CHOICE. Tab is an IFS
# WHITESPACE character, so `IFS=$'\t' read` collapses runs of it and drops empty fields — a clean
# run with no failures produced two adjacent tabs, every later field shifted left, and the metrics
# hash was read as the empty string. The visible symptom was every control reporting
# INERT_MUTATION: the comparison fell through to "no envelope, and stdout is identical", which is
# exactly what a gate that writes its result to a file and prints nothing looks like.
run_in() {
  local dir="$1" cmd="$2" gate="$3" out ec verdict fails metrics env_file
  out="$(cd "$dir" && eval "$cmd" 2>&1)"; ec=$?
  env_file="$dir/$EVIDENCE_DIR/$gate.json"
  verdict=""; fails=""; metrics=""
  if [[ -f "$env_file" ]]; then
    verdict="$(jq -r '.verdict // ""' "$env_file" 2>/dev/null)"
    fails="$(jq -r '[(.failures // [])[] | (.name // .)] | sort | join(",")' "$env_file" 2>/dev/null)"
    metrics="$(jq -cS '.metrics // {}' "$env_file" 2>/dev/null | shasum -a 256 | cut -d' ' -f1)"
  fi
  printf '%s\x1f%s\x1f%s\x1f%s\x1f%s' \
    "$ec" "$(printf '%s' "$out" | shasum -a 256 | cut -d' ' -f1)" "$verdict" "$fails" "$metrics"
}

total=0; red=0; bad=0
declare -a RESULTS=()

for f in "${CONTROL_FILES[@]:-}"; do
  [[ -n "$f" ]] || continue
  gate="$(jq -r '.gate' "$f")"
  name="$(jq -r '.name' "$f")"
  kind="$(jq -r '.kind // "source-mutation"' "$f")"
  expect="$(jq -r '.expect // ""' "$f")"
  marker="$(jq -r '.marker // ""' "$f")"
  tag="$(jq -r '.tag // (.name | gsub("[^A-Za-z0-9]+"; "-"))' "$f")"
  cmd="$(gs_verification_cmd "$gate")"
  total=$((total + 1))

  if [[ -z "$cmd" ]]; then
    RESULTS+=("$gate/$name|NO_SUCH_GATE|the ledger has no verification_cmd for this gate")
    bad=$((bad + 1)); continue
  fi

  scratch="$(mktemp -d)"
  trap 'rm -rf "$scratch"' EXIT
  rsync -a "${RSYNC_EXCLUDES[@]}" "$ROOT/" "$scratch/" 2>/dev/null
  mkdir -p "$scratch/$EVIDENCE_DIR"

  # --- the CLEAN baseline, measured on the scratch copy, not read from the working tree --------
  # A canonical envelope belongs to a tree that has since moved; the differential has to be
  # against the copy the mutation is actually applied to.
  IFS=$'\x1f' read -r b_ec b_out b_verdict b_fails b_metrics <<<"$(run_in "$scratch" "$cmd" "$gate")"
  if [[ "$b_ec" -ne 0 && "$kind" == "source-mutation" ]]; then
    RESULTS+=("$gate/$name|BASELINE_NOT_GREEN|the unsabotaged copy exits $b_ec; nothing below is about the sabotage")
    bad=$((bad + 1)); rm -rf "$scratch"; continue
  fi

  applied=1; marker_count=0
  if [[ "$kind" == "source-mutation" ]]; then
    while IFS= read -r edit; do
      ef="$(jq -r '.file' <<<"$edit")"
      find_s="$(jq -r '.find' <<<"$edit")"
      repl_s="$(jq -r '.replace' <<<"$edit")"
      want_n="$(jq -r '.count // 1' <<<"$edit")"
      target="$scratch/$ef"
      [[ -f "$target" ]] || { applied=0; break; }
      got_n="$(grep -F -c -- "$find_s" "$target" 2>/dev/null || true)"
      [[ "$got_n" -eq "$want_n" ]] || { applied=0; break; }
      FIND="$find_s" REPL="$repl_s" perl -0777 -i -pe \
        'BEGIN{$f=$ENV{FIND};$r=$ENV{REPL}} s/\Q$f\E/$r/g' "$target" 2>/dev/null || { applied=0; break; }
    done < <(jq -c '.edits[]' "$f")

    if [[ "$applied" -eq 1 && -n "$marker" ]]; then
      mf="$scratch/$(jq -r '.markerFile // .edits[0].file' "$f")"
      marker_count="$(grep -F -c -- "$marker" "$mf" 2>/dev/null || echo 0)"
      [[ "$marker_count" -ge 1 ]] || applied=0
    fi
  fi

  if [[ "$applied" -eq 0 ]]; then
    RESULTS+=("$gate/$name|SABOTAGE_DID_NOT_APPLY|marker=$marker_count — a sabotage that failed to apply and a sabotage the gate caught are the same observation, and neither is a control")
    bad=$((bad + 1)); rm -rf "$scratch"; continue
  fi

  # --- the sabotaged run ------------------------------------------------------------------------
  env_prefix=""
  while IFS= read -r kv; do env_prefix+="$kv "; done < <(jq -r '(.env // {}) | to_entries[] | "\(.key)=\(.value|@sh)"' "$f")
  IFS=$'\x1f' read -r s_ec s_out s_verdict s_fails s_metrics \
    <<<"$(run_in "$scratch" "${env_prefix}$cmd" "$gate")"
  rm -rf "$scratch"; trap - EXIT

  strength="exit-code-only"; [[ -n "$b_verdict" || -n "$s_verdict" ]] && strength="named-predicates"

  # (2) SOMETHING MOVED — separate from the marker count, and the assertion that catches an
  #     arithmetically inert mutation. Prefer the gate's own metrics; fall back to stdout.
  moved=1
  if [[ -n "$b_metrics" && "$b_metrics" == "$s_metrics" && "$b_out" == "$s_out" ]]; then moved=0; fi
  if [[ -z "$b_metrics" && "$b_out" == "$s_out" ]]; then moved=0; fi

  went_red=0
  [[ "$s_ec" -ne 0 || "$s_verdict" == "FAIL" ]] && went_red=1

  hit=1; absent_clean=1
  if [[ "$strength" == "named-predicates" && -n "$expect" ]]; then
    [[ ",$s_fails," == *",$expect,"* ]] || hit=0
    [[ ",$b_fails," == *",$expect,"* ]] && absent_clean=0
  fi

  if   [[ "$moved" -eq 0 ]]; then
    status=INERT_MUTATION
    detail="marker landed (${marker_count}) and the build consumed it, but no metric and no output changed — the patch applies and does nothing"
  elif [[ "$went_red" -eq 0 ]]; then
    status=STAYED_GREEN
    detail="the gate passed under the mutation (exit $s_ec, verdict ${s_verdict:-n/a})"
  elif [[ "$absent_clean" -eq 0 ]]; then
    status=PREDICATE_ALREADY_RED_WHEN_CLEAN
    detail="'$expect' is already in the clean failures; a gate cannot borrow its own defect as proof of sensitivity"
  elif [[ "$hit" -eq 0 ]]; then
    status=RED_FOR_THE_WRONG_REASON
    detail="expected '$expect', got '${s_fails:-<none>}'"
  else
    status=RED; red=$((red + 1))
    detail="exit $s_ec${expect:+, predicate $expect}"
  fi
  [[ "$status" == RED ]] || bad=$((bad + 1))

  jq -n --arg gate "$gate" --arg name "$name" --arg kind "$kind" --arg status "$status" \
        --arg expect "$expect" --arg strength "$strength" --arg detail "$detail" \
        --argjson marker_count "${marker_count:-0}" --argjson moved "$moved" \
        --arg clean_failures "$b_fails" --arg sabotaged_failures "$s_fails" \
        --argjson clean_exit "$b_ec" --argjson sabotaged_exit "$s_ec" \
    '{gate:$gate,name:$name,kind:$kind,status:$status,expectedPredicate:$expect,
      strength:$strength,detail:$detail,markerCount:$marker_count,observableMoved:($moved==1),
      cleanExit:$clean_exit,sabotagedExit:$sabotaged_exit,
      cleanFailures:$clean_failures,sabotagedFailures:$sabotaged_failures}' \
    > "$OUT_DIR/$gate.$tag.json"

  RESULTS+=("$gate/$name|$status|$detail")
done

# Gates with no control at all — a hole, reported by name rather than by absence. Scoped to the
# gates actually under test: a `sabotage.sh <gate>` run must not report every OTHER gate as
# uncontrolled, or the one honest signal here drowns in noise from gates nobody asked about.
no_control=()
for g in $(gs_all_gate_ids); do
  if [[ ${#WANTED[@]} -gt 0 ]]; then
    in_scope=0
    for w in "${WANTED[@]}"; do [[ "$g" == "$w" ]] && in_scope=1; done
    [[ "$in_scope" -eq 1 ]] || continue
  fi
  n=0
  for f in "${CONTROL_FILES[@]:-}"; do
    [[ -n "$f" ]] || continue
    [[ "$(jq -r '.gate // ""' "$f")" == "$g" ]] && n=$((n + 1))
  done
  [[ "$n" -eq 0 ]] && no_control+=("$g")
done

census_after="$(find "$EVIDENCE_DIR" -maxdepth 1 -name '*.json' -exec shasum -a 256 {} \; 2>/dev/null | sort)"
clobbered="[]"
[[ "$census_before" != "$census_after" ]] && clobbered='["canonical evidence changed during the sabotage run"]'

jq -n --argjson total "$total" --argjson red "$red" --argjson bad "$bad" \
      --argjson clobbered "$clobbered" \
      --argjson no_control "$(printf '%s\n' "${no_control[@]:-}" | jq -R . | jq -s 'map(select(. != ""))')" \
      --arg ranAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{kind:"sabotage-matrix",ranAt:$ranAt,controls_declared:$total,controls_red:$red,
    controls_failed:$bad,gates_declaring_no_control:$no_control,
    canonical_evidence_clobbered:$clobbered}' > "$OUT_DIR/_matrix.json"

for r in "${RESULTS[@]:-}"; do
  [[ -n "$r" ]] || continue
  IFS='|' read -r who st de <<<"$r"
  if [[ "$st" == RED ]]; then printf '  ok   %-52s %s\n' "$who" "$st"
  else printf '  BAD  %-52s %s\n       %s\n' "$who" "$st" "$de"; fi
done
for g in "${no_control[@]:-}"; do [[ -n "$g" ]] && printf '  BAD  %-52s NO_CONTROL_DECLARED\n' "$g"; done

echo
echo "$red/$total controls confirmed red; ${#no_control[@]} gate(s) declare none"
[[ "$bad" -eq 0 && "${#no_control[@]}" -eq 0 ]] && exit 0
exit 1
