# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Project Overview

Lightning is an open source workflow platform for governments and non-profits to
move health and survey data between systems. It's built on Elixir/Phoenix with
PostgreSQL, featuring React components and real-time collaborative editing.

## Common Development Commands

### Elixir/Phoenix Development

```bash
# Setup project (run once)
./bin/bootstrap

# Run development server
iex -S mix phx.server

# With custom environment variables
env $(cat .env | grep -v "#" | xargs) iex -S mix phx.server

# Testing
MIX_ENV=test mix ecto.create  # first time setup
mix test
# Don't use -v flag with mix test

# Code quality checks
mix verify  # runs all checks below
mix format --check-formatted
mix dialyzer
mix credo --strict --all
mix sobelow
mix coveralls.html

# Database operations
mix ecto.create
mix ecto.migrate
mix ecto.reset  # drop and recreate
mix ecto.gen.migration short_descriptive_name
```

### Frontend Development

```bash
# Always cd into assets directory first
cd assets

# Run tests
npm test
npm run test:run
npm run test:coverage

# Type checking (preferred method)
npx tsc --noEmit --project ./tsconfig.browser.json

# E2E testing
npm run test:e2e
npm run test:e2e:ui
npm run test:e2e:debug

# Linting
npm run lint

# Check types across project (only when explicitly asked)
npm run check
```

**Important**: Phoenix auto-builds assets. To check for build failures/warnings,
use Tidewave MCP to check logs or run `mix esbuild default`. For JS/TS issues,
prefer `mcp__ide__getDiagnostics` over `tsc`.

### Debugging Collaborative Editor Stores

The collaborative editor stores integrate with Redux DevTools in development:

```bash
# Start development server
iex -S mix phx.server

# Open browser and navigate to workflow editor
# Open Redux DevTools extension (Chrome/Firefox)
# Select store instance from dropdown (e.g., "WorkflowStore")
```

**Available stores:**
- WorkflowStore - Workflow data, jobs, triggers, edges
- SessionContextStore - User, project, config, permissions
- SessionStore - Connection and sync state
- AwarenessStore - Collaborative user presence
- AdaptorStore - Available adaptors
- CredentialStore - Project and keychain credentials

**Features:**
- View current state of any store
- See action history with timestamps
- Export/import state for bug reproduction

**Note:** DevTools is disabled in production builds. For detailed store architecture and usage guidelines, see `.claude/guidelines/store-structure.md`.

### Docker Development

```bash
# Initial setup
docker compose build && docker compose run --rm web mix ecto.migrate

# Run application
docker compose up

# Reset everything
docker compose down --rmi all --volumes
```

## Architecture Overview

### Core Structure

- **`lib/lightning/`**: Core business logic, contexts, schemas
- **`lib/lightning_web/`**: Web interface, LiveViews, controllers, API
- **`assets/`**: React components, TypeScript, CSS
- **Phoenix LiveView**: Primary UI framework with real-time features
- **React Integration**: Selected components use React via LiveView mounting

### Key Contexts (lib/lightning/)

- **Accounts**: User management, authentication (`lib/lightning/accounts.ex`)
- **Projects**: Main organizational unit (`lib/lightning/projects.ex`)
- **Workflows**: Directed acyclic graphs with jobs/triggers
  (`lib/lightning/workflows.ex`)
- **Runs**: Workflow execution instances (`lib/lightning/runs.ex`)
- **Jobs**: Workflow components with JavaScript/adaptors
  (`lib/lightning/jobs.ex`)
- **Credentials**: External service authentication
  (`lib/lightning/credentials.ex`)
- **Collections**: Key-value data store (`lib/lightning/collections.ex`)

### Workflows System Architecture

Lightning workflows are **directed acyclic graphs (DAGs)** with these
components:

1. **Workflow**: Container with jobs, triggers, edges
2. **Jobs**: JavaScript execution units with NPM adaptors and credentials
3. **Triggers**: Initiation methods (Webhook, Cron, Kafka)
4. **Edges**: Flow control with conditions (`:always`, `:on_job_success`,
   `:on_job_failure`, `:js_expression`)

**Novel Solutions**:

- Snapshot system with `lock_version` optimistic locking
- Real-time collaborative presence with edit priority
- Multi-type trigger system with unified interface
- Conditional edge execution with JavaScript expressions

### Database

- PostgreSQL with Ecto ORM
- Development URL: `postgres://postgres:postgres@localhost:5432/lightning_dev`
- Test URL: Same host/port but `lightning_test` database
- Migrations: `priv/repo/migrations/`
- Schemas alongside contexts in `lib/lightning/`
- Use `psql` with dev URL for direct database queries

### Additional Contexts

- **WorkOrders** (lib/lightning/work_orders.ex): Manages workflow execution
  requests
