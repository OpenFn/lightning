# E2E Testing with Playwright

## Overview

End-to-end (E2E) tests validate complete user journeys through the Lightning
application using Playwright. These tests run against a dedicated test server
with an isolated database, ensuring tests don't interfere with development or
production environments.

**Testing Philosophy:**
- Test complete user workflows, not individual actions
- Use real backend systems (Phoenix, PostgreSQL) for integration confidence
- Maintain fast, stable tests through proper isolation and fixtures
- Leverage Page Object Model (POM) for maintainable test code
- Focus on user-visible behavior over implementation details

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

### Test File Naming

```typescript
// ✅ GOOD: Descriptive, feature-based names
workflow-creation.spec.ts
collaborative-editing.spec.ts
credential-management.spec.ts

// ❌ BAD: Generic or numbered names
test1.spec.ts
workflow.spec.ts
e2e-test.spec.ts
```

### Test Grouping with Tags

Use tags to organize and filter tests:

```typescript
test('workflow creation @smoke @critical', async ({ page }) => {
  // Critical smoke test - must pass before deployment
});

test('advanced workflow features @extended', async ({ page }) => {
  // Extended test suite - optional for quick feedback
});

test('real-time collaboration @collaborative @websocket', async ({ page }) => {
  // Tests requiring WebSocket/real-time features
});
```

**Run specific tags:**
```bash
npx playwright test --grep @smoke
npx playwright test --grep "@critical|@smoke"
npx playwright test --grep-invert @extended
```

## Test Data Management

### Using Test Data

Lightning provides test data through `test-data.ts`:

```typescript
import { getTestData } from '../../test-data';

test.describe('Workflow Tests', () => {
  let testData: Awaited<ReturnType<typeof getTestData>>;

  test.beforeAll(async () => {
    // Load test data once per suite
    testData = await getTestData();
  });

  test('navigate to workflow', async ({ page }) => {
    // Use real IDs from database
    await page.goto(`/projects/${testData.projects.openhie.id}/w`);

    // Use known workflow name
    await page.getByText(testData.workflows.openhie.name).click();
  });
});
```

### Test Data Structure

```typescript
{
  users: {
    editor: { id, email, password, firstName, lastName },
    viewer: { id, email, password, firstName, lastName },
    admin: { id, email, password, firstName, lastName },
  },
  projects: {
    openhie: { id, name, description },
    // ... other projects
  },
  workflows: {
    openhie: { id, name, projectId },
    // ... other workflows
  }
}
```

### Test Data Best Practices

**✅ DO: Use test data for navigation and assertions**
```typescript
test('open workflow', async ({ page }) => {
  const workflowId = testData.workflows.openhie.id;
  await page.goto(`/w/${workflowId}`);
  await expect(page).toHaveURL(new RegExp(`/w/${workflowId}`));
});
```

**✅ DO: Create new data for modification tests**
```typescript
test('create new workflow', async ({ page }) => {
  // Don't modify existing test data
  await page.getByRole('button', { name: 'New Workflow' }).click();
  await page.fill('[name="name"]', 'Test Workflow');
  // New workflow won't interfere with other tests
});
```

**❌ DON'T: Modify existing test data**
```typescript
test('delete workflow', async ({ page }) => {
  // BAD: Deleting test data breaks other tests
  await page.goto(`/w/${testData.workflows.openhie.id}`);
  await page.click('text=Delete');
});
```

## Writing Effective E2E Tests

### Test Structure: Complete User Journeys

**✅ GOOD: Test complete workflows**
```typescript
test('user can create and configure workflow', async ({ page }) => {
  // 1. Navigate to workflows
  await page.goto('/projects/123/w');

  // 2. Create workflow
  await page.getByRole('button', { name: 'New Workflow' }).click();
  await page.fill('[name="name"]', 'Data Pipeline');
  await page.click('text=Create');

  // 3. Add job
  await page.getByTestId('add-job').click();
  await page.fill('[name="job_name"]', 'Fetch Data');

  // 4. Configure and save
  await page.fill('[name="adaptor"]', '@openfn/language-http');
  await page.click('text=Save');

  // 5. Verify result
  await expect(page.getByText('Workflow saved')).toBeVisible();
  await expect(page.getByText('Fetch Data')).toBeVisible();
});
```

**❌ BAD: Fragmented actions**
```typescript
test('navigate to workflows', async ({ page }) => { /* ... */ });
test('click new workflow', async ({ page }) => { /* ... */ });
test('fill workflow name', async ({ page }) => { /* ... */ });
test('click create', async ({ page }) => { /* ... */ });
// Tests are too granular and dependent
```

### Using test.step() for Clarity

Break complex tests into logical steps:

```typescript
test('complete workflow lifecycle', async ({ page }) => {
  await test.step('Create workflow', async () => {
    await page.goto('/workflows/new');
    await page.fill('[name="name"]', 'ETL Pipeline');
    await page.click('text=Create');
  });

  await test.step('Add jobs', async () => {
    await page.getByTestId('add-job').click();
    await page.fill('[name="job_name"]', 'Extract');
    await page.click('text=Add another');
    await page.fill('[name="job_name"]', 'Transform');
  });

  await test.step('Execute workflow', async () => {
    await page.click('text=Run');
    await expect(page.getByText('Running')).toBeVisible();
  });
});
```

