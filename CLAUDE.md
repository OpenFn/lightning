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
MIX_ENV=test mix test
# Don't use -v flag with mix test

# Code quality checks
mix verify  # runs all checks below
mix format --check-formatted
mix dialyzer
mix credo --strict --all
mix sobelow
MIX_ENV=test mix coveralls.html

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

# Linting
npm run lint

# Check types across project (only when explicitly asked)
npm run check
```

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
- Migrations: `priv/repo/migrations/`
- Schemas alongside contexts in `lib/lightning/`

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

### React Development

- Props from LiveView React mounting are **underscore_cased**, not camelCased
- Components receive underscore_cased props when mounted via LiveView
- Phoenix auto-builds assets; use `mix esbuild default` to check build issues

### Testing Requirements

- Write comprehensive ExUnit tests
- Use ExMachina for test data generation
- Follow TDD practices
- Don't use `-v` flag with mix test

### Code Quality Standards

- Line width under 80 characters
- Run `mix verify` before committing (format, dialyzer, credo, sobelow,
  coveralls)
- Use TypeScript strictly in frontend
- Follow security best practices (authentication, authorization, input
  validation)

### Feature Development

- Label work units with `Uxx` prefixes
- Minimize changes outside current unit scope
- Highlight impacts on past/future units

## Worker System

Lightning uses external Node.js workers for job execution:

- WebSocket communication with JWT authentication
- Two-layer security: Worker Token (shared secret) + Run Token
  (Lightning-signed)
- Generate keys with: `mix lightning.gen_worker_keys`
- Environment variables: `WORKER_RUNS_PRIVATE_KEY`, `WORKER_SECRET`,
  `WORKER_LIGHTNING_PUBLIC_KEY`

## Deployment Considerations

### Required Environment Variables

- `PRIMARY_ENCRYPTION_KEY`: For credentials/TOTP encryption (generate with
  `mix lightning.gen_encryption_key`)
- Worker authentication keys (see above)
- Database URL and connection settings

### Security

- Encryption at rest for credentials and sensitive data
- JWT-based worker authentication
- OAuth2 integration support
- Strong parameter validation

## Performance Optimization

- Database indexing for query performance
- Ecto preloading to avoid N+1 queries
- Caching strategies (ETS, Redis via Cachex)
- Background job processing with Oban
- Prometheus metrics via PromEx

## File Organization Patterns

- LiveViews: `lib/lightning_web/live/[context]_live/`
- Controllers: `lib/lightning_web/controllers/`
- API: `lib/lightning_web/controllers/api/`
- React components: `assets/js/`
- Tests mirror source structure in `test/`

## Documentation and Communication

- Don't prefix items with \*\* unless entire item should be bold
- Use issue numbers for branch names with dash separation
- Follow "strong opinions, weakly held" principle
- Ask for clarification when uncertain
- You don't need to build using `npm run ...`, phoenix automatically builds as
  we go, if you want to check for build failures or warnings etc you can either
  use Tidewave MCP to check the logs, or run `mix esbuild default`
- When running npm or npx commands, always cd into the assets directory
  beforehand.
- When checking for JS/TS issues, prefer mcp__ide__getDiagnostics over tsc
