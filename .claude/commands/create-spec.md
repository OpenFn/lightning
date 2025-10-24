---
argument-hint: [issue-file-path]
description: Create requirements specification from issue file
---

# Create Requirements Specification from GitHub Issue

You are tasked with creating a comprehensive requirements specification document from a GitHub issue file. This command helps transform high-level issue descriptions into detailed, implementable specifications.

**Usage**: `/create-spec $ARGUMENTS`

If $ARGUMENTS appears to be an issue number (not a file path), instruct the user to run `/get-issue <number>` first to create the issue file, then provide the file path to this command.

## Process Overview

Follow this structured approach to create a requirements spec:

### 1. Issue Analysis

Read the issue file at $ARGUMENTS:
- Verify the file exists and is readable
- Extract key information: goals, constraints, acceptance criteria
- Identify frontend vs backend requirements
- Note any existing implementation details mentioned

### 2. Requirements Discovery

Break down the issue into specific requirements:
- **Core Requirements:** Essential functionality that must be implemented
- **Secondary Requirements:** Nice-to-have features or related concerns
- For each requirement:
  - **What:** Clear description of the requirement
  - **Why:** Purpose and user benefit
  - **Backend needs:** What backend must expose/implement
  - **Frontend needs:** What frontend must implement
  - **Implementation approach:** Proposed solution with code examples
  - **Open questions:** What needs clarification or decision

### 3. Codebase Context Analysis

Use agents to understand existing patterns:
- **codebase-analyzer:** Find similar implementations in the codebase
- **codebase-pattern-finder:** Identify patterns to follow
- **react-collab-editor / phoenix-elixir-expert:** For domain-specific analysis

Ask questions like:
- "How is X currently implemented in [similar feature]?"
- "What stores/contexts handle similar data?"
- "What's the pattern for [specific concern]?"

### 4. Requirements Document Structure

Create a document at `.context/<username>/analysis/<issue-name>-requirements.md` with:

```markdown
# [Feature Name] Requirements Analysis

**Issue:** [#XXXX](github-url)
**Date:** YYYY-MM-DD
**Status:** [In Progress / Review Complete]

## Table of Contents

- [Overview](#overview)
- [Core Requirements](#core-requirements)
- [Secondary Requirements](#secondary-requirements)
- [Backend API Contract](#backend-api-contract)
- [Open Questions & Decisions](#open-questions--decisions)
- [Implementation Dependencies](#implementation-dependencies)
- [Next Steps](#next-steps)

## Overview

[1-2 paragraph summary of what needs to be built and why]

## Core Requirements

### 1. [Requirement Name]

**What:** [Clear description]

**Why:** [User benefit / business reason]

**Backend needs to expose:**
- [List of data, APIs, events needed]

**Frontend needs to:**
- [List of UI, state management, interactions needed]

**Implementation:**
- [Specific approach with code examples]
- [Store/context locations]
- [Pattern references from codebase]

**Open Questions:**
- [List questions that need answers]

[Repeat for each core requirement]

## Secondary Requirements

[Similar structure for secondary items]

## Backend API Contract

### On Session Mount/Join
[Expected data structures]

### Reactive Updates During Session
[Events and state changes]

### On [Key Actions]
[Request/response formats]

## Open Questions & Decisions Needed

### Critical Questions
1. **Question?**
   - Options considered
   - Decision: [When answered]
   - Rationale: [Why]

[Mark questions as ✅ ANSWERED when resolved]

## Implementation Dependencies

### Must be resolved before work:
- [ ] Dependency 1
- [ ] Dependency 2

### Can be implemented in parallel:
- [ ] Task 1
- [ ] Task 2

## Next Steps

1. [Ordered list of next actions]
2. [With clear owners if known]
```

### 5. Interactive Review Process

Work with the user to review each requirement:
- Present one requirement at a time
- Ask clarifying questions
- Use agents to find implementation patterns
- Document decisions in the spec
- Mark items as reviewed/skipped
- Use TodoWrite to track review progress

Example flow:
```
"Let's review requirement 1: [Name]. I found this similar pattern in [file].
Should we follow this approach or explore alternatives?"
```

### 6. Decision Documentation

When decisions are made:
- Update the requirement section with chosen approach
- Add code examples showing the pattern
- Mark open questions as ✅ ANSWERED
- Document rationale for future reference
- Note if something is deliberately skipped (e.g., "SKIPPING - too complex")

### 7. Final Validation

Before completing:
- Verify all core requirements have implementation approaches
- Check that API contracts are complete
- Ensure backend/frontend dependencies are clear
- List actionable next steps
- Update status to "Review Complete"

## Key Principles

**Be Thorough:**
- Don't assume - ask questions and use agents to find answers
- Document the "why" behind decisions
- Include code examples from the codebase

**Be Collaborative:**
- Work iteratively with the user
- Present options, don't dictate solutions
- Track progress with TodoWrite

**Be Practical:**
- Reference existing patterns in the codebase
- Note when to reuse vs create new
- Identify dependencies and blockers early

**Be Clear:**
- Use consistent structure across requirements
- Mark decisions and open questions clearly
- Provide concrete next steps

## Usage

```
/create-spec <issue-file-path>
```

### Workflow

**Step 1:** User fetches the issue first:
```
/get-issue <issue-number>
```
This creates an issue file at a specific path (e.g., `.context/stuart/issues/3635-workflow-save.md`)

**Step 2:** User creates requirements spec with the file path:
```
/create-spec .context/stuart/issues/3635-workflow-save.md
```

### Important

- **Argument must be a file path**, not an issue number
- If the user provides just a number, instruct them to run `/get-issue <number>` first to create the issue file
- This keeps the command focused on its single purpose: converting an existing issue file into a requirements specification

### Process

Once you have the issue file path:
1. Read the issue file to understand the requirements
2. Create initial requirements document structure
3. Guide user through reviewing each requirement
4. Use agents to find implementation patterns
5. Document all decisions
6. Produce final comprehensive spec

## Output

Final deliverable is a complete requirements spec document that:
- Breaks down the issue into implementable pieces
- References existing codebase patterns
- Documents all decisions and rationale
- Provides clear API contracts
- Lists actionable next steps
- Can be used directly by developers to implement the feature
