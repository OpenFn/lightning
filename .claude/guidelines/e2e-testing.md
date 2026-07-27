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

# Debug specific test
npm run test:e2e:debug workflow.spec.ts
```

## Architecture Overview

### Test Environment

```
┌─────────────────────────────────────────────────────────────┐
│                    Playwright Test Runner                   │
│  (Node.js process, port 4003 baseURL)                      │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ├──► Browser Contexts (isolated sessions)
                 │    ├── User 1 Context (auth state)
                 │    └── User 2 Context (different auth)
                 │
                 ├──► bin/e2e Helper Integration
                 │    ├── Database reset (snapshot-based)
                 │    ├── Test data fetching
                 │    └── Server lifecycle management
                 │
                 └──► E2E Server (Phoenix)
                      ├── Port: 4003
                      ├── Database: lightning_test_e2e
                      ├── LiveView WebSocket connections
                      └── Real-time collaborative features
```

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

```
assets/test/e2e/
├── specs/                      # Test files organized by feature
│   ├── smoke/                  # Critical path tests
│   │   └── basic-navigation.spec.ts
│   ├── workflows/              # Workflow-specific tests
│   │   ├── workflow-creation.spec.ts
│   │   └── workflow-editing.spec.ts
│   └── collaborative/          # Collaborative editor tests
│       └── multi-user-editing.spec.ts
├── pages/                      # Page Object Models
│   ├── base/                   # Base classes
│   │   ├── index.ts
│   │   └── liveview.page.ts   # LiveView-specific utilities
│   ├── components/             # Reusable component POMs
│   │   ├── job-form.page.ts
│   │   └── workflow-diagram.page.ts
│   ├── login.page.ts
│   ├── projects.page.ts
│   ├── workflow-edit.page.ts  # Current LiveView editor
│   ├── workflow-collab.page.ts # NEW: Collaborative editor
│   └── index.ts
├── fixtures/                   # Custom fixtures (future)
├── helpers/                    # Test utilities (future)
├── e2e-helper.ts              # bin/e2e integration
├── test-data.ts               # Test data fetching/caching
└── global.setup.ts            # Global test setup
```

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

**Test data shape:**

```typescript
{
  users: {
    editor: { id, email, password, firstName, lastName },
    viewer: { id, email, password, firstName, lastName },
    admin: { id, email, password, firstName, lastName },
  },
  projects: {
    openhie: { id, name, description },
  },
  workflows: {
    openhie: { id, name, projectId },
  }
}
```

**✅ DO: Use test data for navigation and assertions.**
**✅ DO: Create new data for modification tests** — don't mutate seeded records.
**❌ DON'T: Delete or modify existing test data** — other tests depend on it.

## Writing E2E Tests

### Prefer complete user journeys

```typescript
// ✅ Test a full workflow, not individual clicks
test('user can create and configure workflow', async ({ page }) => {
  await page.goto('/projects/123/w');
  await page.getByRole('button', { name: 'New Workflow' }).click();
  await page.fill('[name="name"]', 'Data Pipeline');
  await page.click('text=Create');
  await page.getByTestId('add-job').click();
  await page.fill('[name="job_name"]', 'Fetch Data');
  await page.fill('[name="adaptor"]', '@openfn/language-http');
  await page.click('text=Save');
  await expect(page.getByText('Workflow saved')).toBeVisible();
});
```

Break complex tests into logical steps with `test.step()` so failures point to the right phase.

### Waiting for Phoenix LiveView

```typescript
import { WorkflowEditPage } from '../pages';

test('workflow loads', async ({ page }) => {
  const workflowPage = new WorkflowEditPage(page);
  await page.goto('/w/123');
  await workflowPage.waitForConnected();
  await workflowPage.waitForSocketSettled();
  await page.getByRole('button', { name: 'Add Job' }).click();
});
```

See `.claude/guidelines/e2e/phoenix-liveview.md` for comprehensive LiveView
testing patterns.

### Using Page Object Models

Use POMs for reusable interactions rather than inline CSS selectors scattered across tests. See `.claude/guidelines/e2e/page-objects.md` for patterns, and **always read an existing POM file before adding new methods** to avoid duplicating helpers like `loginIfNeeded`.

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

For tests requiring multiple users, see `.claude/guidelines/e2e/collaborative-testing.md`.

## Configuration

### playwright.config.ts

```typescript
export default defineConfig({
  testDir: './test/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'list',

  use: {
    baseURL: 'http://localhost:4003',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },

  projects: [
    { name: 'setup', testMatch: /global\.setup\.ts/ },
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
      dependencies: ['setup'],
    },
  ],

  webServer: {
    command: 'bin/e2e start',
    url: 'http://localhost:4003',
    reuseExistingServer: !process.env.CI,
    timeout: 60 * 1000,
  },
});
```

**Lightning specifics:**
- `workers: 1` in CI avoids database contention
- `webServer` automatically starts/stops the e2e server via `bin/e2e start`

### Environment variables

```bash
PORT=4003                                                              # E2E server port
DATABASE_URL=postgres://postgres:postgres@localhost/lightning_test_e2e # E2E database
PWDEBUG=1                                                              # Enable inspector
DEBUG=pw:api                                                           # Verbose API logs
```

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