- **Invocations** (lib/lightning/invocation): Individual job execution records
- **Pipeline** (lib/lightning/pipeline): Job execution pipeline management
- **Runtime** (lib/lightning/runtime): JavaScript execution environment
- **Config** (lib/lightning/config.ex): Application configuration management
- **Collections** (lib/lightning/collections.ex): Key-value data store for
  workflow data

## Development Guidelines

### Elixir/Phoenix Best Practices

- Write idiomatic Elixir with pattern matching and guards
- Follow Phoenix conventions for contexts, schemas, controllers
- Use snake_case for files/functions, PascalCase for modules
- Leverage pipe operator `|>` for chaining
- Use newer `{}` brace syntax in HEEx templates
- Implement "let it crash" philosophy with supervisor trees
- Use Ecto changesets for validation
- Avoid string table references in queries: use schema modules
- **Always run `mix format` before committing** - this is critical
- When generating migrations: `mix ecto.gen.migration short_descriptive_name`
  (underscored spaced style)

### React Development

- Props from LiveView React mounting are **underscore_cased**, not camelCased
- Components receive underscore_cased props when mounted via LiveView
- Lightning uses React 18+ with modern patterns
- Key dependencies: @xyflow/react (workflow visualization), Yjs (collaborative
  editing), Monaco Editor (code editing)
- React components integrated into Phoenix app via LiveView mounting
- **Icons**: Use heroicons via Tailwind classes (e.g., `className="hero-check-micro h-4 w-4"`). Never create custom SVG icons.
- **Conditional CSS Classes**: Always use the `cn` utility (`assets/js/utils/cn.ts`) for merging Tailwind classes. It combines `clsx` for conditional logic with `tailwind-merge` for conflict resolution.

#### Using the `cn` Utility

The `cn` utility should be used whenever you need to conditionally apply CSS classes or merge className props:

```typescript
import { cn } from '#/utils/cn';

// Basic conditional classes
<div className={cn(
  "base-class",
  isActive && "active-class",
  isDisabled && "opacity-50"
)} />

// Merging with className prop
<button className={cn(
  "px-4 py-2 rounded",
  variant === 'primary' ? "bg-blue-600" : "bg-gray-200",
  className
)} />

// Handles Tailwind conflicts automatically
cn('p-4', 'p-2') // => "p-2" (last wins)
```

**Anti-pattern to avoid:**
```typescript
// ❌ Don't use template literals
className={`base-class ${condition ? 'active' : ''} ${className}`}

// ✅ Use cn instead
className={cn("base-class", condition && "active", className)}
```

#### Toast Notifications

For toast notifications in the collaborative editor, see `.claude/guidelines/toast-notifications.md`:
- Usage patterns for info, alert, success, and warning toasts
- Integration with workflow operations
- Styling conventions matching Lightning's design system
- Testing strategies

#### Collaborative Editor Store Architecture

When working with the collaborative editor stores (creating, modifying, or debugging), see `.claude/guidelines/store-structure.md`:
- Store hierarchy and responsibilities (SessionStore, WorkflowStore, AwarenessStore, etc.)
- Decision tree for "where should this state go?"
- Store update patterns (Y.Doc, Phoenix Channel, local state)
- When to create new stores vs extending existing ones
- Redux DevTools integration for debugging

### Testing Requirements

- Write comprehensive ExUnit tests for backend code
- Use ExMachina for test data generation
- Follow TDD practices
- Don't use `-v` flag with mix test
- Frontend: Use Vitest for unit/integration tests
- E2E: Use Playwright tests (`npm run test:e2e` in assets/)
- E2E environment managed by `bin/e2e` script
- Test database: `lightning_test` (automatically created/migrated by mix test)
- **See `.claude/guidelines/testing-essentials.md`** for comprehensive unit
  testing guidelines and best practices
- **See `.claude/guidelines/e2e-testing.md`** for comprehensive E2E testing
  guidelines with Playwright, Phoenix LiveView patterns, and collaborative
  feature testing

### Code Quality Standards

- Line width under 80 characters
- Run `mix verify` before committing (runs format, dialyzer, credo, sobelow,
  coveralls)
- Use TypeScript strictly in frontend with strict type checking
- Elixir code compiled with `warnings_as_errors: true`
- Follow security best practices (authentication, authorization, input
  validation)

### Feature Development

- Label work units with `Uxx` prefixes
- Minimize changes outside current unit scope
- Highlight impacts on past/future units

## Worker System

Lightning uses external Node.js workers (@openfn/ws-worker) for job execution:

- WebSocket communication with JWT authentication
- Two-layer security: Worker Token (shared secret) + Run Token
  (Lightning-signed)
- Workers execute JavaScript jobs with NPM adaptors in isolated environments
- Generate keys with: `mix lightning.gen_worker_keys`
- Required environment variables: `WORKER_RUNS_PRIVATE_KEY`, `WORKER_SECRET`,
  `WORKER_LIGHTNING_PUBLIC_KEY`
