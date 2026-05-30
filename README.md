# Gatesmith

> A Claude Code workflow that drives a build from a ledger of machine-checkable
> quality gates. A PM agent picks the next gate, spawns one lane-owner teammate
> per tick, re-runs the gate's verification, commits on pass, and loops until
> every gate passes.

You describe the work as a **ledger of quality gates** in `.gatesmith/gates.yaml`. The
PM agent picks the next unblocked gate, spawns the one teammate that owns it,
re-runs the gate's verification command, enforces a lane fence, commits on pass,
and journals the verdict. A ralph loop fires the PM tick repeatedly until every
gate passes.

## Prerequisites

- [Claude Code][cc]
- The `ralph-loop` Claude Code plugin (provides `/ralph-loop:ralph-loop` and
  `/ralph-loop:cancel-ralph`) — install it from your Claude Code plugin
  marketplace (`/plugin`)
- `git`

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

```
/ralph-loop:ralph-loop /gatesmith     # start the build loop
/ralph-loop:cancel-ralph              # stop (human owns end-of-project)
```

Each tick is one `/gatesmith` invocation. Watch progress in `.gatesmith/journal.md` and
`.gatesmith/state.md`.

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
| `depends_on` | gate ids that must be `passed` first |
| `status` | `pending` \| `failed` \| `passed` (PM mutates) |
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

## The lane fence

Teammates may edit only their own lane directory. Gatesmith enforces this *after
the fact* with `git diff --stat`, not with harness file-permission denies —
because spawned teammates inherit the same `settings.json` and hard denies would
block them from editing their own lane. If a teammate's diff strays out of lane,
the PM marks the gate failed and refuses to commit, leaving the diff for a human
to inspect.

## Layout

```
template/                     # copied into your project by install.sh
├── .gatesmith/
│   ├── PM_PROMPT.md           # the authoritative PM contract (fill in {{LANES}} etc.)
│   ├── gates.yaml             # the gate ledger (replace seed gates)
│   ├── state.md               # derived snapshot (PM re-projects each tick)
│   ├── journal.md             # append-only audit log
│   ├── evidence/              # captured verification output per tick
│   ├── handoff/               # teammate handoff files
│   └── templates/_lane.md     # generic lane template — copy per lane
└── .claude/
    ├── commands/gatesmith.md  # the /gatesmith slash command
    └── settings.json          # allowlist (add your build/test commands)

SETUP_PROMPT.md                # one-shot kick-off prompt to generate your ledger
install.sh                     # copies template/.gatesmith + template/.claude into $PWD
```

## License

MIT

[cc]: https://claude.com/claude-code
