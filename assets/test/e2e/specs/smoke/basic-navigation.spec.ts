import { test, expect } from '@playwright/test';

import {
  WorkflowsPage,
  WorkflowCollaborativePage,
  LoginPage,
  ProjectsPage,
} from '../../pages';
import { WorkflowDiagramPage } from '../../pages/components/workflow-diagram.page';
import { getTestData } from '../../test-data';

test('homepage loads successfully', async ({ page }) => {
  await page.goto('/');

  // Wait for the page to load
  await page.waitForLoadState('networkidle');

  // Check that we can see some basic Lightning content
  await expect(page).toHaveTitle(/Lightning/);
});

test.describe('Workflow Navigation with Dynamic Data', () => {
  let testData: Awaited<ReturnType<typeof getTestData>>;

  test.beforeAll(async () => {
    // Load test data once per test suite
    testData = await getTestData();
  });

  test.beforeEach(async ({ page }) => {
    // Login as editor user for most tests
    await page.goto('/');
    const loginPage = new LoginPage(page);
    await loginPage.loginIfNeeded(
      testData.users.editor.email,
      testData.users.editor.password
    );
  });

  test('can navigate to existing workflow and see React Flow with 5 nodes', async ({
    page,
  }) => {
    const projectsPage = new ProjectsPage(page);
    const workflowsPage = new WorkflowsPage(page);
    const collabEditor = new WorkflowCollaborativePage(page);
    const diagram = new WorkflowDiagramPage(page);

    // Navigate to project using ProjectsPage POM
    await projectsPage.navigateToProject(testData.projects.openhie.name);
    await workflowsPage.waitForConnected();

    await expect(page.getByText('OpenHIE Workflow')).toBeVisible();

    // Navigate to the workflow using POM. The workflow route now renders the
    // collaborative editor directly (the only editor).
    await workflowsPage.navigateToWorkflow(testData.workflows.openhie.name);

    // Verify URL contains the actual workflow ID from database
    await expect(page).toHaveURL(
      new RegExp(`/w/${testData.workflows.openhie.id}`)
    );

    // Wait for the collaborative editor to load and sync
    await collabEditor.waitForReactComponentLoaded();
    await collabEditor.waitForSynced();

    await diagram.verifyReactFlowPresent();

    // Assert we have 5 nodes visible in the workflow (4 jobs + 1 trigger)
    await diagram.nodes.verifyCount(5);

    // Assert no error states are shown
    await collabEditor.verifyNoErrors();

    const errorMessage = page.locator('text=Something went wrong');
    await expect(errorMessage).not.toBeVisible();

    const invariantError = page.locator('text=Invariant failed');
    await expect(invariantError).not.toBeVisible();
  });

  test('workflow data matches database state', async ({ page }) => {
    const projectsPage = new ProjectsPage(page);

    await projectsPage.navigateToProjects();

    // Verify the openhie project is visible using POM methods
    await projectsPage.verifyProjectVisible(testData.projects.openhie.name);

    // Verify that editor user sees at least one project
    await projectsPage.verifyProjectsListNotEmpty();
  });
});
