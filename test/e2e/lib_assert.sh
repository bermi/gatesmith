#!/usr/bin/env bash
# Shared helpers for the Gatesmith e2e bash harness. Sourced by each test.
# Tests create their own mktemp scratch repos and clean up on EXIT.

# Repo paths (this file lives at <repo>/test/e2e/lib_assert.sh).
E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$E2E_DIR/../.." && pwd)"
TEMPLATE="$REPO_ROOT/template"
SEED="$E2E_DIR/fixtures/gates.seed.yaml"
SNAPDIR_BIN="${SNAPDIR_BIN:-snapdir}"

PASS=0; FAILN=0; SKIPN=0
ok()   { PASS=$((PASS+1));   printf '  ok:   %s\n' "$1"; }
fail() { FAILN=$((FAILN+1)); printf '  FAIL: %s\n' "$1"; }
skip() { SKIPN=$((SKIPN+1)); printf '  skip: %s\n' "$1"; }

# assert_eq <actual> <expected> <msg>
assert_eq() { [[ "$1" == "$2" ]] && ok "$3" || fail "$3 (got '$1' want '$2')"; }
# assert_true <cmd...> — passes if the command exits 0
assert_true()  { if "$@" >/dev/null 2>&1; then ok "$*"; else fail "$*"; fi; }
assert_false() { if "$@" >/dev/null 2>&1; then fail "NOT($*)"; else ok "NOT($*)"; fi; }

finish() {
  printf '  --- %d ok, %d failed, %d skipped\n' "$PASS" "$FAILN" "$SKIPN"
  [[ $FAILN -eq 0 ]]
}

have_snapdir() { command -v "$SNAPDIR_BIN" >/dev/null 2>&1 || [[ -x "$SNAPDIR_BIN" ]]; }

# mkrepo — create a scratch git repo with the kit installed + the seed ledger.
# Echoes the repo path. The CALLER owns cleanup, e.g.:
#     R="$(mkrepo)"; trap 'rm -rf "$R"' EXIT
# (Do NOT trap inside mkrepo — it runs in a command-substitution subshell whose
# exit would delete the repo before the test ever uses it.)
mkrepo() {
  local d; d="$(mktemp -d)"
  cp -R "$TEMPLATE/.gatesmith" "$d/.gatesmith"
  mkdir -p "$d/.claude"
  cp -R "$TEMPLATE/.claude/." "$d/.claude/"
  chmod +x "$d/.claude/gatesmith/"*.sh
  mkdir -p "$d/.gatesmith/"{loops,locks,questions,answers,work}
  cp "$SEED" "$d/.gatesmith/gates.yaml"
  ( cd "$d" && git init -q && git config user.email t@t.t && git config user.name t \
      && git add -A && git commit -qm bootstrap ) >/dev/null 2>&1
  printf '%s' "$d"
}

# gate_field <gates.yaml> <gate-id> <field> — read a scalar field from one gate block.
gate_field() {
  local file="$1" id="$2" field="$3"
  awk -v id="$id" -v f="$field" '
    $1=="-" && $2=="id:" { ingate = ($3==id) }
    ingate && $1==f":" { sub(/^[^:]*: */,""); gsub(/^"|"$/,""); print; exit }
  ' "$file"
}

# gate_block <gates.yaml> <gate-id> — print one gate's block (its `- id:` line
# through the line before the next gate). Used to assert other rows stay untouched.
gate_block() {
  local file="$1" id="$2"
  awk -v id="$id" '
    $1=="-" && $2=="id:" { if (ingate) exit; ingate = ($3==id) }
    ingate { print }
  ' "$file"
}

# set_status <gates.yaml> <gate-id> <new-status> — targeted single-row read-modify-write
# (mirrors the PM RECORD rule: change only this gate's status line).
set_status() {
  local file="$1" id="$2" ns="$3" tmp="$1.tmp.$$"
  awk -v id="$id" -v ns="$ns" '
    $1=="-" && $2=="id:" { ingate = ($3==id) }
    ingate && $1=="status:" { sub(/status:.*/, "status: " ns); ingate=0 }
    { print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

# deps_passed <gates.yaml> <gate-id> — 0 if every depends_on gate is `passed`.
deps_passed() {
  local file="$1" id="$2" raw d
  raw="$(gate_field "$file" "$id" depends_on)"; raw="${raw#[}"; raw="${raw%]}"
  [[ -z "${raw// /}" ]] && return 0
  local arr; IFS=', ' read -ra arr <<<"$raw"
  for d in "${arr[@]}"; do
    [[ -z "$d" ]] && continue
    [[ "$(gate_field "$file" "$d" status)" == passed ]] || return 1
  done
  return 0
}

# pickable_for_owner <gates.yaml> <gate-id> <owner> — 0 if the PM would pick this gate
# under scope <owner> (status pending|failed, owner match, deps passed, no open question).
pickable_for_owner() {
  local file="$1" id="$2" owner="$3" st q
  st="$(gate_field "$file" "$id" status)"
  [[ "$st" == pending || "$st" == failed ]] || return 1
  [[ "$(gate_field "$file" "$id" owner)" == "$owner" ]] || return 1
  q="$(gate_field "$file" "$id" pending_question)"; [[ -n "$q" ]] && return 1
  deps_passed "$file" "$id"
}
