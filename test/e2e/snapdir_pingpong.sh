#!/usr/bin/env bash
# Snapdir fleet ping-pong: N peers re-sync PURELY via a shared snapdir store.
# Proves the "fleet coordinates through snapdir alone" story. Skips if snapdir absent.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib_assert.sh"
echo "snapdir ping-pong"
if ! have_snapdir; then skip "snapdir not found (set SNAPDIR_BIN)"; finish; exit 0; fi

SD="$SNAPDIR_BIN"
ROOT="$(mktemp -d)"; trap "rm -rf '$ROOT'" EXIT
export SNAPDIR_CACHE_DIR="$ROOT/cache"; mkdir -p "$SNAPDIR_CACHE_DIR"   # OUTSIDE every workdir
STORE="file://$ROOT/store"; CAT=pingpong; LOCK="$ROOT/catalog.lock"
N=3; M=4   # peers, rounds

with_lock() { local t=0; until mkdir "$LOCK" 2>/dev/null; do sleep 0.02; t=$((t+1)); ((t>500)) && return 1; done
             "$@"; local rc=$?; rmdir "$LOCK"; return $rc; }
latest_id() { "$SD" revisions --location "$STORE" --catalog "$CAT" 2>/dev/null \
              | head -1 | grep -o '"id":"[0-9a-f]\{64\}"' | head -1 | cut -d'"' -f4; }

# seed
seed="$ROOT/seed"; mkdir -p "$seed"; printf 'seed\n' > "$seed/tally.txt"
with_lock "$SD" push "$seed" --store "$STORE" --catalog "$CAT" >/dev/null 2>&1

peer() {
  local pid="$1" r w lid
  for ((r=1; r<=M; r++)); do
    w="$ROOT/peer$pid"; rm -rf "$w"
    # one locked critical section: read latest -> pull -> append -> push
    with_lock bash -c '
      SD="$1"; STORE="$2"; CAT="$3"; w="$4"; pid="$5"; r="$6"
      lid="$("$SD" revisions --location "$STORE" --catalog "$CAT" 2>/dev/null | head -1 | grep -o "\"id\":\"[0-9a-f]\{64\}\"" | head -1 | cut -d\" -f4)"
      "$SD" pull "$w" --store "$STORE" --id "$lid" >/dev/null 2>&1
      printf "round%s-peer%s\n" "$r" "$pid" >> "$w/tally.txt"
      "$SD" push "$w" --store "$STORE" --catalog "$CAT" >/dev/null 2>&1
    ' _ "$SD" "$STORE" "$CAT" "$w" "$pid" "$r"
    sleep 0.0$((RANDOM % 5))
  done
}

for ((p=1; p<=N; p++)); do peer "$p" & done
wait

FINAL="$(latest_id)"
FRESH="$ROOT/fresh"; "$SD" pull "$FRESH" --store "$STORE" --id "$FINAL" >/dev/null 2>&1
assert_eq "$("$SD" id "$FRESH")" "$FINAL" "fresh pull of latest id reproduces the snapshot (content-addressed)"

revs="$("$SD" revisions --location "$STORE" --catalog "$CAT" 2>/dev/null | grep -c '"id"')"
assert_eq "$revs" "$((1 + N*M))" "one revision per push: seed + N*M contributions, no lost/dup"

# tally has every (round,peer) exactly once
need=$((N*M)); got=0
for ((r=1; r<=M; r++)); do for ((p=1; p<=N; p++)); do
  grep -qx "round$r-peer$p" "$FRESH/tally.txt" && got=$((got+1))
done; done
assert_eq "$got" "$need" "tally contains every round/peer contribution exactly once"

# chain integrity: every previous_id links to the next id, oldest is null
chain_ok=1
mapfile -t IDS < <("$SD" revisions --location "$STORE" --catalog "$CAT" 2>/dev/null | grep -o '"id":"[0-9a-f]\{64\}"' | cut -d'"' -f4)
mapfile -t PREVS < <("$SD" revisions --location "$STORE" --catalog "$CAT" 2>/dev/null | grep -o '"previous_id":\("[0-9a-f]\{64\}"\|null\)' | sed 's/"previous_id"://; s/"//g')
for ((i=0; i<${#IDS[@]}-1; i++)); do [[ "${PREVS[$i]}" == "${IDS[$((i+1))]}" ]] || chain_ok=0; done
[[ "${PREVS[-1]}" == "null" ]] || chain_ok=0
assert_eq "$chain_ok" "1" "revision chain is unbroken (previous_id links back to null)"

finish
