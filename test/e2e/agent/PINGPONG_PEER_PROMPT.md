# Ping-pong peer prompt (fill {{...}} and pass to one Agent subagent)

You are ping-pong peer **{{PEER}}** in a fleet of independent Claude instances that
share state ONLY through a snapdir content store. You may NOT talk to the other peers;
the store is your only channel.

Fixed environment — use exactly these, do not invent paths:
- snapdir binary: `{{SNAPDIR_BIN}}`
- store:  always pass `--store {{STORE}}`
- catalog: always pass `--catalog {{CAT}}`
- export `SNAPDIR_CACHE_DIR={{CACHE}}` before every snapdir call
- your working dir: `{{WORKDIR}}` (the cache is OUTSIDE it — only create files there via pull)
- shared mutex dir: `{{LOCK}}`

CRITICAL: the snapdir catalog allows only one writer at a time. EVERY
`snapdir revisions` and `snapdir push` MUST be wrapped in the mutex. Take it by looping
`mkdir {{LOCK}}` until it succeeds (sleep ~0.1s between tries; keep retrying — failure
means a peer holds it). Release with `rmdir {{LOCK}}` immediately after the snapdir
call, including on error. `snapdir pull` of a known id does NOT need the mutex.

Play exactly **{{ROUNDS}}** rounds. Each round is ONE locked critical section:
1. Take the mutex.
2. `LID=$({{SNAPDIR_BIN}} revisions --location {{STORE}} --catalog {{CAT}} | head -1 | grep -o '"id":"[0-9a-f]\{64\}"' | head -1 | cut -d'"' -f4)`
3. `rm -rf {{WORKDIR}} && {{SNAPDIR_BIN}} pull {{WORKDIR}} --store {{STORE}} --id "$LID"`
4. Append exactly one line `round<r>-peer-{{PEER}}` to `{{WORKDIR}}/tally.txt`.
5. `{{SNAPDIR_BIN}} push {{WORKDIR}} --store {{STORE}} --catalog {{CAT}}` (note the new id).
6. Release the mutex.

Never fabricate a round you didn't actually push. When done, report: the final id you
pushed, and the full contents of your last `tally.txt`. Do not stop early.
