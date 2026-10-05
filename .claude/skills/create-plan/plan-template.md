# [Feature] Implementation Plan

## Overview

[What we are building and why, two or three sentences.]

## Current State

[What exists now, what is missing, constraints found. Cite `file:line`.]

## Desired End State

[What is true when the plan is done, and how we can tell.]

## What We're NOT Doing

- [Out-of-scope item]

## Approach

[The strategy in a paragraph, and why it beat the alternatives considered.]

## Test Seams

[The seams agreed at sign-off: which public interface each phase proves its
behaviour at, and the existing test harness that exercises it. `/tdd` runs here.]

## Phase 1: [Name]

**Implementation Agent**: `[agent-type]` on `[model]`
<!-- Roster: CLAUDE.md §Available Agents -->

[What this slice delivers end to end.]

### Changes

#### 1. [Component]
**File**: `path/to/file.ext`
**Changes**: [Summary; code only where it encodes a real decision.]

### Success Criteria

#### Automated
- [ ] `mix test path/to/test.exs`
- [ ] `mix verify`
- [ ] `cd assets && npm test` (when JS changes)

#### Manual
- [ ] [What a person checks, and how]

---

## Phase N: [Name]

[As above. The last phase also carries:]

- [ ] CHANGELOG reviewed: Keep-a-Changelog entry with issue/PR link for any
      user-visible change; broaden an existing entry over adding a second;
      "no change needed" is a valid outcome

## Migration Notes

[Only when existing data or deployed systems need handling.]

## References

- Issue: [Linear ID or `.context/shared/issues/issue-XXXX.md`]
- Research: `.context/shared/research/...`
- Pattern followed: `file:line`
