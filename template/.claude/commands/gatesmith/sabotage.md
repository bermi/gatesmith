---
description: Run every gate's sabotage controls, or author the missing ones (audit mode)
---

# /gatesmith:sabotage — prove the gates can fail

A gate that has never been shown to fail is not evidence. An instrument that has silently stopped
measuring is indistinguishable from a clean result. This command is what makes the difference
observable.

`$ARGUMENTS` may be: nothing (every gate), one or more gate ids, `--list`, or `--audit`.

## Run mode (default, or with gate ids)

```sh
.claude/gatesmith/sabotage.sh $ARGUMENTS
```

Report the table it prints verbatim. **Do not** re-interpret a `BAD` line as acceptable. The
statuses mean different things and the difference is the whole point:

| status | what it means | what to do |
| --- | --- | --- |
| `RED` | the control turned its gate red for its named predicate | nothing — this is the pass |
| `STAYED_GREEN` | the gate passed under a mutation that should break it | **first hypothesis: the instrument cannot see the defect, not that the code is fine** |
| `INERT_MUTATION` | the patch applied, the build consumed it, nothing moved | the mutation is arithmetically inert — `max(1.0, x)` where `x >= 1` always. Pick a magnitude the subject can actually express, and record the measurement |
| `RED_FOR_THE_WRONG_REASON` | it went red on a different predicate | a sabotage that reddens a gate for the wrong reason is not a control, it is a coincidence |
| `PREDICATE_ALREADY_RED_WHEN_CLEAN` | the expected failure is present without the mutation | a gate cannot borrow its own defect as proof of sensitivity |
| `SABOTAGE_DID_NOT_APPLY` | marker count 0, or the patch did not match | a failure of the CONTROL, never of the subject |
| `NO_CONTROL_DECLARED` | the gate has no control at all | the gate is currently unfalsifiable |

## Audit mode (`--audit`) — start here on an existing ledger

For every gate that reports `NO_CONTROL_DECLARED`, work out whether you *can* make it fail on
demand, and write the control. **The gates you cannot falsify are the real findings** — report them
by name rather than quietly skipping them.

For each, read the gate's `verification_cmd`, find the source it actually exercises, and author
`.gatesmith/controls/<gate-id>/<name>.json`:

```json
{
  "gate": "raster_parity",
  "name": "threshold-<-to-<=",
  "tag": "threshold-le",
  "expect": "boundary-exact-mismatch",
  "marker": "d1 <= bd",
  "edits": [
    { "file": "src/hit.zig", "find": "if (d1 < bd) {", "replace": "if (d1 <= bd) {", "count": 1 }
  ]
}
```

- `expect` is the **predicate name** the gate must report, not "it failed". Omit it only if the gate
  emits no evidence envelope — and then say so, because the differential is weaker.
- `marker` is a token that must appear in the patched file. Counted with `grep -c`, never `diff`:
  an untracked new file produces no diff at all.
- `count` is how many sites `find` must match. A mismatch aborts rather than patching the wrong one.
- Aim the mutation at a **different primitive or code path** from the controls that already exist. A
  gate whose every control patches the same function has only been shown to see that function.

**If a control cannot be written as declared, say why in the file, in place.** Do not delete the
declaration — a deleted declaration is an erased hole. Add a `"blocked"` key with the reason and the
measurement that supports it, and leave it visible.

## Rules this command enforces, and will not negotiate

1. **Never weaken a threshold to make a gate green.** To change any criterion, first demonstrate
   that the reference or baseline fails the same predicate, and record that demonstration — with the
   measurement — in `.gatesmith/CORRECTIONS.md`.
2. **Whoever implements does not verify.** If you wrote the code under a gate, you do not get to
   author or relax that gate's control in the same tick.
3. **When a control refuses to go red, suspect the instrument first.** Sweep the instrument's
   parameters before touching the mutation's magnitude, and record the sweep. A gate can be
   structurally blind to its own subject — it can integrate a region no part of the defect falls
   inside, and then the most drastic possible version of that defect leaves every metric identical.
