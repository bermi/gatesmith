#!/usr/bin/env bash
# Shared helpers for the vendored Gatesmith loop (setup-loop / cancel-loop / stop-hook).
# Sourced, not executed. All paths are relative to the repo root (the cwd Claude Code
# uses for slash commands and Stop hooks).

GATESMITH_LOOPS_DIR=".gatesmith/loops"
GATESMITH_LOCKS_DIR=".gatesmith/locks"
GATESMITH_DEFAULT_TTL=900   # per-owner lock liveness window, seconds (>= longest tick)

gs_now_iso()   { date -u +%Y-%m-%dT%H:%M:%SZ; }
gs_now_epoch() { date -u +%s; }
gs_hostname()  { hostname 2>/dev/null || echo unknown; }

# gs_field <file> <key> — read a flat "key: value" line, stripping surrounding quotes.
gs_field() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 0
  grep -m1 "^${key}:" "$file" 2>/dev/null | sed "s/^${key}: *//" | sed 's/^"\(.*\)"$/\1/'
}

# gs_fm_field <loop-state-file> <key> — read a key from the YAML frontmatter
# (between the first two --- lines) of a loop state file.
gs_fm_field() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 0
  sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$file" \
    | grep -m1 "^${key}:" | sed "s/^${key}: *//" | sed 's/^"\(.*\)"$/\1/'
}

# gs_lock_state <lockfile> — echoes none|stale|live.
# Liveness is purely TTL/heartbeat so it is host-agnostic (works across machines /
# worktrees). The Stop hook refreshes the heartbeat every tick; a lock whose
# heartbeat is older than its TTL is reclaimable. We deliberately do NOT key
# liveness on pid: the pid stored in the lock belongs to the short-lived setup
# script, not the long-running Claude session, so a pid check would mark every
# fresh lock dead. (pid/hostname are kept for forensics only.)
gs_lock_state() {
  local lockfile="$1" hb_epoch ttl now age
  [[ -f "$lockfile" ]] || { echo none; return 0; }
  hb_epoch="$(gs_field "$lockfile" heartbeat_epoch)"
  ttl="$(gs_field "$lockfile" ttl_seconds)"; ttl="${ttl:-$GATESMITH_DEFAULT_TTL}"
  if [[ ! "$hb_epoch" =~ ^[0-9]+$ ]]; then echo stale; return 0; fi
  now="$(gs_now_epoch)"; age=$(( now - hb_epoch ))
  if (( age < ttl )); then echo live; else echo stale; fi
}

# gs_atomic_create <target> <content> — exclusive create; 0 on success, 1 if it exists.
gs_atomic_create() {
  local target="$1" content="$2"
  ( set -o noclobber; printf '%s\n' "$content" > "$target" ) 2>/dev/null
}

# gs_lock_body <owner> — the contents of a per-owner lock file.
gs_lock_body() {
  local owner="$1"
  cat <<EOF
owner: $owner
session_id: ${CLAUDE_CODE_SESSION_ID:-}
pid: $$
hostname: $(gs_hostname)
started_at: "$(gs_now_iso)"
heartbeat: "$(gs_now_iso)"
heartbeat_epoch: $(gs_now_epoch)
ttl_seconds: ${GATESMITH_LOCK_TTL:-$GATESMITH_DEFAULT_TTL}
EOF
}

# gs_lock_refresh <lockfile> — bump the heartbeat (the reliable per-tick pulse).
gs_lock_refresh() {
  local lock="$1" tmp="${1}.tmp.$$"
  [[ -f "$lock" ]] || return 0
  sed -e "s/^heartbeat: .*/heartbeat: \"$(gs_now_iso)\"/" \
      -e "s/^heartbeat_epoch: .*/heartbeat_epoch: $(gs_now_epoch)/" \
      "$lock" > "$tmp" && mv "$tmp" "$lock"
}
