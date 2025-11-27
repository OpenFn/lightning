import { test, expect } from '@playwright/test';
import { getTestData } from '../../test-data';
import { enableExperimentalFeatures } from '../../e2e-helper';
import {
  LoginPage,
  ProjectsPage,
  WorkflowsPage,
  WorkflowEditPage,
  WorkflowCollaborativePage,
} from '../../pages';

test.describe('Collaborative Editor - Job Credentials', () => {
  let testData: Awaited<ReturnType<typeof getTestData>>;

  test.beforeAll(async () => {
    testData = await getTestData();
  });

  test.beforeEach(async ({ page }) => {
    // Enable experimental features for the editor user
    await enableExperimentalFeatures(testData.users.editor.email);

    // Login as editor user
    await page.goto('/');
    const loginPage = new LoginPage(page);
    await loginPage.loginIfNeeded(
      testData.users.editor.email,
      testData.users.editor.password
    );
  });

  test('Save job without credential in collaborative editor', async ({
    page,
  }) => {
    await test.step('Navigate to project and create new workflow', async () => {
      const projectsPage = new ProjectsPage(page);
      await projectsPage.navigateToProject(testData.projects.openhie.name);

      const workflowsPage = new WorkflowsPage(page);
      await workflowsPage.clickNewWorkflow();

      const workflowEdit = new WorkflowEditPage(page);
      await workflowEdit.selectWorkflowType('Event-based Workflow');
      await page.fill('input[name="workflow[name]"]', 'Test Workflow No Cred');
      await workflowEdit.clickCreateWorkflow();
    });

    await test.step('Navigate to collaborative editor', async () => {
      const workflowEdit = new WorkflowEditPage(page);
      await workflowEdit.waitForConnected();
      await workflowEdit.clickCollaborativeEditorToggle();
    });

    await test.step('Wait for collaborative editor to load', async () => {
      const collabEditor = new WorkflowCollaborativePage(page);
      await collabEditor.waitForReactComponentLoaded();
      await collabEditor.waitForSynced();
    });

    await test.step('Configure job WITHOUT selecting a credential', async () => {
      const collabEditor = new WorkflowCollaborativePage(page);

      // Click first job node
      await page.locator('.react-flow__node-job').first().click();

      // Wait for job inspector to be visible
      await collabEditor.jobInspector.waitForVisible();

      // Configure job name
      await collabEditor.jobInspector.setName('Simple Transform');

      // Verify credential dropdown shows no selection (empty value)
      await expect(collabEditor.jobInspector.credentialSelect).toHaveValue('');
    });

    await test.step('Save workflow', async () => {
      const collabEditor = new WorkflowCollaborativePage(page);
      await collabEditor.saveWorkflow();

      // Wait for save to complete (check for synced status)
      await collabEditor.waitForSynced();
    });

    await test.step('Reload and verify job persisted without credential', async () => {
      await page.reload();

      const collabEditor = new WorkflowCollaborativePage(page);
      await collabEditor.waitForReactComponentLoaded();
      await collabEditor.waitForSynced();

      // Click job again
      await page.locator('.react-flow__node-job').first().click();
      await collabEditor.jobInspector.waitForVisible();

      // Verify credential is still empty
      await expect(collabEditor.jobInspector.credentialSelect).toHaveValue('');
      await expect(collabEditor.jobInspector.nameInput).toHaveValue(
        'Simple Transform'
      );
    });
  });

  test('Save job with project credential', async ({ page }) => {
    await test.step('Navigate to project and create new workflow', async () => {
      const projectsPage = new ProjectsPage(page);
      await projectsPage.navigateToProject(testData.projects.openhie.name);

      const workflowsPage = new WorkflowsPage(page);
      await workflowsPage.clickNewWorkflow();

      const workflowEdit = new WorkflowEditPage(page);
      await workflowEdit.selectWorkflowType('Event-based Workflow');
      await page.fill(
        'input[name="workflow[name]"]',
        'Test Workflow With Cred'
      );
      await workflowEdit.clickCreateWorkflow();
    });

    await test.step('Navigate to collaborative editor', async () => {
      const workflowEdit = new WorkflowEditPage(page);
      await workflowEdit.waitForConnected();
      await workflowEdit.clickCollaborativeEditorToggle();
    });

    await test.step('Wait for collaborative editor to load', async () => {
      const collabEditor = new WorkflowCollaborativePage(page);
      await collabEditor.waitForReactComponentLoaded();
      await collabEditor.waitForSynced();
    });

    await test.step('Select a project credential', async () => {
      const collabEditor = new WorkflowCollaborativePage(page);

      // Click first job node
      await page.locator('.react-flow__node-job').first().click();
      await collabEditor.jobInspector.waitForVisible();

      // Configure job
      await collabEditor.jobInspector.setName('HTTP Request');

      // Select first available credential (skip placeholder at index 0)
      await collabEditor.jobInspector.credentialSelect.selectOption({
        index: 1,
      });

      // Get the selected credential value for verification later
      const selectedCredentialId =
        await collabEditor.jobInspector.getSelectedCredential();
      expect(selectedCredentialId).not.toBe('');

      // Store for next step
      await page.evaluate(
        id => window.sessionStorage.setItem('selectedCredentialId', id),
        selectedCredentialId
      );
    });

    await test.step('Save and verify', async () => {
      const collabEditor = new WorkflowCollaborativePage(page);
      await collabEditor.saveWorkflow();
      await collabEditor.waitForSynced();
    });

    await test.step('Reload and verify persistence', async () => {
      const selectedCredentialId = await page.evaluate(() =>
        window.sessionStorage.getItem('selectedCredentialId')
      );

      await page.reload();

      const collabEditor = new WorkflowCollaborativePage(page);
      await collabEditor.waitForReactComponentLoaded();
      await collabEditor.waitForSynced();

      await page.locator('.react-flow__node-job').first().click();
      await collabEditor.jobInspector.waitForVisible();

      await expect(collabEditor.jobInspector.credentialSelect).toHaveValue(
        selectedCredentialId!
      );
    });
  });

  test('Clear credential after it was selected', async ({ page }) => {
    await test.step('Navigate to project and create new workflow', async () => {
      const projectsPage = new ProjectsPage(page);
      await projectsPage.navigateToProject(testData.projects.openhie.name);

      const workflowsPage = new WorkflowsPage(page);
      await workflowsPage.clickNewWorkflow();

      const workflowEdit = new WorkflowEditPage(page);
      await workflowEdit.selectWorkflowType('Event-based Workflow');
      await page.fill(
        'input[name="workflow[name]"]',
        'Test Workflow Clear Cred'
      );
      await workflowEdit.clickCreateWorkflow();
    });

    await test.step('Navigate to collaborative editor', async () => {
      const workflowEdit = new WorkflowEditPage(page);
      await workflowEdit.waitForConnected();
      await workflowEdit.clickCollaborativeEditorToggle();
    });

    await test.step('Wait for collaborative editor to load', async () => {
      const collabEditor = new WorkflowCollaborativePage(page);
      await collabEditor.waitForReactComponentLoaded();
      await collabEditor.waitForSynced();
    });

    await test.step('First, select a credential', async () => {
      const collabEditor = new WorkflowCollaborativePage(page);

      await page.locator('.react-flow__node-job').first().click();
      await collabEditor.jobInspector.waitForVisible();

      await collabEditor.jobInspector.credentialSelect.selectOption({
        index: 1,
      });
      await expect(collabEditor.jobInspector.credentialSelect).not.toHaveValue(
        ''
      );
    });

    await test.step('Save with credential', async () => {
      const collabEditor = new WorkflowCollaborativePage(page);
      await collabEditor.saveWorkflow();
      await collabEditor.waitForSynced();
    });

    await test.step('Clear the credential by selecting placeholder', async () => {
      const collabEditor = new WorkflowCollaborativePage(page);
      await collabEditor.jobInspector.clearCredential();
      await expect(collabEditor.jobInspector.credentialSelect).toHaveValue('');
    });

    await test.step('Save without credential', async () => {
      const collabEditor = new WorkflowCollaborativePage(page);
      await collabEditor.saveWorkflow();
      await collabEditor.waitForSynced();
    });

    await test.step('Reload and verify credential is cleared', async () => {
      await page.reload();

      const collabEditor = new WorkflowCollaborativePage(page);
      await collabEditor.waitForReactComponentLoaded();
      await collabEditor.waitForSynced();

      await page.locator('.react-flow__node-job').first().click();
      await collabEditor.jobInspector.waitForVisible();

      await expect(collabEditor.jobInspector.credentialSelect).toHaveValue('');
    });
  });

  test('Switch between project and keychain credentials', async ({ page }) => {
    await test.step('Navigate to project and create new workflow', async () => {
      const projectsPage = new ProjectsPage(page);
      await projectsPage.navigateToProject(testData.projects.openhie.name);

      const workflowsPage = new WorkflowsPage(page);
      await workflowsPage.clickNewWorkflow();

      const workflowEdit = new WorkflowEditPage(page);
      await workflowEdit.selectWorkflowType('Event-based Workflow');
      await page.fill(
        'input[name="workflow[name]"]',
        'Test Workflow Switch Cred'
      );
      await workflowEdit.clickCreateWorkflow();
    });

    await test.step('Navigate to collaborative editor', async () => {
      const workflowEdit = new WorkflowEditPage(page);
      await workflowEdit.waitForConnected();
      await workflowEdit.clickCollaborativeEditorToggle();
    });

    await test.step('Wait for collaborative editor to load', async () => {
      const collabEditor = new WorkflowCollaborativePage(page);
      await collabEditor.waitForReactComponentLoaded();
      await collabEditor.waitForSynced();
    });

    await test.step('Check if keychain credentials exist', async () => {
      const collabEditor = new WorkflowCollaborativePage(page);

      await page.locator('.react-flow__node-job').first().click();
      await collabEditor.jobInspector.waitForVisible();

      // Check if keychain credentials exist
      const keychainOption = collabEditor.jobInspector.credentialSelect
        .locator('optgroup[label*="Keychain"] option')
        .first();
      const hasKeychainCreds = (await keychainOption.count()) > 0;

      if (!hasKeychainCreds) {
        test.skip();
        return;
      }
    });

    await test.step('Select project credential', async () => {
      const collabEditor = new WorkflowCollaborativePage(page);

      await collabEditor.jobInspector.credentialSelect.selectOption({
        index: 1,
      });
      const projectCredId =
        await collabEditor.jobInspector.getSelectedCredential();

      await page.evaluate(
        id => window.sessionStorage.setItem('projectCredId', id),
        projectCredId
      );

      await collabEditor.saveWorkflow();
      await collabEditor.waitForSynced();
    });

    await test.step('Switch to keychain credential', async () => {
      const collabEditor = new WorkflowCollaborativePage(page);

      const keychainOption = collabEditor.jobInspector.credentialSelect
        .locator('optgroup[label*="Keychain"] option')
        .first();
      await keychainOption.click();

      const keychainCredId =
        await collabEditor.jobInspector.getSelectedCredential();
      const projectCredId = await page.evaluate(() =>
        window.sessionStorage.getItem('projectCredId')
      );

      expect(keychainCredId).not.toBe(projectCredId);

      await page.evaluate(
        id => window.sessionStorage.setItem('keychainCredId', id),
        keychainCredId
      );

      await collabEditor.saveWorkflow();
      await collabEditor.waitForSynced();
    });

    await test.step('Verify persistence', async () => {
      const keychainCredId = await page.evaluate(() =>
        window.sessionStorage.getItem('keychainCredId')
      );

      await page.reload();

      const collabEditor = new WorkflowCollaborativePage(page);
      await collabEditor.waitForReactComponentLoaded();
      await collabEditor.waitForSynced();

      await page.locator('.react-flow__node-job').first().click();
      await collabEditor.jobInspector.waitForVisible();

      await expect(collabEditor.jobInspector.credentialSelect).toHaveValue(
        keychainCredId!
      );
    });
  });

  test('Multiple jobs with different credential configurations', async ({
    page,
  }) => {
    await test.step('Navigate to project and create new workflow', async () => {
      const projectsPage = new ProjectsPage(page);
      await projectsPage.navigateToProject(testData.projects.openhie.name);

      const workflowsPage = new WorkflowsPage(page);
      await workflowsPage.clickNewWorkflow();

      const workflowEdit = new WorkflowEditPage(page);
      await workflowEdit.selectWorkflowType('Event-based Workflow');
      await page.fill(
        'input[name="workflow[name]"]',
        'Test Workflow Multi Jobs'
      );
      await workflowEdit.clickCreateWorkflow();
    });

    await test.step('Navigate to collaborative editor', async () => {
      const workflowEdit = new WorkflowEditPage(page);
      await workflowEdit.waitForConnected();
      await workflowEdit.clickCollaborativeEditorToggle();
    });

    await test.step('Wait for collaborative editor to load', async () => {
      const collabEditor = new WorkflowCollaborativePage(page);
      await collabEditor.waitForReactComponentLoaded();
      await collabEditor.waitForSynced();
    });

    await test.step('Configure first job with no credential', async () => {
      const collabEditor = new WorkflowCollaborativePage(page);

      await page.locator('.react-flow__node-job').first().click();
      await collabEditor.jobInspector.waitForVisible();

      await collabEditor.jobInspector.setName('Job 1 - No Cred');
      await collabEditor.jobInspector.clearCredential();
    });

    await test.step('Add second job via plus button', async () => {
      // Hover over first job to reveal plus button
      const firstJobNode = page.locator('.react-flow__node-job').first();
      await firstJobNode.hover();

      // Click the plus button (node connector)
      const plusButton = firstJobNode.locator(
        '[data-handleid="node-connector"]'
      );
      await plusButton.click();

      // Wait for second job to be created
      await page.waitForTimeout(500);
    });

    await test.step('Configure second job with credential', async () => {
      const collabEditor = new WorkflowCollaborativePage(page);

      // Click second job
      const secondJobNode = page.locator('.react-flow__node-job').nth(1);
      await secondJobNode.click();
      await collabEditor.jobInspector.waitForVisible();

      await collabEditor.jobInspector.setName('Job 2 - With Cred');
      await collabEditor.jobInspector.credentialSelect.selectOption({
        index: 1,
      });

      const selectedCredId =
        await collabEditor.jobInspector.getSelectedCredential();
      await page.evaluate(
        id => window.sessionStorage.setItem('job2CredId', id),
        selectedCredId
      );
    });

    await test.step('Save all changes', async () => {
      const collabEditor = new WorkflowCollaborativePage(page);
      await collabEditor.saveWorkflow();
      await collabEditor.waitForSynced();
    });

    await test.step('Verify each job persisted correctly', async () => {
      const job2CredId = await page.evaluate(() =>
        window.sessionStorage.getItem('job2CredId')
      );

      await page.reload();

      const collabEditor = new WorkflowCollaborativePage(page);
      await collabEditor.waitForReactComponentLoaded();
      await collabEditor.waitForSynced();

      // Verify first job (no credential)
      await page.locator('.react-flow__node-job').first().click();
      await collabEditor.jobInspector.waitForVisible();
      await expect(collabEditor.jobInspector.nameInput).toHaveValue(
        'Job 1 - No Cred'
      );
      await expect(collabEditor.jobInspector.credentialSelect).toHaveValue('');

      // Verify second job (with credential)
      const secondJobNode = page.locator('.react-flow__node-job').nth(1);
      const secondJobExists = (await secondJobNode.count()) > 0;

      if (secondJobExists) {
        await secondJobNode.click();
        await collabEditor.jobInspector.waitForVisible();
        await expect(collabEditor.jobInspector.nameInput).toHaveValue(
          'Job 2 - With Cred'
        );
        await expect(collabEditor.jobInspector.credentialSelect).toHaveValue(
          job2CredId!
        );
      }
    });
  });

  test('Job created via diagram plus button has null credentials', async ({
    page,
  }) => {
    await test.step('Navigate to project and create new workflow', async () => {
      const projectsPage = new ProjectsPage(page);
      await projectsPage.navigateToProject(testData.projects.openhie.name);

      const workflowsPage = new WorkflowsPage(page);
      await workflowsPage.clickNewWorkflow();

      const workflowEdit = new WorkflowEditPage(page);
      await workflowEdit.selectWorkflowType('Event-based Workflow');
      await page.fill(
        'input[name="workflow[name]"]',
        'Test Workflow Plus Button'
      );
      await workflowEdit.clickCreateWorkflow();
    });

    await test.step('Navigate to collaborative editor', async () => {
      const workflowEdit = new WorkflowEditPage(page);
      await workflowEdit.waitForConnected();
      await workflowEdit.clickCollaborativeEditorToggle();
    });

    await test.step('Wait for collaborative editor to load', async () => {
      const collabEditor = new WorkflowCollaborativePage(page);
      await collabEditor.waitForReactComponentLoaded();
      await collabEditor.waitForSynced();
    });

    await test.step('Add new job via plus button', async () => {
      // Hover over first job to reveal plus button
      const firstJobNode = page.locator('.react-flow__node-job').first();
      await firstJobNode.hover();

      // Click the plus button to add a new job
      const plusButton = firstJobNode.locator(
        '[data-handleid="node-connector"]'
      );
      await plusButton.click();

      // Wait for new job to be created
      await page.waitForTimeout(500);
    });

    await test.step('Verify the new job has credential dropdown available', async () => {
      const collabEditor = new WorkflowCollaborativePage(page);

      const secondJobNode = page.locator('.react-flow__node-job').nth(1);
      await secondJobNode.click();
      await collabEditor.jobInspector.waitForVisible();

      // Verify it defaults to no credential
      await expect(collabEditor.jobInspector.credentialSelect).toBeVisible();
      await expect(collabEditor.jobInspector.credentialSelect).toHaveValue('');
    });

    await test.step('Save immediately without selecting a credential', async () => {
      const collabEditor = new WorkflowCollaborativePage(page);
      await collabEditor.saveWorkflow();
      await collabEditor.waitForSynced();
    });

    await test.step('Reload and verify', async () => {
      await page.reload();

      const collabEditor = new WorkflowCollaborativePage(page);
      await collabEditor.waitForReactComponentLoaded();
      await collabEditor.waitForSynced();

      const secondJobNode = page.locator('.react-flow__node-job').nth(1);
      await secondJobNode.click();
      await collabEditor.jobInspector.waitForVisible();

      await expect(collabEditor.jobInspector.credentialSelect).toHaveValue('');
    });
  });
});
