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

Reserved owner names `__conductor__` and `__all__` must never be used as a real
owner. (Tip: `/goal` can be made an alias for this command by copying this file to
`.claude/commands/goal.md`.)