**Benefits:**
- Clear test report structure
- Easy to identify failing step
- Better trace viewer organization
- Self-documenting test logic

## Common Patterns

### Authentication

Use Page Object Models for login:

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

For tests requiring multiple users, see
`.claude/guidelines/e2e/collaborative-testing.md`.

### Waiting for Phoenix LiveView

Use `LiveViewPage` utilities for LiveView-specific waits:

```typescript
import { WorkflowEditPage } from '../pages';

test('workflow loads', async ({ page }) => {
  const workflowPage = new WorkflowEditPage(page);

  await page.goto('/w/123');

  // Wait for LiveView connection
  await workflowPage.waitForConnected();

  // Wait for socket to settle before assertions
  await workflowPage.waitForSocketSettled();

  // Now safe to interact
  await page.getByRole('button', { name: 'Add Job' }).click();
});
```

See `.claude/guidelines/e2e/phoenix-liveview.md` for comprehensive LiveView
testing patterns.

### Using Page Object Models

**✅ GOOD: Use POMs for reusable interactions**
```typescript
test('edit workflow', async ({ page }) => {
  const workflowEdit = new WorkflowEditPage(page);

  await page.goto('/w/123');
  await workflowEdit.waitForConnected();

  // Use POM methods
  await workflowEdit.setWorkflowName('Updated Name');
  await workflowEdit.diagram.clickNode('Job 1');
  await workflowEdit.jobForm(0).nameInput.fill('Updated Job');
  await workflowEdit.clickSaveWorkflow();

  // Assert using POM locators
  await expect(workflowEdit.unsavedChangesIndicator()).not.toBeVisible();
});
```

**❌ BAD: Inline selectors in tests**
```typescript
test('edit workflow', async ({ page }) => {
  await page.goto('/w/123');

  // Brittle selectors scattered throughout test
  await page.locator('.workflow-name input').fill('Updated Name');
  await page.locator('.react-flow-node').first().click();
  await page.locator('#job-form-0 input[name="name"]').fill('Updated Job');
  await page.locator('button:has-text("Save")').click();
});
```

See `.claude/guidelines/e2e/page-objects.md` for comprehensive POM patterns.

## Debugging E2E Tests

### Interactive UI Mode

Best for exploring and developing tests:

```bash
npm run test:e2e:ui
```

**Features:**
- Visual test runner with browser preview
- Step through tests with time travel
- Inspect locators with pick mode
- Watch mode for rapid iteration

### Debug Mode

Best for troubleshooting specific test failures:

```bash
npm run test:e2e:debug workflow.spec.ts
```

**Features:**
- Chromium Inspector opens automatically
- Set breakpoints in test code
- Step through actions one at a time
- Inspect page state at any point

### Trace Viewer

Automatically captured on first retry (configured in `playwright.config.ts`):

```bash
# After test failure with retry
npx playwright show-trace test-results/.../trace.zip
```

**Features:**
- Film strip view of test execution
- Network activity waterfall
- Console logs and errors
- DOM snapshots at each action
- Action timeline with precise timing

### Common Debugging Techniques

**1. Headed Mode (see browser)**:
```bash
npx playwright test --headed
```

**2. Pause execution in test**:
```typescript
test('debug test', async ({ page }) => {
  await page.goto('/workflows');

  // Pause and open inspector
  await page.pause();

  await page.click('text=New');
});
```

**3. Screenshot on failure**:
```typescript
test.afterEach(async ({ page }, testInfo) => {
  if (testInfo.status !== testInfo.expectedStatus) {
    await page.screenshot({
      path: `test-results/failure-${testInfo.title}.png`
    });
  }
});
```

**4. Verbose logging**:
```typescript
test('debug test', async ({ page }) => {
  // Log navigation
  page.on('console', msg => console.log('Browser log:', msg.text()));

  // Log requests
  page.on('request', req => console.log('Request:', req.url()));

  await page.goto('/workflows');
});
```

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
    {
      name: 'setup',
      testMatch: /global\.setup\.ts/,
    },
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

**Key Settings:**
- `fullyParallel: true` - Tests run in parallel (fast feedback)
- `workers: 1` in CI - Avoid database contention
- `trace: 'on-first-retry'` - Capture traces only when needed
- `webServer` - Automatically starts/stops e2e server

### Environment Variables

```bash
# E2E server port (default: 4003)
PORT=4003

# Database URL
DATABASE_URL=postgres://postgres:postgres@localhost/lightning_test_e2e

# Playwright specific
PWDEBUG=1              # Enable inspector
DEBUG=pw:api           # Verbose API logs
```

## Best Practices Summary

### ✅ DO

