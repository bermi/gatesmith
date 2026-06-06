---
name: snapdir
description: >-
  Inspect, verify, snapshot, and revert directory state with snapdir
  (content-addressed BLAKE3 directory snapshots). TRIGGER when: working in Gatesmith
  snapdir mode; asked to inspect/verify a snapdir id or snapshot; before risky or
  irreversible edits (checkpoint now, revert later); comparing two directory states
  fast; or materializing a snapshot id into a working tree. SKIP for normal
  git-tracked work where git history already provides checkpoints.
---

# snapdir — content-addressed directory snapshots

`snapdir` hashes a directory tree (BLAKE3) into a deterministic 64-hex **id** and can
push/pull that snapshot to/from a content store, byte-for-byte verified. Same content
⇒ same id on any machine. Call the binary as `${SNAPDIR_BIN:-snapdir}`. If it's
missing: `cargo install snapdir-cli` (then `snapdir -h`), or set
`SNAPDIR_BIN=/abs/path/to/snapdir`.

## Store & catalog basics

- **Store** (where snapshots live): `--store <uri>` — `file:///abs/path` (must be
  absolute), `s3://…`, `b2://…`, `gs://…`. `push`/`pull`/`fetch`/`verify` require it.
  (`snapdir` does **not** read a `SNAPDIR_STORE` env var — always pass `--store`.)
- **Cache** (local object cache): `--cache-dir` / `SNAPDIR_CACHE_DIR`. Keep it
  **outside** any directory you snapshot — `snapdir id` hashes the whole tree, so a
  nested cache changes the id.
- **Catalog** (history index, a redb DB in the cache dir): `--catalog <name>` /
  `SNAPDIR_CATALOG`. It is **local to the cache** — a peer with a fresh cache sees no
  revisions even on a shared store. It is also **single-writer**: serialize concurrent
  `push`/`revisions` behind a mutex (e.g. `mkdir some.lock` … `rmdir some.lock`).

Reusable argument set:
```bash
SD="${SNAPDIR_BIN:-snapdir}"
ARGS=(--store "$STORE")
[ -n "${SNAPDIR_CACHE_DIR:-}" ] && ARGS+=(--cache-dir "$SNAPDIR_CACHE_DIR")
[ -n "${SNAPDIR_CATALOG:-}" ]   && ARGS+=(--catalog "$SNAPDIR_CATALOG")
```
(`id` and `manifest` are local-only — omit `--store` for them.)

## Inspect ANY snapshot id

```bash
$SD manifest --id <id> "${ARGS[@]}"     # list TYPE PERM CHECKSUM SIZE PATH
$SD verify   --id <id> "${ARGS[@]}"     # re-hash every object, fail on tampering
$SD ancestors --id <id> --location <store|abspath> --catalog <name>   # history walk
$SD revisions --location <store|abspath> --catalog <name>             # JSON, newest first
# Read its contents by pulling to a throwaway dir:
tmp=$(mktemp -d); $SD pull "$tmp" --id <id> "${ARGS[@]}"; ls -R "$tmp"
```
`revisions` emits `{"created_at","id","previous_id"}` per line, newest first; the
latest id is the first line's `id`.

## Checkpoint & revert — your own safety net

Before risky/irreversible work, snapshot the FULL tree (no excludes — full fidelity),
remember the id, and restore it if things go wrong:
```bash
CK=$($SD push . "${ARGS[@]}")           # checkpoint -> 64-hex id
# … do the risky edits …
$SD pull . --id "$CK" "${ARGS[@]}" --force   # REVERT to the checkpoint
```
`--force` is required to overwrite a populated directory and **discards uncommitted
local changes** — only revert when you mean to. The id printed by `push` is the only
handle you need; record it.

## Fast mass-comparison (BLAKE3)

- "Did anything change?" → compare ids: `[ "$($SD id A)" = "$($SD id B)" ]`.
- "What changed?" → diff manifests (directory checksums bubble up, so one changed file
  shows on its own line):
  ```bash
  diff <($SD manifest A) <($SD manifest B) \
    | grep -E '^[<>] F ' \
    | sed -E 's#^[<>] F [0-7]+ [0-9a-f]+ [0-9]+ (\./.*)$#\1#' | sort -u
  ```

## Gotchas

- `push`/`pull`/`verify` need `--store`; `snapdir` ignores any `SNAPDIR_STORE` env.
- `file://` stores must be absolute (`file:///abs/...`).
- `--paths` filtering is unreliable in current builds — prefer `--exclude <regex>`
  (supports `%common%` / `%system%` macros) to drop noise.
- The catalog is per-cache and single-writer; share the cache+catalog (same host /
  shared FS) for peers to see each other's `revisions`, and serialize catalog writes.
- A full `snapdir push .` captures EVERYTHING in the tree — including `.git` and, if you
  run it in `$HOME`, your shell/Claude transcripts. Run from a dedicated project dir,
  or `--exclude` what you don't want.
