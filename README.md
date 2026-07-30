# Gatesmith

> A Claude Code workflow that drives a build from a ledger of machine-checkable
> quality gates. A PM agent picks the next gate, spawns one lane-owner teammate
> per tick, re-runs the gate's verification, commits on pass, and loops until
> every gate passes. Multiple teams/branches can build the same ledger in
> parallel, and the whole thing can run headlessly.

You describe the work as a **ledger of quality gates** in `.gatesmith/gates.yaml`. The
PM agent picks the next unblocked gate, spawns the one teammate that owns it,
re-runs the gate's verification command, enforces a lane fence, commits on pass,
and journals the verdict. A self-referential loop (vendored into the kit) fires the
PM tick repeatedly until every gate passes.

## Prerequisites

- [Claude Code][cc]
- `git`
- `jq` (used by the vendored loop's Stop hook)
- `snapdir` (optional — only for git-free "snapdir mode"; `cargo install snapdir-cli`)

The loop is built in — no external `ralph-loop` plugin needed.

## Install into a project

1. Copy the kit into the repo you want to build:

   ```sh
   git clone https://github.com/bermi/gatesmith ~/code/gatesmith   # once
   cd ~/your-project
   ~/code/gatesmith/install.sh                                     # drops .gatesmith/ + .claude/
   ```

2. Generate your gate ledger and lane templates: open the project in Claude
   Code and paste the filled-in kick-off prompt from
   **[SETUP_PROMPT.md](SETUP_PROMPT.md)** — it has a template plus worked
   examples for an API, a CLI, and a data pipeline.

3. Run the loop (below).

## Run it

Single-stream (no owners):

```
/gatesmith:loop                 # start the build loop in this session
/gatesmith:cancel _default      # stop (human owns end-of-project)
```

Multi-team / multi-branch — one loop per owner, on separate worktrees, terminals,
or machines:

```
# worktree / machine A
/gatesmith:loop team-a
# worktree / machine B
/gatesmith:loop team-b
```

Or drive several owners from a single session with the conductor:

```
/gatesmith:conduct              # spawns one tick per owner with work, reconciles the ledger
```

Each tick is one `/gatesmith [<owner>] [flags]` invocation. The loop is a Stop hook
(`.claude/gatesmith/stop-hook.sh`) that re-feeds the owner tick until that owner's
gates are all green (`===== OWNER COMPLETE: <owner> =====`). Watch progress in
`.gatesmith/journal.md` and `.gatesmith/state.md`.

### Parallel owners

A gate may carry an optional `owner` (team/branch), distinct from `owner_agent`
(the lane). A `/gatesmith <owner>` tick only picks and mutates gates whose `owner`
matches its scope, but `depends_on` always resolves against the **whole** ledger —
so `team-b`'s gate can depend on `team-a`'s and only becomes pickable once that gate
is `passed`. The single `gates.yaml` is the shared source of truth: each owner writes
only its own rows, under a short-lived `.gatesmith/locks/ledger.lock`, via
read-modify-write. The conductor (`/gatesmith:conduct`) is the cross-machine
reconciler. Per-owner loop locks (`.gatesmith/locks/<owner>.lock`, TTL/heartbeat
liveness) stop two processes from looping the same owner.

### Headless / remote control

Add `--remote-control` to any loop or tick to disable `AskUserQuestion`. Every human
question is written to `.gatesmith/questions/<uuid>.md` (with all options) and the PM
polls `.gatesmith/answers/<uuid>.md` each tick; the uuid is recorded on the gate and
in the journal. A gate awaiting an answer is skipped (it doesn't block other work).
Both dirs are gitignored. Drop an answer file (`choice:` + optional `directive:
pass|fail|retry|supersede`) to unblock it.

### Tick command hook

`--tick-cmd ./path` runs a repo-relative command before (`GATESMITH_TICK_PHASE=pre`)
and after (`=post`) each tick. The path must start with `./`, contain no `..`, and be
a tracked/executable file in the repo. Allowlist your command in `.claude/settings.json`
or unattended ticks stall on a permission prompt.

### Superseding a gate

Tell the PM (interactively, or with a `directive: supersede` answer in remote mode)
to supersede a gate: it marks the old gate `superseded`, appends your replacement gate
as `pending`, and repoints any dependents to the new id — letting you move on without
losing the audit trail.

### Snapdir mode (git-free)

For builds where git isn't available or wanted, run with `--snapdir-store
file:///abs/store` (or set `SNAPDIR_STORE`) to use [snapdir][sd] — BLAKE3
content-addressed directory snapshots — as the state/sync backend instead of git:

```
/gatesmith:loop team-a --snapdir-store file:///abs/store
/gatesmith:conduct     --snapdir-store file:///abs/store
```

In snapdir mode: the lane fence is a `snapdir manifest` diff (not `git diff`); RECORD
**pushes a snapshot** and records `snapdir_id` on the gate instead of committing a
`git_sha`; the ledger travels inside the snapshot, so state syncs without git; and the
conductor is the sole canonical pusher (cross-machine peers re-sync by pulling the
canonical id from the shared store). Pass `--snapdir-id <id>` to materialize a prior
snapshot at session start. Needs the `snapdir` binary (`cargo install snapdir-cli`, or
set `SNAPDIR_BIN=/abs/path`). A bundled **snapdir skill** (`.claude/skills/snapdir/`)
also teaches the model to inspect any snapshot id and to checkpoint/revert its own
state. Note: a snapshot captures the whole working dir — run from a dedicated project
dir, not `$HOME`.

[sd]: https://snapdir.org

## How a tick works

Every `/gatesmith` tick runs this contract (full text in `.gatesmith/PM_PROMPT.md`):

1. **READ STATE** — load `gates.yaml`, `state.md`, recent `journal.md`, git status; re-verify any frozen-interface SHA locks.
2. **PICK NEXT GATE** — `pending|failed` gates whose deps are all `passed`, sorted by (phase asc, failure_count desc, id asc). Head wins.
3. **CHECK ESCALATION** — `failure_count >= 3`, `human_checkpoint: true`, or a frozen-interface change proposal → ask the human via `AskUserQuestion` and exit.
4. **SPAWN TEAMMATE** — exactly one, from `.gatesmith/templates/<owner_agent>.md`, with the gate's fields substituted in.
5. **VERIFY** — lane fence (`git diff --stat` — every changed path must be in the teammate's lane), re-run `verification_cmd`, apply `pass_criteria`, capture evidence.
6. **RECORD** — append to `journal.md` first, then mutate `gates.yaml`, re-project `state.md`, and commit if the gate passed and the diff is in-lane.
7. **EXIT** — print a tick summary and the next likely gate.

The PM **never writes production code** and **spawns at most one teammate per
tick**. That single-writer rule plus the lane fence is what keeps an unattended
build from corrupting itself.

## The gate ledger

`.gatesmith/gates.yaml` is the single source of truth. Each gate:

| field | meaning |
|---|---|
| `id` | unique kebab-case identifier |
| `phase` | integer; lower phases run first |
| `owner_agent` | the lane that owns it → `.gatesmith/templates/<owner_agent>.md` |
| `owner` | optional team/branch that owns it (drives loop scoping); distinct from `owner_agent` |
| `depends_on` | gate ids that must be `passed` first (resolved across the whole ledger) |
| `status` | `pending` \| `failed` \| `passed` \| `superseded` (PM mutates) |
| `failure_count` | retries; `>= 3` escalates to the human |
| `verification_cmd` | shell command the PM re-runs from the repo root |
| `pass_criteria` | the DSL applied to the result (below) |
| `human_checkpoint` | `true` → PM asks the human before passing |
| `description` | one-line human summary |

### pass_criteria DSL

Use any one, or combine with `and:`:

```yaml
exit_code: 0
file_exists: path/to/file
files_exist: [a, b, c]
regex_match: "pattern"            # against stdout
json_path: ".metrics.score"       # with:
  op: ">="                        #   == != < <= > >=
  value: 20
human_confirm: "question for the human"
and: [ {exit_code: 0}, {file_exists: foo} ]
```

## Sabotage controls — proving a gate can fail

A gate that has never been shown to fail is not evidence. `pass_criteria: exit_code: 0` tells you a
command succeeded; it tells you nothing about whether that command *could* have failed. An
instrument that has silently stopped measuring is indistinguishable from a clean result.

So a gate may declare **sabotage controls**: concrete mutations to the real source that must turn it
red. `/gatesmith:sabotage` runs them.

```sh
.claude/gatesmith/sabotage.sh --list      # what is declared
.claude/gatesmith/sabotage.sh             # run them all
/gatesmith:sabotage --audit               # author the missing ones
```

Each control is `rsync`ed to a scratch copy, patched, built and run there, then deleted — the
working tree is never mutated. Four things are asserted, and they are deliberately separate:

1. **The patch landed** — a unique marker counted with `grep -c` in the file the build consumed.
   Never `diff`: an untracked new file produces no diff at all.
2. **Something moved** — the gate's own metrics, or its stdout, must differ from the clean run.
   This is what catches an *arithmetically inert* mutation: `max(1.0, x)` where `x >= 1` applies,
   builds, counts its marker, and changes nothing. A marker count cannot see that.
3. **It went red.**
4. **For the right reason** — the expected predicate must be in `failures(sabotaged)` and **absent
   from** `failures(clean)`. A gate already red for that reason cannot borrow its own defect as
   proof of sensitivity.

The statuses are the point. `RED` is the pass; `INERT_MUTATION`, `RED_FOR_THE_WRONG_REASON`,
`PREDICATE_ALREADY_RED_WHEN_CLEAN`, `SABOTAGE_DID_NOT_APPLY` and `NO_CONTROL_DECLARED` are five
distinct ways a control can be worthless while looking like one from a distance.

**It works on a ledger that has never heard of any of this.** With no evidence envelope the
differential falls back to the exit code and records `strength: "exit-code-only"` — weaker, but it
still catches the biggest failure mode, a gate that cannot fail at all. Gates that emit
`.gatesmith/evidence/<id>.json` with named `failures[]` get the full check. See
`.gatesmith/controls/README.md` for the envelope and the control format.

**Start by auditing what you already have.** `/gatesmith:sabotage --audit` walks the gates that
declare no control and asks the one useful question: can you make this fail on demand? The ones you
cannot are the real findings.

### Three verdicts, not two

A gate exits `0` (PASS), `1` (FAIL) or `3` (**UNTRACED** — the instrument could not be shown to be
working). UNTRACED is never counted as a pass and never as a failure: "the instrument was broken"
and "the subject was fine" are the same reading, and a gate that cannot see must not report a
colour.

### Rules the discipline depends on

- **Never weaken a threshold to go green.** To change any criterion, first demonstrate that the
  reference or baseline fails the same predicate, and record that demonstration — with the
  measurement — in `.gatesmith/CORRECTIONS.md`.
- **Whoever implements does not verify.** A lane may mutate its gate's `status`, not its
  `pass_criteria`.
- **When a control cannot be written as declared, say why in place.** A deleted declaration is an
  erased hole.
- **When a control refuses to go red, suspect the instrument before the code.** A gate can be
  structurally blind to its own subject — integrating a region no part of the defect falls inside,
  so the most drastic version of that defect leaves every metric identical.

## The lane fence

Teammates may edit only their own lane directory. Gatesmith enforces this *after
the fact* with `git diff --stat`, not with harness file-permission denies —
because spawned teammates inherit the same `settings.json` and hard denies would
block them from editing their own lane. If a teammate's diff strays out of lane,
the PM marks the gate failed and refuses to commit, leaving the diff for a human
to inspect.

## Layout

```
template/                          # copied into your project by install.sh
├── .gatesmith/
│   ├── PM_PROMPT.md                # the authoritative PM contract (fill in {{LANES}} etc.)
│   ├── gates.yaml                  # the gate ledger (replace seed gates)
│   ├── state.md                    # derived snapshot (PM re-projects each tick)
│   ├── journal.md                  # append-only audit log
│   ├── .gitignore                  # ignores loops/ locks/ questions/ answers/
│   ├── evidence/                   # captured verification output per tick
│   │   └── _sabotage/              # per-control results + _matrix.json summary
│   ├── controls/                   # sabotage controls: one JSON per control
│   ├── handoff/                    # teammate handoff files
│   ├── loops/ locks/               # runtime: loop state + per-owner/ledger locks (gitignored)
│   ├── questions/ answers/         # runtime: remote-control Q&A handoff (gitignored)
│   ├── work/                       # runtime: snapdir-mode per-owner checkouts (gitignored)
│   └── templates/_lane.md          # generic lane template — copy per lane
└── .claude/
    ├── commands/
    │   ├── gatesmith.md            # the /gatesmith tick command
    │   └── gatesmith/{loop,cancel,conduct,sabotage}.md  # /gatesmith:loop|cancel|conduct|sabotage
    ├── gatesmith/                  # vendored loop: stop-hook.sh, setup-loop.sh, cancel-loop.sh, lib.sh
    │                                 # plus sabotage.sh — the control runner
    ├── skills/snapdir/SKILL.md     # snapdir inspect / checkpoint-revert guide
    └── settings.json               # Stop hook + allowlist (add your build/test commands)

SETUP_PROMPT.md                     # one-shot kick-off prompt to generate your ledger
install.sh                          # copies the template into $PWD, chmods scripts, merges the Stop hook
```

## License

MIT

[cc]: https://claude.com/claude-code