- **Test complete user workflows** from start to finish
- **Use Page Object Models** for maintainable, reusable code
- **Use test data** from `test-data.ts` for navigation and assertions
- **Wait for LiveView connections** using `waitForConnected()`
- **Use semantic locators** (role, label, text) over CSS selectors
- **Use test.step()** to organize complex tests
- **Reset database** between test runs (`bin/e2e reset`)
- **Test from user perspective** - what they see and do
- **Keep tests independent** - each test should run in isolation
- **Use traces for debugging** - capture on failure, not always

### ❌ DON'T

- **Fragment user journeys** into micro-tests
- **Hardcode selectors** in test files - use POMs
- **Modify test data** that other tests depend on
- **Use arbitrary timeouts** - use proper waiting strategies
- **Test implementation details** - focus on user behavior
- **Skip LiveView waits** - ensure handlers are attached
- **Make tests depend on each other** - maintain independence
- **Over-test trivial interactions** - focus on business value
- **Use XPath selectors** - prefer semantic/test-id locators
- **Run parallel tests in CI** without considering database isolation

## Related Guidelines

For deeper dives into specific topics:

- **Modern Playwright patterns**: `.claude/guidelines/e2e/playwright-patterns.md`
  - Auto-waiting and web-first assertions
  - Locator strategies and best practices
  - Network interception and mocking
  - Performance measurement

- **Phoenix LiveView testing**: `.claude/guidelines/e2e/phoenix-liveview.md`
  - LiveView connection handling
  - WebSocket message monitoring
  - Handling phx-* attributes and hooks
  - Race condition prevention

- **Page Object Model**: `.claude/guidelines/e2e/page-objects.md`
  - POM architecture and organization
  - Component composition patterns
  - Locator initialization strategies
  - Handling dynamic content

- **Collaborative testing**: `.claude/guidelines/e2e/collaborative-testing.md`
  - Multi-user test scenarios
  - WebSocket and presence testing
  - Y.Doc state verification
  - Real-time update validation

## Troubleshooting

### Database Issues

**Symptom**: Tests fail with database connection errors
```bash
# Solution: Verify PostgreSQL is running
pg_isready

# Reset database
bin/e2e reset --full
```

**Symptom**: Test data doesn't match expectations
```bash
# Solution: Reset snapshot and test data cache
bin/e2e setup
```

### Server Issues

**Symptom**: Tests timeout waiting for server
```bash
# Check if port is in use
lsof -i :4003

# Manually start server to check for errors
bin/e2e start
```

**Symptom**: Server starts but tests can't connect
```bash
# Verify server is accessible
curl http://localhost:4003

# Check firewall settings
```

### Test Flakiness

**Symptom**: Tests pass locally but fail in CI

1. **Check parallelization**: Set `workers: 1` in CI config
2. **Add proper waits**: Use `waitForConnected()` for LiveView
3. **Verify test isolation**: Each test should be independent
4. **Check for timing issues**: Replace fixed timeouts with conditions

**Symptom**: Tests fail intermittently

1. **Enable trace**: Set `trace: 'on'` temporarily
2. **Add debug logging**: Log key actions and state
3. **Check for race conditions**: Especially with WebSocket/LiveView
4. **Verify test data**: Ensure clean state before each test

### Common Errors

**Error**: "E2E infrastructure not available"
```bash
# Solution: Run setup
bin/e2e setup
```

**Error**: "Port 4003 already in use"
```bash
# Solution: Stop existing server
bin/e2e stop

# Or kill process
lsof -ti:4003 | xargs kill -9
```

**Error**: "Test data returned null"
```bash
# Solution: Database not seeded
bin/e2e setup
```

## Performance Optimization

### Fast Feedback Strategies

**1. Smoke Tests First**:
```bash
# Run critical tests first
npx playwright test --grep @smoke
```

**2. Parallel Execution** (local development):
```typescript
// playwright.config.ts
export default defineConfig({
  workers: undefined, // Use all available cores
  fullyParallel: true,
});
```

**3. Test Sharding** (CI/CD):
```bash
# Split tests across multiple machines
npx playwright test --shard=1/4
npx playwright test --shard=2/4
npx playwright test --shard=3/4
npx playwright test --shard=4/4
```

### Reducing Test Duration

**Avoid**: Unnecessary full-page navigation
```typescript
// ❌ SLOW: Navigate for every test
test.beforeEach(async ({ page }) => {
  await page.goto('/workflows');
});
```

**Use**: API-based setup when possible
```typescript
// ✅ FASTER: Set up via API, only navigate when testing UI
test('edit workflow', async ({ page, request }) => {
  // Create workflow via API
  const response = await request.post('/api/workflows', {
    data: { name: 'Test Workflow' }
  });
  const workflow = await response.json();

  // Navigate directly to edit page
  await page.goto(`/w/${workflow.id}`);
});
```

**Reuse**: Authentication state
```typescript
// global.setup.ts - authenticate once
const context = await browser.newContext();
// Login...
await context.storageState({ path: 'auth.json' });

// playwright.config.ts - reuse for all tests
use: {
  storageState: 'auth.json',
}
```

---

**Remember**: E2E tests provide confidence in complete user workflows. Keep
them focused on business-critical paths, maintain them with Page Object Models,
and ensure they're fast and stable through proper isolation and waiting
strategies.