- Worker package: `@openfn/ws-worker` (npm, used in dev dependencies)

## Custom Mix Tasks

Lightning includes several custom Mix tasks:

- `mix lightning.install_runtime`: Install JavaScript runtime dependencies
- `mix lightning.install_schemas`: Install JSON schemas for validation
- `mix lightning.install_adaptor_icons`: Install adaptor icons
- `mix lightning.gen_worker_keys`: Generate worker authentication keys
- `mix lightning.gen_encryption_key`: Generate encryption key for credentials

## Deployment Considerations

### Required Environment Variables

- `PRIMARY_ENCRYPTION_KEY`: For credentials/TOTP encryption (generate with
  `mix lightning.gen_encryption_key`)
- Worker authentication keys (see Worker System section)
- Database URL and connection settings
- See `.env.example` for comprehensive list of configuration options

### Security

- Encryption at rest for credentials and sensitive data (Cloak + libsodium)
- JWT-based worker authentication (Joken)
- OAuth2 integration support for external services
- Multi-factor authentication (TOTP via nimble_totp)
- Strong parameter validation via Ecto changesets
- Rate limiting via Hammer + Mnesia backend
- CORS support via cors_plug

## Performance Optimization

- Database indexing for query performance
- Ecto preloading to avoid N+1 queries
- Caching strategies (ETS via Cachex, no Redis)
- Background job processing with Oban (multiple queues: scheduler, background,
  workflow_runs)
- Prometheus metrics via PromEx
- Connection pooling with Ecto
- Asset optimization with esbuild and tailwind minification
- Multi-node clustering for horizontal scaling via libcluster

## File Organization Patterns

- LiveViews: `lib/lightning_web/live/[context]_live/`
- Controllers: `lib/lightning_web/controllers/`
- API: `lib/lightning_web/controllers/api/`
- React components: `assets/js/`
- Tests mirror source structure in `test/`
- Migrations: `priv/repo/migrations/`
- Static assets: `priv/static/`

## Key Dependencies and Libraries

### Backend (Elixir)

- **Phoenix 1.7**: Web framework with LiveView
- **Ecto 3.13+**: Database ORM and query builder
- **Oban**: Background job processing
- **Bodyguard**: Authorization framework
- **Cloak**: Encryption for sensitive data
- **Timex**: Date/time utilities
- **Broadway + Kafka**: Event streaming
- **Y_ex**: Yjs bindings for collaborative editing (see
  `.claude/guidelines/yex-guidelines.md`)
- **Rambo**: External command execution (needs Rust)

### Frontend (JavaScript/TypeScript)

- **React 18**: UI library
- **@xyflow/react**: Workflow DAG visualization
- **Monaco Editor**: Code editor (VS Code editor)
- **Yjs**: CRDT for real-time collaboration
- **y-phoenix-channel**: Yjs + Phoenix Channels integration
- **Zustand**: State management
- **Immer**: Immutable state updates
- **Tailwind CSS**: Utility-first CSS framework
- **Vitest**: Testing framework
- **Playwright**: E2E testing

## Application Supervision and Runtime

### Main Supervision Tree (lib/lightning/application.ex)

Key supervised processes:

- **Repo**: Ecto database connection pool
- **Oban**: Background job processing with queues for `scheduler`, `background`,
  `workflow_runs`
- **PromEx**: Prometheus metrics collection
- **Phoenix.PubSub**: Real-time message broadcasting
- **Presence**: User presence tracking for collaborative editing
- **Endpoint**: Web server and request handling
- **libcluster**: Multi-node clustering via PostgreSQL

### Key Runtime Components

- **Runtime Manager** (lib/lightning/runtime): Executes JavaScript jobs in
  isolated environments
- **Kafka Integration** (lib/lightning/workflows/triggers): Event-driven
  workflow triggers
- **Workflows.Presence** (lib/lightning/workflows/presence.ex): Collaborative
  editing with edit priority system
- **Cachex**: ETS-based caching for performance

## Documentation and Communication

- Don't prefix items with \*\* unless the entire item should be bold
- Use issue numbers for branch names with dash separation
- Follow "strong opinions, weakly held" principle
- Ask for clarification when uncertain
- When running npm or npx commands, always cd into the assets directory first
- We don't need to use MIX_ENV=test for most test related commands, ecto.create is the only one that explicitly needs the env set
- You don't need to build using `npm run ...`, phoenix automatically builds as
  we go, if you want to check for build failures or warnings etc you can either
  use Tidewave MCP to check the logs, or run `mix esbuild default`
- When checking for JS/TS issues, prefer mcp__ide__getDiagnostics over tsc
- never commit the .context directory, this is a symlink to another folder shared across branches and worktrees