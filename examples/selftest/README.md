# Gatesmith e2e self-test — example project

This directory is the **test subject** for Gatesmith's end-to-end self-test: a small
3-team build whose ledger exercises every feature (multi-owner hierarchy, cross-owner
dependencies, the ledger write-lock, remote-control Q&A, supersede, the loop, and —
in snapdir mode — content-addressed re-sync).

It is **not** a runnable project on its own; it ships only the subject-specific files:

```
.gatesmith/gates.yaml          # the 3-owner ledger (team-a / team-b / team-qa)
.gatesmith/templates/*.md      # lane templates (core / svc / qa)
core/ svc/ qa/                 # the production lanes (start empty)
docs/build-plan.md             # the locked plan ({{PLAN_DOC}})
```

## How the harness uses it

The deterministic bash tests in `../../test/e2e/` copy the ledger
(`fixtures/gates.seed.yaml`, a copy of this `gates.yaml`) into scratch repos with the
kit installed — you don't set anything up for those; just run `test/e2e/run.sh`.

For the **agent-driven** layers (a conductor actually building this project, and the
snapdir fleet ping-pong), see `../../test/e2e/agent/README.md`. The typical setup it
describes:

```sh
cp -R examples/selftest /tmp/gs-selftest && cd /tmp/gs-selftest
git init -q && git add -A && git commit -qm subject
/path/to/gatesmith/install.sh            # drops the kit (refuses if .gatesmith exists)
# then overlay this subject's ledger + templates over the freshly-installed scaffold
```

(Install into an empty dir first if `install.sh` refuses an existing `.gatesmith/`;
the agent README spells out the exact ordering.)
