# Assets

Frontend build configuration, JavaScript/TypeScript source, styles, and test
suites for the Lightning application.

## E2E Testing

End-to-end test suite using Playwright covering critical user journeys and
workflows. Tests run against a dedicated test server with isolated database
state.

## Quick Start

```bash
# Run full test suite
npm run test:e2e

# Run with interactive UI (great for debugging)
npm run test:e2e:ui

# Run in debug mode (step through tests)
npm run test:e2e:debug
```

**First time setup**: Run `bin/e2e setup` from project root to initialize test
database with demo data.

## Local Development

### Running Tests

All test commands should be run from the assets directory:

```bash
cd assets

# Standard test run
npm run test:e2e

# Interactive mode with browser UI
npm run test:e2e:ui

# Debug specific test file
npm run test:e2e:debug auth.spec.ts
```

### Test Data Management

E2E tests use an isolated database (`lightning_test_e2e`) with demo data.
Between test runs:

```bash
# Fast reset using database snapshot (recommended)
bin/e2e reset

# Full database rebuild (when schema changes)
bin/e2e reset --full
```

## Architecture

The E2E system bridges Phoenix and Playwright through the `bin/e2e` coordination
script:

**Test Workflow:**

1. Playwright config detects if e2e server is running
2. If not, automatically starts test server via `bin/e2e server` (port 4003)
3. Server uses isolated test database with pre-seeded demo data
4. Tests execute against dedicated environment
5. Database resets between runs maintain test isolation

**Key Components:**

- `bin/e2e`: Phoenix-side test environment manager
- `assets/test/e2e/e2e-helper.ts`: TypeScript bridge to e2e script
- `assets/playwright.config.ts`: Test configuration and server coordination
- `assets/test/e2e/`: Test files and page objects

**Database Strategy:**

- Snapshot-based resets for speed (truncate + restore vs full rebuild)
- Demo data provides realistic relationships and constraints
- Isolated environment prevents interference with development database

## Configuration

### Environment Variables

```bash
# Test server (defaults)
PORT=4003
DATABASE_URL=postgres://postgres:postgres@localhost/lightning_test_e2e
MIX_ENV=dev
```

### Test Server

The e2e server runs independently from your main development server:

- **Development**: `http://localhost:4000`
- **E2E Testing**: `http://localhost:4003`

This separation ensures tests don't interfere with your development workflow.

## Troubleshooting

### "Tests fail but work manually"

- Database state: Run `bin/e2e reset` to clean test data
- Server issues: Check if e2e server is running on correct port (4003)
- Environment: Ensure test database exists (`bin/e2e setup`)

### "Server won't start"

- Port conflict: Check if port 4003 is in use
- Database connection: Verify PostgreSQL is running

### "Database errors during setup"

- Connection refused: Confirm PostgreSQL service is running
- Permission denied: Check database user permissions for `lightning_test_e2e`
- Migration issues: Run `bin/e2e reset --full` to rebuild from scratch
