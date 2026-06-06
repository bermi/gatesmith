#!/usr/bin/env bash
# Loop lifecycle: drives the REAL setup-loop.sh / stop-hook.sh / cancel-loop.sh.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib_assert.sh"
echo "03 loop lifecycle"
R="$(mkrepo)"; GS="$R/.claude/gatesmith"; trap 'rm -rf "$R"' EXIT
cd "$R" || exit 1

# forge a transcript whose last assistant text block is $1
mk_tr() { local f="$R/tr.jsonl"
  printf '%s\n' '{"role":"user","message":{"content":[{"type":"text","text":"go"}]}}' > "$f"
  printf '{"role":"assistant","message":{"content":[{"type":"text","text":%s}]}}\n' "$(printf '%s' "$1" | jq -Rs .)" >> "$f"
  printf '%s' "$f"; }
hook() { printf '{"session_id":"%s","transcript_path":"%s"}' "$1" "$2" | bash "$GS/stop-hook.sh" 2>/dev/null; }

# acquire
CLAUDE_CODE_SESSION_ID=S1 bash "$GS/setup-loop.sh" team-a --max-iterations 5 >/dev/null 2>&1
assert_true test -f .gatesmith/loops/team-a.loop.md
assert_true test -f .gatesmith/locks/team-a.lock

# refuse-live (different session)
assert_false env CLAUDE_CODE_SESSION_ID=S2 bash "$GS/setup-loop.sh" team-a
ok "live lock refuses a different session"

# one-session-one-owner
assert_false env CLAUDE_CODE_SESSION_ID=S1 bash "$GS/setup-loop.sh" team-b
ok "one session cannot drive a second owner"

# stop-hook: no sentinel -> block + iterate
TR="$(mk_tr 'PM tick done, next gate is a_api')"
OUT="$(hook S1 "$TR")"
assert_eq "$(printf '%s' "$OUT" | jq -r '.decision' 2>/dev/null)" "block" "no sentinel -> decision=block"
assert_eq "$(grep '^iteration:' .gatesmith/loops/team-a.loop.md | tr -d ' ')" "iteration:2" "iteration incremented to 2"

# stop-hook: different session -> exit 0, no change
hook OTHER "$TR" >/dev/null 2>&1
assert_eq "$(grep '^iteration:' .gatesmith/loops/team-a.loop.md | tr -d ' ')" "iteration:2" "foreign session does not touch the loop"

# stop-hook: OWNER IDLE -> still block (continue polling)
OUT="$(hook S1 "$(mk_tr '===== OWNER IDLE: team-a remote-wait =====')")"
assert_eq "$(printf '%s' "$OUT" | jq -r '.decision' 2>/dev/null)" "block" "OWNER IDLE keeps the loop running"

# stop-hook: OWNER COMPLETE -> stop, remove state + lock
hook S1 "$(mk_tr 'all green
===== OWNER COMPLETE: team-a =====')" >/dev/null 2>&1
assert_false test -f .gatesmith/loops/team-a.loop.md
assert_false test -f .gatesmith/locks/team-a.lock
ok "OWNER COMPLETE removes loop state + lock"

# max-iterations stop
CLAUDE_CODE_SESSION_ID=S3 bash "$GS/setup-loop.sh" team-c --max-iterations 1 >/dev/null 2>&1
hook S3 "$(mk_tr 'still working')" >/dev/null 2>&1
assert_false test -f .gatesmith/loops/team-c.loop.md
ok "max-iterations reached stops the loop"

# stale-lock reclaim
CLAUDE_CODE_SESSION_ID=S4 bash "$GS/setup-loop.sh" team-d >/dev/null 2>&1
sed -i.bak 's/^heartbeat_epoch: .*/heartbeat_epoch: 100/' .gatesmith/locks/team-d.lock; rm -f .gatesmith/locks/team-d.lock.bak
assert_true env CLAUDE_CODE_SESSION_ID=S5 bash "$GS/setup-loop.sh" team-d
assert_eq "$(grep '^session_id:' .gatesmith/locks/team-d.lock | tr -d ' ')" "session_id:S5" "stale lock reclaimed by new session"

# cancel
CLAUDE_CODE_SESSION_ID=S5 bash "$GS/cancel-loop.sh" team-d >/dev/null 2>&1
assert_false test -f .gatesmith/loops/team-d.loop.md
ok "cancel removes the loop"

finish
