---
argument-hint: [plan-file-path]
description: Implement approved technical plan
---

# Implement Plan

You are tasked with implementing an approved technical plan from `.context/shared/plans/`. These plans contain phases with specific changes and success criteria.

**Usage**: `/implement-plan $ARGUMENTS`

If `$ARGUMENTS` is empty, ask user for plan path. Otherwise, read the plan at `$ARGUMENTS` and begin implementation.

## Getting Started

When `$ARGUMENTS` contains a plan path:
- Read the plan at `$ARGUMENTS` completely and check for any existing checkmarks (- [x])
- **Identify the agent assignment** for each phase (marked as `**Implementation Agent**: ...`)
- Read the original ticket and all files mentioned in the plan
- **Read files fully** - never use limit/offset parameters, you need complete context
- Think deeply about how the pieces fit together
- Create a todo list to track your progress across all phases
- **CRITICAL**: You will coordinate implementation, spawning a FRESH specialized agent for each phase

If `$ARGUMENTS` is empty, ask for one.

## Available Agent Types

When implementing phases, use these specialized agents based on the work type:

- **phoenix-elixir-expert**:
  - Elixir/Phoenix backend development
  - Ecto schemas, migrations, and queries
  - Phoenix LiveView backend
  - Phoenix Channels and WebSocket implementations
  - OTP, GenServers, supervision trees
  - Performance optimization
  - Backend testing with ExUnit

- **react-collaborative-architect**:
  - React/TypeScript frontend development
  - Collaborative editing features with YJS
  - Modern React patterns (hooks, context, etc.)
  - Lightning workflow editor frontend
  - Testing collaborative features

- **react-collab-editor**:
  - Collaborative editor in `assets/js/collaborative-editor/`
  - Y.Doc synchronization and debugging
  - Immer and useSyncExternalStore patterns
  - TanStack Form and Zod validation
  - @xyflow/react diagram components
  - TypeScript type fixes in editor codebase

- **react-test-specialist**:
  - React component unit tests with Vitest
  - Reviewing and improving test quality
  - Removing redundant tests
  - Test refactoring for maintainability
  - Following project test guidelines

- **general-purpose**:
  - Mixed work spanning frontend and backend
  - Coordination tasks
  - Work that doesn't fit specialized categories
  - Simple changes not requiring specialized expertise

## Agent-Based Phase Implementation

**This is the core of the implementation process**:

1. **For each phase**, spawn a FRESH agent of the type specified in the plan

2. **Each agent gets a focused task**:
   ```
   You are implementing Phase [N] of this plan: [plan path]

   Read the plan file completely, then implement ONLY this phase:

   ## Phase [N]: [Phase Name]

   [Copy the full phase details from the plan]

   After implementation:
   1. Run all automated verification steps listed in the success criteria
   2. Fix any issues that arise
   3. Update the plan file to check off completed items
   4. Report back with what was completed and any manual verification steps remaining
   ```

3. **Wait for each phase to complete** before spawning the next agent
   - This ensures each phase gets a fresh context window
   - Prevents context overflow on complex implementations
   - Each agent focuses solely on their phase

4. **After each phase completes**:
   - Read the updated plan to see what was checked off
   - Review any issues or notes from the agent
   - Perform or coordinate manual verification if needed
   - Move to the next phase with a new fresh agent

## Your Role as Coordinator

As the main agent running this command, you are the **coordinator**, not the implementer:
- You read the plan and understand the full scope
- You spawn specialized agents for each phase
- You track overall progress across all phases
- You handle issues and communicate with the user
- You coordinate manual verification between phases

**You do NOT implement the phases yourself** - you delegate to fresh specialized agents.

## Implementation Philosophy

Plans are carefully designed, but reality can be messy. The job is to:
- Follow the plan's intent while adapting to what is found
- Implement each phase fully before moving to the next
- Verify work makes sense in the broader codebase context
- Update checkboxes in the plan as sections are completed

When things don't match the plan exactly, think about why and communicate clearly. The plan is the guide, but judgment matters too.

If an agent encounters a mismatch:
- The agent should STOP and report the issue
- Present the issue clearly to the user:
  ```
  Issue in Phase [N]:
  Expected: [what the plan says]
  Found: [actual situation]
  Why this matters: [explanation]

  How should I proceed?
  ```
- Wait for user guidance before continuing
- May need to spawn a new agent with updated instructions

## Verification Approach

Each phase agent is responsible for:
- Running all automated verification steps in the success criteria
- Fixing any issues before reporting completion
- Updating checkboxes in the plan file using Edit
- Reporting what manual verification steps remain

As coordinator, you should:
- Verify the agent completed their automated checks
- Coordinate any manual verification with the user
- Ensure quality before moving to the next phase

## If an Agent Gets Stuck

When an agent reports something isn't working as expected:
- Review what the agent tried
- Consider if the codebase has evolved since the plan was written
- Present the mismatch clearly to the user
- Get guidance before spawning a new agent with updated instructions

**Key insight**: If an agent is stuck, don't try to fix it yourself - either:
1. Guide the user to help resolve the issue, then spawn a new agent
2. Spawn a debugging/research agent to understand the issue
3. Update the plan and spawn a new implementation agent

## Resuming Work

If the plan has existing checkmarks:
- Identify which phase to start from (first unchecked phase)
- Trust that completed work is done
- Spawn an agent for the next incomplete phase
- Verify previous work only if something seems off

## Example Flow

```
You (coordinator): Reading plan... I see 3 phases:
  - Phase 1: Database Schema (phoenix-elixir-expert) ✅ Done
  - Phase 2: API Endpoints (phoenix-elixir-expert) ⬜ Next
  - Phase 3: React Components (react-collaborative-architect) ⬜ Pending

I'll spawn a fresh phoenix-elixir-expert agent for Phase 2...

[Agent implements Phase 2, runs tests, updates checkboxes]

Agent completed Phase 2! All automated checks passed.
Manual verification needed: Test the API endpoints with curl.

[Wait for user to verify or proceed]

Now spawning a fresh react-collaborative-architect agent for Phase 3...
```

Remember: You're coordinating a solution, not implementing it. Each phase gets a fresh agent with a focused mission. This prevents context overflow and ensures quality.
