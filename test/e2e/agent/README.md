# Agent-driven e2e layer

These two checks need the `Agent` tool, so a Claude Code session drives them (a plain
`bash run.sh` can't spawn subagents). Run them from a Gatesmith session. Both use the
real `snapdir` binary (`${SNAPDIR_BIN:-snapdir}`).

## 1. Snapdir fleet ping-pong (peer re-sync via snapdir alone)

Goal: prove N independent "instances" converge by coordinating only through a shared
snapdir store — the "one session controls a fleet" demo.

Controller setup (do this once in the session):
```sh
ROOT=$(mktemp -d); export SNAPDIR_CACHE_DIR="$ROOT/cache"; mkdir -p "$SNAPDIR_CACHE_DIR"
STORE="file://$ROOT/store"; CAT=pingpong; LOCK="$ROOT/catalog.lock"
seed="$ROOT/seed"; mkdir -p "$seed"; printf 'seed\n' > "$seed/tally.txt"
mkdir "$LOCK"; "${SNAPDIR_BIN:-snapdir}" push "$seed" --store "$STORE" --catalog "$CAT"; rmdir "$LOCK"
```
Then spawn 2–3 subagents with `PINGPONG_PEER_PROMPT.md`, filling `{{PEER}}` (1,2,3),
`{{SNAPDIR_BIN}}`, `{{STORE}}`, `{{CAT}}`, `{{CACHE}}`, `{{WORKDIR}}` (`$ROOT/peer<N>`),
`{{LOCK}}`, `{{ROUNDS}}` (e.g. 3). After they return, assert (controller):
- `snapdir revisions --location $STORE --catalog $CAT | grep -c '"id"'` == `1 + peers*rounds`
- pull the latest id into a fresh dir; `snapdir id <fresh>` equals that latest id
- the fresh `tally.txt` contains every `round<r>-peer-<p>` line exactly once

The pure-bash equivalent (no LLM) is `../snapdir_pingpong.sh` — run it first to confirm
the mechanics, then the agent version to confirm instances can follow the protocol.

## 2. Conductor builds the self-test in snapdir mode

Goal: the conductor drives `examples/selftest` to `ALL OWNERS COMPLETE` as the sole
snapshot pusher.

Setup a scratch copy with the kit + the subject ledger:
```sh
W=$(mktemp -d); cp -R <repo>/examples/selftest/. "$W"/
( cd "$W" && git init -q )
# install the kit into an empty sibling, then copy the scaffold in (install.sh refuses
# an existing .gatesmith/), OR temporarily move the subject ledger aside:
mv "$W/.gatesmith" "$W/.gatesmith.subject"
( cd "$W" && <repo>/install.sh )
cp "$W/.gatesmith.subject/gates.yaml" "$W/.gatesmith/gates.yaml"
cp "$W/.gatesmith.subject/templates/"*.md "$W/.gatesmith/templates/"
cp -R "$W/.gatesmith.subject/." "$W/.gatesmith/"   # carry docs etc. if any
rm -rf "$W/.gatesmith.subject"
# fill {{LANES}}=core/ svc/ qa/, {{PLAN_DOC}}=docs/build-plan.md in .gatesmith/PM_PROMPT.md
STORE="file://$W/store"
```
From a session in `$W`, run `/gatesmith:conduct --snapdir-store $STORE --remote-control`.
Drive each round per `conduct.md`, spawning one `CONDUCTOR_WORKER_PROMPT.md` subagent
per owner with pickable work; reconcile + `snapdir push` between rounds. When
`qa_signoff` raises a question, drop `.gatesmith/answers/<uuid>.md` with
`choice: A` / `directive: pass`. (Optional: drive the supersede path by answering an
escalation with `directive: supersede` for `a_api` → `a_api_v2`.)

Final assertions (bash): pull the final canonical id into a fresh dir and check
`core/skeleton.txt`, `core/api.txt`, `svc/consumer.txt` exist; `gates.yaml` is all
`passed`/`superseded`; `snapdir id <fresh>` reproduces the conductor's last id.
