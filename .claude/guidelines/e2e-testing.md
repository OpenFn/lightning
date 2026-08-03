# E2E Testing with Playwright

## Overview

End-to-end (E2E) tests validate complete user journeys through the Lightning
application using Playwright. These tests run against a dedicated test server
with an isolated database, ensuring tests don't interfere with development or
production environments.

## Quick Start

```bash
# First time setup (from project root)
bin/e2e setup

# Run tests (from assets directory)
cd assets
npm run test:e2e

# Interactive debugging
npm run test:e2e:ui

# Debug a specific test — note the `--`, npm needs it to forward arguments
npm run test:e2e:debug -- specs/smoke/basic-navigation.spec.ts
```

## Architecture Overview

### Test Environment

- The Playwright runner is a Node process; `baseURL` defaults to `http://localhost:4003`, driven by
  `PORT`.
- It starts and stops a Phoenix server on that port against the `lightning_test_e2e` database, via
  the `webServer` entry in `playwright.config.ts`.
- `bin/e2e` handles database reset from a snapshot, test-data fetching and server lifecycle;
  `assets/test/e2e/e2e-helper.ts` is the TypeScript bridge to it.
- Everything runs in a single browser context today. Nothing in the suite opens a second one.

**Key Components:**
- **playwright.config.ts**: Test configuration, server coordination
- **bin/e2e**: Phoenix-side test environment manager
- **assets/test/e2e/e2e-helper.ts**: TypeScript bridge to bin/e2e script
- **assets/test/e2e/pages/**: Page Object Models
- **assets/test/e2e/specs/**: Test files organized by feature

### Database Management Strategy

Lightning uses a **snapshot-based reset strategy** for fast test isolation:

1. **Setup Phase** (`bin/e2e setup`):
   - Creates `lightning_test_e2e` database
   - Runs migrations
   - Seeds demo data (users, projects, workflows)
   - Creates snapshot for fast restore

2. **Test Execution**:
   - `global.setup.ts` runs before all tests
   - Calls `bin/e2e reset` to restore snapshot
   - Each test gets clean database state

3. **Benefits**:
   - **Fast**: Truncate + restore vs full rebuild (~1s vs ~10s)
   - **Isolated**: Each test run starts with known state
   - **Realistic**: Demo data includes relationships and constraints

## Test Organization

### Directory Structure

`ls assets/test/e2e/` rather than trusting a tree in a doc. The layout: `specs/` grouped by area
(`smoke/`, `collaborative/`), `pages/` for the Page Object Models (see
`.claude/guidelines/e2e/page-objects.md`), and at the root `e2e-helper.ts` (the bridge to
`bin/e2e`), `test-data.ts` and `global.setup.ts`.

### Test Grouping with Tags

Use tags to organize and filter tests:

```typescript
test('workflow creation @smoke @critical', async ({ page }) => {});
test('advanced workflow features @extended', async ({ page }) => {});
test('real-time collaboration @collaborative @websocket', async ({ page }) => {});
```

```bash
npx playwright test --grep @smoke
npx playwright test --grep "@critical|@smoke"
npx playwright test --grep-invert @extended
```

## Test Data Management

Lightning provides test data through `test-data.ts`:

```typescript
import { getTestData } from '../../test-data';

test.describe('Workflow Tests', () => {
  let testData: Awaited<ReturnType<typeof getTestData>>;

  test.beforeAll(async () => {
    testData = await getTestData();
  });

  test('navigate to workflow', async ({ page }) => {
    await page.goto(`/projects/${testData.projects.openhie.id}/w`);
    await page.getByText(testData.workflows.openhie.name).click();
  });
});
```

**Test data shape** (`test-data.ts:21-35`):

```typescript
{
  users: {
    admin: { email, password, id },   // demo@openfn.org
    editor: { email, password, id },  // editor@openfn.org
    viewer: { email, password, id },  // viewer@openfn.org
    super?: { email, password, id },  // optional
  },
  projects: {
    openhie: { id, name },
    dhis2: { id, name },
  },
  workflows: {
    openhie: { id, name, projectId },
    dhis2: { id, name, projectId },
  }
}
```

No `firstName` / `lastName` on a user, and no `description` on a project. `super` is optional, so
guard it before use.

**✅ DO: Use test data for navigation and assertions.**
**✅ DO: Create new data for modification tests** — don't mutate seeded records.
**❌ DON'T: Delete or modify existing test data** — other tests depend on it.

## Writing E2E Tests

### Prefer complete user journeys

Test a whole task the way a user performs it, not one click at a time. Break the journey into
`test.step()` blocks so a failure points at the phase that broke.

`assets/test/e2e/specs/collaborative/edge-validation.spec.ts` is the worked example to copy from:
it logs in, opens a workflow, and drags edges between nodes across several steps, all against real
routes and real selectors.

### Waiting for Phoenix LiveView

See `.claude/guidelines/e2e/phoenix-liveview.md §LiveView waits` for the wait primitives and
worked examples.

### Using Page Object Models

Use POMs for reusable interactions rather than inline CSS selectors scattered across tests. Read
the existing POM before adding a method — `loginIfNeeded` is the sort of helper that gets written
twice. See `.claude/guidelines/e2e/page-objects.md` for the class hierarchy and composition
patterns.

### Authentication

```typescript
import { LoginPage } from '../pages';

test.beforeEach(async ({ page }) => {
  const loginPage = new LoginPage(page);
  await loginPage.loginIfNeeded(
    testData.users.editor.email,
    testData.users.editor.password
  );
});
```

`loginIfNeeded` only fills the form when it is visible (`login.page.ts:59-63`), so it is safe to
call from a `beforeEach` that may already be authenticated.

**No spec runs more than one browser context yet** — `browser.newContext()` is 0 hits across
`assets/test/e2e/specs/`. For the shape a multi-user test should take, and the per-user feature
flag it needs, see `.claude/guidelines/e2e/collaborative-testing.md §Multi-user test template`.

## Configuration

### playwright.config.ts

`assets/playwright.config.ts` is 40 lines. Read it rather than a copy of it.

**Lightning specifics:**
- `workers: 1` in CI avoids database contention
- `webServer` automatically starts/stops the e2e server via `bin/e2e start`

### Environment variables

Both of these are defaulted by `bin/e2e.d/manager:6,9`, so you only set them to override:

```bash
PORT=4003                                                              # E2E server port
DATABASE_URL=postgres://postgres:postgres@localhost/lightning_test_e2e # E2E database
```

`playwright.config.ts:17,36` reads `PORT` for both `baseURL` and the `webServer` health check,
so changing it changes both.

## Related Guidelines

- **Modern Playwright patterns:** `.claude/guidelines/e2e/playwright-patterns.md`
- **Phoenix LiveView testing:** `.claude/guidelines/e2e/phoenix-liveview.md`
- **Page Object Model:** `.claude/guidelines/e2e/page-objects.md`
- **Collaborative testing:** `.claude/guidelines/e2e/collaborative-testing.md`

## Troubleshooting

### Database issues

```bash
# Reset database
bin/e2e reset --full

# Rebuild snapshot and test data cache
bin/e2e setup
```

### Server issues

```bash
# Check if port is in use
lsof -i :4003

# Stop existing server
bin/e2e stop
```

### Common errors

- **"E2E infrastructure not available"** → `bin/e2e setup`
- **"Port 4003 already in use"** → `bin/e2e stop` or `lsof -ti:4003 | xargs kill -9`
- **"Test data returned null"** → database not seeded, run `bin/e2e setup`
