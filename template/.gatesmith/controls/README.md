# Sabotage controls

One JSON file per control: `.gatesmith/controls/<gate-id>/<name>.json`.

A control is a concrete mutation to the **real source** that must turn its gate red. `/gatesmith:sabotage`
applies each one to an `rsync` copy of the tree, builds and runs there, asserts the gate went red for
the named predicate, and deletes the copy. The working tree is never mutated.

```json
{
  "gate": "raster_parity",
  "name": "threshold-<-to-<=",
  "tag": "threshold-le",
  "expect": "boundary-exact-mismatch",
  "marker": "d1 <= bd",
  "markerFile": "src/hit.zig",
  "edits": [
    { "file": "src/hit.zig", "find": "if (d1 < bd) {", "replace": "if (d1 <= bd) {", "count": 1 }
  ]
}
```

| field | meaning |
| --- | --- |
| `gate` | the gate id in `gates.yaml`. Its `verification_cmd` is what gets re-run. |
| `name` | must be stable — it is how "declared" and "executed" are matched. |
| `tag` | filename component for the result. Defaults to a slug of `name`. |
| `expect` | the **predicate name** the gate must report. Requires an evidence envelope. |
| `marker` | token that must appear in the patched file, counted with `grep -c`. |
| `markerFile` | where to count it. Defaults to `edits[0].file`. |
| `edits[]` | `{file, find, replace, count}`. `find` must match exactly `count` sites. |
| `kind` | `source-mutation` (default) or `empty-input`. |
| `env` | env vars for the sabotaged run — how `empty-input` controls starve the gate. |

## The red-on-empty control

Feed the gate nothing and require it to refuse to report green. Passing on no data is the most
common way a suite becomes decorative.

```json
{ "gate": "raster_parity", "name": "empty-corpus", "kind": "empty-input",
  "env": { "CORPUS_DIR": "/dev/null" } }
```

An empty *input* is not the only shape of this. A gate can have a full corpus and a **selector that
matches nothing** — a filter for a category the data never contains — and pass while measuring an
empty set. Assert the count of what was actually measured (`subjects`, `samples`, `comparisons`) in
the gate's own envelope, not merely that input existed.

## The evidence envelope

Controls work without one — the differential falls back to the exit code and records
`strength: "exit-code-only"`. But an exit code carries one bit, so it cannot tell "red for the right
reason" from a coincidence. Gates that emit `.gatesmith/evidence/<gate>.json` get the full check:

```json
{
  "verdict": "PASS",
  "failures": [],
  "counts":  { "subjects": 13, "comparisons": 52 },
  "metrics": { "worst_delta": 0.0063 },
  "thresholds": { "worst_delta": 0.018 },
  "instrument": {
    "name": "what was measured",
    "live": true,
    "evidence_of_liveness": "the observation proving the instrument was working this run"
  }
}
```

`verdict` is three-valued: `PASS`, `FAIL`, and `UNTRACED` (exit 3) — the instrument could not be
shown to work. **UNTRACED is never counted as a pass and never as a failure.** A check that cannot
see must not be permitted to report a colour.
