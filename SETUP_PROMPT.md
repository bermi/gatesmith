# Gatesmith setup prompt

A generalized version of the prompt that generates a project's gate ledger and
lane templates. Fill in the angle-bracket blanks, paste it into a Claude Code
session at the root of your project, and let it plan.

---

> I'd like to build **\<PROJECT GOAL — one or two sentences\>**.
>
> Constraints / stack / context: **\<languages, frameworks, hard requirements,
> non-goals; link a spec doc with `@path/to/spec.md` if you have one\>**.
>
> Please **ultrathink** and plan this to execute with teammates: a master
> **project-manager (PM) agent** designs machine-checkable **quality gates** and
> verifies what teammates do against them. Each gate names the lane that owns it,
> its dependencies, a `verification_cmd`, and `pass_criteria`. The PM spawns
> exactly one lane-owner teammate per tick, re-runs the verification itself,
> enforces a lane fence (`git diff --stat` — teammates may only touch their own
> lane directory), commits on pass, and journals every verdict. The whole project
> is controlled through a **ralph loop** from architecture to prototype until
> production quality is reached.
>
> Use the **Gatesmith** kit that's already installed in this repo:
> - Fill in the `{{LANES}}`, `{{PLAN_DOC}}`, and `{{FROZEN}}` placeholders in
>   `.pm/PM_PROMPT.md` for this project.
> - Replace the seed gates in `.pm/gates.yaml` with a real, phased,
>   dependency-ordered ledger covering the whole build (bootstrap → prototype →
>   hardening → ship). Mark human-judgment gates with `human_checkpoint: true`.
> - For each lane, copy `.pm/templates/_lane.md` to `.pm/templates/<lane>.md` and
>   write that lane's style discipline (idioms, allowed/banned APIs, testing,
>   reuse expectations).
> - Add this project's build/test/run commands to `.claude/settings.json` so
>   unattended ticks don't stall on permission prompts.
> - Write the locked architecture/build plan to the `{{PLAN_DOC}}` path.
>
> When the ledger and templates are ready, I'll start the build with:
>
> ```
> /ralph-loop:ralph-loop /gatesmith
> ```

---

## After planning

1. Review the generated `.pm/gates.yaml` — this *is* your project plan. If the
   gates are right, the build will be right.
2. Make the bootstrap commit (just `.pm/`, `.claude/`, and your build-tool files).
3. Run `/ralph-loop:ralph-loop /gatesmith` and watch `.pm/journal.md` fill in.
4. Stop any time with `/ralph-loop:cancel-ralph`; resume by running the loop again.
