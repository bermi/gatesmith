# Self-test build plan (locked)

This is the `{{PLAN_DOC}}` for the Gatesmith e2e self-test. The architecture is
trivial on purpose — the point is to exercise Gatesmith's orchestration, not to build
real software.

- **team-a** (lane `core/`): owns the API. `a_skeleton` creates `core/skeleton.txt`;
  `a_api` writes `core/api.txt` with the API marker line.
- **team-b** (lane `svc/`): owns a service that **consumes team-a's API**.
  `b_consumer` depends (cross-owner) on `a_api` and writes `svc/consumer.txt`.
- **team-qa** (lane `qa/`): owns the human sign-off. `qa_signoff` is a human
  checkpoint after the integration is in place.

Locked decision: the API marker is `API v1`. (The self-test exercises *supersede* by
replacing `a_api` with `a_api_v2` whose marker is `API v2`, which re-points
`b_consumer`.)
