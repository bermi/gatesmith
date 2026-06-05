---
description: Run the (optionally owner-scoped) Gatesmith tick in a self-referential loop until that scope has no pickable gates.
argument-hint: "[<owner>] [--max-iterations N] [--remote-control] [--tick-cmd ./x] [--force]"
allowed-tools: ["Bash(.claude/gatesmith/setup-loop.sh:*)"]
---

Activate a Gatesmith build loop **for this session**. Give an `<owner>` to loop one
team/branch; omit it for a single-stream project (loops the unowned ledger).

```!
.claude/gatesmith/setup-loop.sh $ARGUMENTS
```

The script printed a `Run one '<tick command>' tick now` line above. Run **exactly
that tick command** now (it already carries the right scope and flags). When you try
to stop, the Stop hook re-feeds the same tick command.

The loop ends automatically when:
- the tick prints `===== OWNER COMPLETE: <owner> =====` (the scope's gates are all
  passed/superseded), or `===== PROJECT COMPLETE — all gates green =====`, or
- `--max-iterations` is reached.

Do **not** fabricate completion to escape the loop. If the only remaining work is
awaiting remote answers, the tick prints `===== OWNER IDLE: <owner> remote-wait =====`
and the loop keeps polling — that is expected, not a reason to stop.

To stop early: `/gatesmith:cancel <owner>` (or `/gatesmith:cancel _default` for the
single-stream loop). You never cancel the loop yourself; the human owns end-of-project.
