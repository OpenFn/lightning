# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Project Overview

Lightning is an open source workflow platform for governments and non-profits to
move health and survey data between systems. It's built on Elixir/Phoenix with
PostgreSQL, featuring React components and real-time collaborative editing via
Yjs CRDTs.

## Common Development Commands

### Setup & Running

```bash
./bin/bootstrap              # Initial setup (run once, or when switching branches)
iex -S mix phx.server        # Run development server
mix verify                   # Run ALL code quality checks before committing
```

### Elixir Testing

```bash
MIX_ENV=test mix ecto.create           # First time test DB setup only
mix test                               # Run all tests (don't use -v flag)
mix test path/to/test.exs              # Run single file
mix test path/to/test.exs:42           # Run test at specific line
mix test --only focus                  # Run tests tagged with @tag :focus
```

### Frontend (always cd into assets/ first)

```bash
cd assets
npm test                     # Run unit tests in watch mode
npm run test:run             # Run tests once
npm run test:e2e             # Run E2E tests
npm run test:e2e:ui          # E2E with interactive UI
npm run lint                 # Lint TypeScript
npx tsc --noEmit --project ./tsconfig.browser.json  # Type check
```

### Code Quality

```bash
mix format                   # Format Elixir code (ALWAYS before committing)
mix credo --strict --all     # Static analysis
mix dialyzer                 # Type checking
mix sobelow                  # Security analysis
```

### Database

```bash
mix ecto.migrate                              # Run migrations
mix ecto.reset                                # Drop and recreate database
mix ecto.gen.migration short_descriptive_name # Generate migration
```

**Important Notes:**
- Phoenix auto-builds assets; use `mix esbuild default` or Tidewave MCP to check
  for build errors
- For JS/TS issues, prefer `mcp__ide__getDiagnostics` over `tsc`
- Never commit the `.context` directory (symlink to shared folder)

## Architecture Overview

### Directory Structure

- **`lib/lightning/`** - Core business logic, contexts, schemas
- **`lib/lightning_web/`** - LiveViews, controllers, API, channels
- **`assets/js/`** - React components, TypeScript
- **`test/`** - Mirrors source structure

### Key Contexts (lib/lightning/)

- **Workflows** - DAGs with jobs, triggers, edges (`lib/lightning/workflows.ex`)
- **Jobs** - JavaScript execution units with NPM adaptors
- **Accounts** - User management, authentication
- **Projects** - Main organizational unit
- **Credentials** - External service authentication (encrypted)
- **Runs** / **WorkOrders** - Workflow execution management
- **Collections** - Key-value data store

### Workflows Architecture

Workflows are **directed acyclic graphs (DAGs)**:
- **Triggers**: Webhook, Cron, or Kafka initiation
- **Jobs**: JavaScript code executed with NPM adaptors
- **Edges**: Flow control with conditions (`:always`, `:on_job_success`,
  `:on_job_failure`, `:js_expression`)

Key features:
- Snapshot system with `lock_version` optimistic locking
- Real-time collaborative editing via Yjs CRDTs
- Presence system for edit priority

### Collaborative Editor (assets/js/collaborative-editor/)

Real-time multi-user workflow editing using:
- **Yjs** - CRDT for conflict-free collaborative editing
- **y-phoenix-channel** - Yjs sync over Phoenix Channels
- **Y_ex** - Elixir Yjs bindings (see `.claude/guidelines/yex-guidelines.md`)

**Store Architecture** (see `.claude/guidelines/store-structure.md`):
- **SessionStore** - Y.Doc, connection state, sync status
- **WorkflowStore** - Jobs, triggers, edges, positions (Y.Doc backed)
- **AwarenessStore** - User presence, cursors, selections
- **SessionContextStore** - User, project, permissions (Phoenix Channel)
- **AdaptorStore** / **CredentialStore** - Reference data

All stores use `useSyncExternalStore` + Immer and integrate with Redux DevTools
in development.

### Database

- PostgreSQL with Ecto ORM
- Dev: `postgres://postgres:postgres@localhost:5432/lightning_dev`
- Test: `lightning_test` (auto-created by mix test)
- Schemas alongside contexts in `lib/lightning/`

## Development Guidelines

### Elixir/Phoenix

- Pattern matching and guards over conditionals
- Pipe operator `|>` for chaining
- Use `{}` brace syntax in HEEx templates
- Ecto changesets for validation
- Avoid string table references in queries; use schema modules
- `warnings_as_errors: true` - code must compile without warnings

### React/TypeScript

- Props from LiveView are **underscore_cased** (not camelCase)
- Use `cn()` utility from `#/utils/cn` for conditional CSS classes
- Use heroicons via Tailwind: `className="hero-check-micro h-4 w-4"`
- See `.claude/guidelines/toast-notifications.md` for notification patterns

### Testing

- **Backend**: ExUnit with ExMachina factories
- **Frontend**: Vitest (see `.claude/guidelines/testing-essentials.md`)
- **E2E**: Playwright (see `.claude/guidelines/e2e-testing.md`)
- Group related assertions; avoid micro-tests (one assertion per test)
- Target test file sizes: < 200-400 lines

## Worker System

External Node.js workers (@openfn/ws-worker) execute JavaScript jobs:
- WebSocket communication with JWT authentication
- Two-layer security: Worker Token + Run Token
- Generate keys: `mix lightning.gen_worker_keys`
- Required ENVs: `WORKER_RUNS_PRIVATE_KEY`, `WORKER_SECRET`,
  `WORKER_LIGHTNING_PUBLIC_KEY`

## Key Dependencies

### Backend
- Phoenix 1.7 + LiveView, Ecto 3.13+, Oban (background jobs)
- Bodyguard (authorization), Cloak (encryption), Y_ex (Yjs bindings)

### Frontend
- React 18, @xyflow/react (DAG visualization), Monaco Editor
- Yjs + y-phoenix-channel (collaboration), Zustand + Immer (state)
- Tailwind CSS, Vitest, Playwright

## Custom Mix Tasks

```bash
mix lightning.gen_worker_keys      # Generate worker authentication keys
mix lightning.gen_encryption_key   # Generate credential encryption key
mix lightning.install_runtime      # Install JavaScript runtime dependencies
mix lightning.install_schemas      # Install JSON schemas for validation
mix lightning.install_adaptor_icons # Install adaptor icons
```

## Troubleshooting

### Switching Branches
Run `./bin/bootstrap` to sync dependencies and migrations.

### Rambo Errors (Apple Silicon)
Install Rust: `brew install rust`

### Port Conflicts
```bash
lsof -i :4000   # Check what's using the port
```

## Guidelines Reference

Detailed guidelines in `.claude/guidelines/`:
- `store-structure.md` - Collaborative editor store architecture
- `testing-essentials.md` - Unit testing patterns and anti-patterns
- `e2e-testing.md` - Playwright E2E testing
- `yex-guidelines.md` - Critical Yex (Yjs/Elixir) usage rules
- `toast-notifications.md` - Notification patterns