---
description: Cancel a Gatesmith loop for one owner, or all loops owned by this session.
argument-hint: "<owner> | --all [--force]"
allowed-tools: ["Bash(.claude/gatesmith/cancel-loop.sh:*)"]
---

```!
.claude/gatesmith/cancel-loop.sh $ARGUMENTS
```

Removes the owner's loop state file and releases its lock, so the next time the
session tries to stop the Stop hook lets it exit.

- `/gatesmith:cancel <owner>` — cancel one owner (must be owned by this session).
- `/gatesmith:cancel --all` — cancel every loop owned by THIS session.
- `--force` — break a loop/lock held by another (e.g. crashed) session. Repo-wide
  with `--all --force`; warns it may orphan a still-running remote loop.

Report the result printed above to the user.
