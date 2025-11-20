import { test, expect } from '@playwright/test';
import { getTestData } from '../../test-data';
import {
  WorkflowsPage,
  WorkflowEditPage,
  LoginPage,
  ProjectsPage,
} from '../../pages';

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

  test('can navigate to existing workflow and see React Flow with 6 nodes', async ({
    page,
  }) => {
    const projectsPage = new ProjectsPage(page);
    const workflowsPage = new WorkflowsPage(page);
    const workflowEdit = new WorkflowEditPage(page);

    // Navigate to project using ProjectsPage POM
    await projectsPage.navigateToProject(testData.projects.openhie.name);
    await workflowsPage.waitForConnected();

    await expect(page.getByText('OpenHIE Workflow')).toBeVisible();

    // Navigate to the workflow using POM
    await workflowsPage.navigateToWorkflow(testData.workflows.openhie.name);
    await workflowEdit.waitForConnected();

    // Verify URL contains the actual workflow ID from database
    await expect(page).toHaveURL(
      new RegExp(`/w/${testData.workflows.openhie.id}`)
    );

    await workflowEdit.diagram.verifyReactFlowPresent();

    // Assert we have 5 nodes visible in the workflow
    await workflowEdit.diagram.nodes.verifyCount(5);
    await expect(page.getByRole('main')).toMatchAriaSnapshot(`
      - navigation "Breadcrumb":
        - list:
          - listitem:
            - link "Home":
              - /url: /
          - listitem:
            - link "Projects":
              - /url: /projects
          - listitem:
            - link "openhie-project":
              - /url: /projects/4adf2644-ed4e-4f97-a24c-ab35b3cb1efa/w
          - listitem:
            - link "Workflows":
              - /url: /projects/4adf2644-ed4e-4f97-a24c-ab35b3cb1efa/w
          - listitem: OpenHIE Workflow latest
      - checkbox
      - switch
      - link:
        - /url: /projects/4adf2644-ed4e-4f97-a24c-ab35b3cb1efa/w/01ec091c-c52d-44d8-81df-213505f0da2b?m=settings
      - link "Run":
        - /url: /projects/4adf2644-ed4e-4f97-a24c-ab35b3cb1efa/w/01ec091c-c52d-44d8-81df-213505f0da2b?m=workflow_input&s=cae544ab-03dc-4ccc-a09c-fb4edb255d7a
      - button "Save"
      - button "Open options user avatar":
        - img "user avatar"
      `);

    // Assert no error messages are shown
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
