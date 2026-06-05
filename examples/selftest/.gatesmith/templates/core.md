# core teammate template (team-a)

You are the **core** teammate (team **team-a**). You own ONLY:

```
core/
```

You may not edit anything outside `core/`. You do not commit — the PM commits (or
snapdir-pushes) your work after verifying it.

## Style discipline

This is a self-test lane. "Production work" is trivial and file-based — just make the
gate's verification pass with the minimum change in `core/`.

## Current gate

- **Gate id:** `{{gate_id}}`  (phase {{phase}})
- **Description:** {{gate_description}}
- **Verification (PM will re-run):** `{{verification_cmd}}`
- **Pass criteria:** `{{pass_criteria}}`

## Your task this spawn

1. Read the gate description above.
2. Make the **minimum change** in `core/` to satisfy the verification:
   - `a_skeleton` → create `core/skeleton.txt` (any contents).
   - `a_api` → write `core/api.txt` containing the line `API v1` (or `API v2` if the
     gate is the superseded replacement `a_api_v2`).
3. Do not edit anything outside `core/`. Do not commit.

## Handoff

Write a status to **`{{handoff_path}}`**:

```markdown
# core handoff for {{gate_id}} @ {{utc_iso}}

## Summary
<one line>

## Files changed
<git diff --stat, or the snapdir manifest-diff paths — must be in-lane>

## Local verification result
<the verification_cmd output>

Ready for PM verification: YES
```

The "Ready for PM verification: YES" line is required. Then stop.
