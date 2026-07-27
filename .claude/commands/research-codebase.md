---
argument-hint: [research-query]
description: Research codebase with parallel agents
---

# Research Codebase

You are tasked with conducting comprehensive research across the codebase to answer user questions by spawning parallel sub-agents and synthesizing their findings.

**Usage**:
- `/research-codebase` - Interactive mode, asks for research question
- `/research-codebase <query>` - Direct mode, starts research immediately with provided query

## Your job: document and explain the codebase as it exists today

Describe what exists; don't propose improvements, critiques, or refactors unless asked. You are creating a technical map/documentation of the existing system — describe what exists, where it exists, how it works, and how components interact.

## Initial Setup:

When this command is invoked:

**If `$ARGUMENTS` is provided**:
- Begin research immediately with the query: `$ARGUMENTS`
- Skip the initial prompt
- Proceed directly to step 1 (reading any mentioned files) and then step 2 (analyzing and decomposing the research question)

**If `$ARGUMENTS` is empty**, respond with:
```
I'm ready to research the codebase. Please provide your research question or area of interest, and I'll analyze it thoroughly by exploring relevant components and connections.
```

Then wait for the user's research query.

## Steps to follow after receiving the research query:

1. **Read any directly mentioned files first:**
   - If the user mentions specific files (tickets, docs, JSON), read them first
   - Read mentioned files fully (no limit/offset) in the main context before spawning sub-tasks.
   - This ensures you have full context before decomposing the research

2. **Analyze and decompose the research question:**
   - Break down the user's query into composable research areas
   - Identify specific components, patterns, or concepts to investigate
   - Create a research plan using TodoWrite to track all subtasks
   - Consider which directories, files, or architectural patterns are relevant

3. **Spawn parallel sub-agent tasks for comprehensive research:**
   - Create multiple Task agents to research different aspects concurrently.
   - See [CLAUDE.md §Available Agents](../../CLAUDE.md#available-agents) for the canonical agent roster. For research, the relevant agents are typically **codebase-locator**, **codebase-analyzer**, **codebase-pattern-finder**, **context-locator**, **context-analyzer**, and (only when the user explicitly asks for external research) **web-search-researcher**.
   - All agents are documentarians, not critics: they describe what exists without suggesting improvements.
   - For web-research agents, instruct them to return LINKS with their findings and INCLUDE those links in your final report.
   - Start with locator agents to find what exists; then run analyzer agents on the most promising findings. Run multiple agents in parallel when they're searching for different things.

4. **Wait for all sub-agents to complete and synthesize findings:**
   - IMPORTANT: Wait for ALL sub-agent tasks to complete before proceeding
   - Compile all sub-agent results (both codebase and context findings)
   - Prioritize live codebase findings as primary source of truth
   - Use .context/ findings as supplementary historical context
   - ask the user for their first name if `$USER` or `dscl/finger` fails or doesn't map to a persons folder in .context.
   - Connect findings across different components
   - Include specific file paths and line numbers for reference
   - Verify all .context/ paths are correct (e.g., .context/stuart/ or .context/shared/)
   - Highlight patterns, connections, and architectural decisions
   - Answer the user's specific questions with concrete evidence

5. **Generate research document:**
   - Use the metadata gathered in step 4
   - Structure the document with YAML frontmatter followed by content:
     ```markdown
     ---
     date: [Current date and time with timezone in ISO format]
     researcher: [Researcher name from step 4 status]
     git_commit: [Current commit hash]
     branch: [Current branch name]
     repository: [Repository name]
     topic: "[User's Question/Topic]"
     tags: [research, codebase, relevant-component-names]
     status: complete
     last_updated: [Current date in YYYY-MM-DD format]
     last_updated_by: [Researcher name]
     ---

     # Research: [User's Question/Topic]

     **Date**: [Current date and time with timezone from step 4]
     **Researcher**: [Researcher name from step 4 status]
     **Git Commit**: [Current commit hash from step 4]
     **Branch**: [Current branch name from step 4]
     **Repository**: [Repository name]

     ## Research Question
     [Original user query]

     ## Summary
     [High-level documentation of what was found, answering the user's question by describing what exists]

     ## Detailed Findings

     ### [Component/Area 1]
     - Description of what exists ([file.ext:line](link))
     - How it connects to other components
     - Current implementation details (without evaluation)

     ### [Component/Area 2]
     ...

     ## Code References
     - `path/to/file.ex:123` - Description of what's there
     - `another/file.ts:45-67` - Description of the code block

     ## Architecture Documentation
     [Current patterns, conventions, and design implementations found in the codebase]

     ## Historical Context (from .context/)
     [Relevant insights from .context/ directory with references]
     - `.context/shared/something.md` - Historical decision about X
     - `.context/stuart/notes.md` - Past exploration of Y

     ## Related Research
     [Links to other research documents in .context/shared/research/]

     ## Open Questions
     [Any areas that need further investigation]
     ```

6. **Add GitHub permalinks (if applicable):**
   - Check if on main branch or if commit is pushed: `git branch --show-current` and `git status`
   - If on main/master or pushed, generate GitHub permalinks:
     - Get repo info: `gh repo view --json owner,name`
     - Create permalinks: `https://github.com/{owner}/{repo}/blob/{commit}/{file}#L{line}`
   - Replace local file references with permalinks in the document

7. **Present findings:**
   - Present a concise summary of findings to the user
   - Include key file references for easy navigation
   - Ask if they have follow-up questions or need clarification

8. **Handle follow-up questions:**
   - If the user has follow-up questions, append to the same research document
   - Update the frontmatter fields `last_updated` and `last_updated_by` to reflect the update
   - Add `last_updated_note: "Added follow-up research for [brief description]"` to frontmatter
   - Add a new section: `## Follow-up Research [timestamp]`
   - Spawn new sub-agents as needed for additional investigation
   - Continue updating the document

## Important notes:
- For Lightning-specific commands referenced in research reports (e.g., `mix verify`, `mix test`), see [CLAUDE.md §Common Commands](../../CLAUDE.md#common-commands).
- Always use parallel Task agents to maximize efficiency and minimize context usage
- Always run fresh codebase research - never rely solely on existing research documents
- The .context/ directory provides historical context to supplement live findings
- Focus on finding concrete file paths and line numbers for developer reference
- Each sub-agent prompt should be specific and focused on read-only documentation operations
- Link to GitHub when possible for permanent references
- Explore all of .context/ directory, including shared/, stuart/, frank/, and root-level files (see `.claude/agents/context-locator.md` for the `.context/` layout)
- **File reading**: Read mentioned files fully (no limit/offset) before spawning sub-tasks
- **Ordering**: Follow the numbered steps:
  - Read mentioned files first before spawning sub-tasks (step 1)
  - Wait for all sub-agents to complete before synthesizing (step 4)
  - Gather metadata before writing the document (step 5 before step 6)
  - Don't write the research document with placeholder values
- **Frontmatter consistency**:
  - Always include frontmatter at the beginning of research documents
  - Keep frontmatter fields consistent across all research documents
  - Update frontmatter when adding follow-up research
  - Use snake_case for multi-word field names (e.g., `last_updated`, `git_commit`)
  - Tags should be relevant to the research topic and components studied
