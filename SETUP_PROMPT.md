# Gatesmith setup prompt

A generalized version of the prompt that generates a project's gate ledger and
lane templates. Fill in the angle-bracket blanks, paste it into a Claude Code
session at the root of your project, and let it plan.

---

> I'd like to build **\<PROJECT GOAL — one or two sentences\>**.
>
> Constraints / stack / context: **\<languages, frameworks, hard requirements,
> non-goals; link a spec doc with `@path/to/spec.md` if you have one\>**.
>
> Please **ultrathink** and plan this to execute with teammates: a master
> **project-manager (PM) agent** designs machine-checkable **quality gates** and
> verifies what teammates do against them. Each gate names the lane that owns it,
> its dependencies, a `verification_cmd`, and `pass_criteria`. The PM spawns
> exactly one lane-owner teammate per tick, re-runs the verification itself,
> enforces a lane fence (`git diff --stat` — teammates may only touch their own
> lane directory), commits on pass, and journals every verdict. The whole project
> is controlled through a **ralph loop** from architecture to prototype until
> production quality is reached.
>
> Use the **Gatesmith** kit that's already installed in this repo:
> - Fill in the `{{LANES}}`, `{{PLAN_DOC}}`, and `{{FROZEN}}` placeholders in
>   `.pm/PM_PROMPT.md` for this project.
> - Replace the seed gates in `.pm/gates.yaml` with a real, phased,
>   dependency-ordered ledger covering the whole build (bootstrap → prototype →
>   hardening → ship). Mark human-judgment gates with `human_checkpoint: true`.
> - For each lane, copy `.pm/templates/_lane.md` to `.pm/templates/<lane>.md` and
>   write that lane's style discipline (idioms, allowed/banned APIs, testing,
>   reuse expectations).
> - Add this project's build/test/run commands to `.claude/settings.json` so
>   unattended ticks don't stall on permission prompts.
> - Write the locked architecture/build plan to the `{{PLAN_DOC}}` path.
>
> When the ledger and templates are ready, I'll start the build with:
>
> ```
> /ralph-loop:ralph-loop /gatesmith
> ```

---

## Examples

You only write two blanks: the **goal** and the **constraints/context**.
Everything else is fixed. The generated `gates.yaml` is only as good as those
two blanks, so state three things concretely: the **lanes** (one directory per
owner), any **frozen contract** between lanes, and what **"done"** means —
including which gates need a human to eyeball the result.

### A REST API + web dashboard

> I'd like to build a self-hosted bookmark manager: a JSON REST API and a small
> web dashboard to add, tag, and full-text-search bookmarks.
>
> Constraints: Go for the API, Postgres for storage, a Svelte single-page
> frontend, local accounts only (no external auth provider). Lanes: `api/` (Go
> service + migrations), `web/` (Svelte app), `e2e/` (Playwright tests). The
> OpenAPI spec at `api/openapi.yaml` is the contract between `api/` and `web/` —
> freeze it once phase 1 passes so the frontend builds against a stable schema.
> Done: `go test ./...` green, the Playwright suite passes against a running
> stack, and I can add/search/tag a bookmark in the browser (human checkpoint).

### A single-binary CLI

> I'd like to build `lh`, a CLI that tails and filters structured (JSON) log
> streams with a query like `level>=warn and service=api`.
>
> Constraints: one statically-linked Rust binary, no runtime deps, reads from
> stdin or a file. Lanes: `src/` (parser + filter engine + CLI), `tests/`
> (integration fixtures), `man/` (man page + README usage). The grammar in
> `src/grammar.pest` is the spec — freeze it after phase 1. Done: `cargo test`
> green, `cargo build --release` produces a binary under 5 MB, and `lh --help`
> plus three documented example queries run against `tests/fixtures/sample.log`.

### An offline data pipeline

> I'd like to build a pipeline that turns a folder of PDFs into a searchable
> embedding index.
>
> Constraints: Python with uv, no cloud calls — a local embedding model only.
> Lanes: `ingest/` (PDF → text chunking), `embed/` (model worker), `index/`
> (vector store + query API), `qa/` (eval scripts). The chunk-record schema in
> `index/schema.json` is frozen after phase 2 so `ingest/` and `index/` stay
> compatible. Done: `uv run pytest` green, a benchmark in `qa/` reports
> recall@10 ≥ 0.8 on the labeled query set in `qa/eval/`, and querying "refund
> policy" returns the expected document (human checkpoint).

---

## After planning

1. Review the generated `.pm/gates.yaml` — this *is* your project plan. If the
   gates are right, the build will be right.
2. Make the bootstrap commit (just `.pm/`, `.claude/`, and your build-tool files).
3. Run `/ralph-loop:ralph-loop /gatesmith` and watch `.pm/journal.md` fill in.
4. Stop any time with `/ralph-loop:cancel-ralph`; resume by running the loop again.
