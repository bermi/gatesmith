# Corrections

Every change to what a gate *means* — its `verification_cmd`, its `pass_criteria`, a threshold, a
declared control — is recorded here, with the measurement that justifies it.

`.claude/gatesmith/ledger-fence.sh` blocks a fenced field from moving without an entry naming the
gate. It can check that an entry exists and is substantive. It cannot check that the demonstration
is honest — that is what "whoever implements does not verify" is for.

## The rule

**Never weaken a threshold to make a gate green.** "The implementation is off and the gate wanted
tighter" is a bug, not an over-specified gate. To change a criterion you must first demonstrate that
the **reference or baseline fails the same predicate**, measured, and record it below.

## What an entry must contain

```markdown
## <gate-id> — <one line: what moved>

**The reading that was red.** The number, the predicate, the run it came from.

**Which side is wrong, measured.** Drive the REFERENCE through the same instrument, at the same
inputs. If the reference passes comfortably, the subject is wrong and the gate stays. Only if the
reference fails the same predicate is the criterion itself in question — and then say by how much.

**The correction.** What changed, and why the new criterion is not simply the old one relaxed until
the subject fit.

**Why this is not a weakening.** What the gate can still catch that it could before. Ideally: the
control that proves it, and the reading it produces.
```

## A worked shape, for calibration

A gate compared two things and one of them was measured at the wrong moment, so the comparison was
between two different states. The fix was not to widen the tolerance — re-driven at the same state,
the reference failed the old predicate *worse* than the subject did. The instrument was replaced;
the bound never moved. That is the shape to aim for: **the instrument is usually what is wrong, not
the number.**

---

<!-- entries below, newest last -->
