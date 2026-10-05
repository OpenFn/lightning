---
name: implement-plan
description: Execute a plan written by /create-plan, one phase at a time, on the agent and model each phase names. Usage /implement-plan <plan path>
disable-model-invocation: true
---

# Implement plan

Read the plan at `$ARGUMENTS` in full. If empty, ask for the path. Check
`git log` for phases already landed before starting.

Plans from `/create-plan` carry three things a fresh session should honour:

- **Test Seams** names where tests go. Use `/tdd` at those seams only; a test
  at a seam the plan does not name needs the user's agreement first.
- Each phase names an **Implementation Agent** and model. Dispatch one fresh
  agent per phase with that type and an explicit `model:`, handing it the plan
  path and phase number rather than a paraphrase. Phases run in order.
- **Success Criteria** split automated from manual. The phase agent runs the
  automated ones; run them again yourself before moving on. Manual ones are
  reported to the user at the end, never ticked on their behalf.

When the code disagrees with the plan, stop and ask before adapting.

When every phase passes: `/code-review`, fix what holds, then `/commit`.
Report any manual criteria still outstanding.
