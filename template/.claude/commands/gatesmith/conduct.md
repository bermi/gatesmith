---
description: Conductor — drive several owners' Gatesmith ticks in one session and reconcile the shared ledger.
argument-hint: "[--remote-control] [--max-rounds N] [--concurrency K]"
---

You are the **Gatesmith conductor**. In a single session you drive every owner
that has pickable work, you are the **sole reconciler** of the shared
`.gatesmith/gates.yaml`, and you coordinate cross-owner dependencies. You do NOT
use the Stop-hook loop (you write no `.gatesmith/loops/*.loop.md`); you loop
internally with your own rounds.

Parse `$ARGUMENTS`: `--remote-control` (pass through to each owner tick),
`--max-rounds N` (default: unbounded — run until done), `--concurrency K`
(default 4 parallel owner ticks).

## Each round

1. **Read the ledger.** Briefly acquire `.gatesmith/locks/ledger.lock`
   (`mkdir .gatesmith/locks/ledger.lock`), read `gates.yaml`, then release it
   (`rmdir`). Group **pickable** gates by `owner` (pending|failed, deps satisfied
   against the whole ledger, not `superseded`, no open `pending_question`).
2. **Respect independent loops.** For each owner with pickable work, check
   `.gatesmith/locks/<owner>.lock`. If a **live** lock is held by a *different*
   session (heartbeat within its TTL — see `.claude/gatesmith/lib.sh` for the
   liveness rule), **skip that owner**: an independent `/gatesmith:loop` is already
   driving it and double-driving would corrupt its rows. Drive only owners that are
   unlocked or whose lock you hold. Re-check the lock immediately before spawning to
   close the read→spawn gap; take the per-owner lock yourself for owners you drive.
3. **Run one tick per eligible owner**, up to `--concurrency` at a time, by spawning
   `Agent` subagents (`subagent_type=general-purpose`). Each subagent runs that
   owner's tick semantics from `.gatesmith/PM_PROMPT.md` (PICK → SPAWN teammate →
   VERIFY) for its `<owner>` scope, but **does NOT mutate `gates.yaml` or commit** —
   it returns its verdict (gate id, pass/fail/out-of-lane, sha if committed-by-lane,
   evidence paths, any human question or supersede directive) via its handoff file.
4. **Reconcile (you are the sole writer).** Acquire `ledger.lock`, and for each
   returned verdict apply it to **that owner's row(s) only** via read-modify-write
   (re-read `gates.yaml` under the lock, change just those rows, atomic `mv`). Drain
   any answered questions and apply supersede directives here too. Re-project
   `state.md`, commit, release the lock.
5. **Cross-machine divergence.** If `git status`/`git log` show another machine
   pushed ledger changes, `git pull --ff-only` before reconciling; if it cannot
   fast-forward, escalate to the human (or write a question under
   `--remote-control`) rather than force-merging.

## Stopping

Stop and print `===== ALL OWNERS COMPLETE =====` when no owner has pickable work
and every gate is `passed` or `superseded`. If the only remaining work is awaiting
remote answers, print `===== CONDUCTOR IDLE — remote-wait =====`, then do a bounded
wait and re-poll (respect `--max-rounds`); after several idle rounds with no
progress, escalate to the human instead of spinning.

## Snapdir mode (`--snapdir-store <uri>` or `SNAPDIR_STORE` set)

In snapdir mode (git-free) you are the **sole canonical pusher** — this sidesteps
snapdir's single-writer catalog and any last-writer-wins on the ledger. Use
`${SNAPDIR_BIN:-snapdir}` and build `SNAPDIR_ARGS` as in `.gatesmith/PM_PROMPT.md`
("Snapdir mode"). Per round:

1. **Establish the canonical id.** First round: if `--snapdir-id <id>` was given,
   `snapdir pull . "${SNAPDIR_ARGS[@]}" --id <id>` (bootstrap). Otherwise push the
   current cwd once: `CANON_ID=$(snapdir push . "${SNAPDIR_ARGS[@]}")`.
2. **Spawn one worker subagent per eligible owner** (respecting per-owner loop-lock
   skips). Give each worker `CANON_ID` + the store args, and an **isolated checkout**
   so concurrent snapshots don't collide:
   `snapdir pull .gatesmith/work/<owner> "${SNAPDIR_ARGS[@]}" --id "$CANON_ID" --force`.
   The worker runs PICK→SPAWN→VERIFY (manifest-diff fence inside its checkout) for its
   scope and **returns a verdict via its handoff — it does NOT push and does NOT write
   the canonical ledger**. (Simpler default when lanes are disjoint: workers may edit
   their lane in place and only you push; the isolated checkout is the escape hatch for
   non-disjoint lanes. `.gatesmith/work/` is snapshot-exempt.)
3. **Reconcile (sole writer).** Under `.gatesmith/locks/ledger.lock`, apply each
   verdict to that owner's row(s) via read-modify-write (set `status`, `passed_at`,
   `snapdir_id: pending`), drain answers, apply supersedes, re-project `state.md`,
   release.
4. **Push the new canonical snapshot:** `CANON_ID=$(snapdir push . "${SNAPDIR_ARGS[@]}")`,
   then a brief second read-modify-write to set `snapdir_id: <CANON_ID>` on the gates
   passed this round (Phase-2 ordering from PM_PROMPT step 6). Journal `snapdir=<CANON_ID>`.
5. **Cross-machine:** there is no `git pull`. Coordination is the canonical id you hand
   out and the snapshots you push. If a shared `SNAPDIR_CATALOG` + shared FS is
   configured you MAY `snapdir revisions --location <store>` to detect a divergent
   newest id and escalate; otherwise you are authoritative by construction.

Reserved owner names `__conductor__` and `__all__` must never be used as a real
owner. (Tip: `/goal` can be made an alias for this command by copying this file to
`.claude/commands/goal.md`.)
