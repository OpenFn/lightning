import { test, expect } from "@playwright/test";
import { getTestData } from "../../test-data";
import { WorkflowEditPage, WorkflowsPage } from "../../pages";

test.describe("US-022: Workflow Steps - Add and Configure", () => {
  let testData: Awaited<ReturnType<typeof getTestData>>;

  test.beforeAll(async () => {
    testData = await getTestData();
  });

  test.beforeEach(async ({ page }) => {
    // Login as editor user
    await page.goto("/");
    const loginForm = page.locator("#login form");
    if (await loginForm.isVisible()) {
      await page.fill('input[name="user[email]"]', testData.users.editor.email);
      await page.fill(
        'input[name="user[password]"]',
        testData.users.editor.password
      );
      await page.click('button[type="submit"]');
      await page.waitForLoadState("networkidle");
    }
  });

  test("TC-022: Add and configure workflow steps", async ({ page }) => {
    const workflowsPage = new WorkflowsPage(page);
    const workflowEdit = new WorkflowEditPage(page);

    // Test follows exact steps from US-022 documentation

    // 1. Create a new event-based workflow
    await workflowsPage.navigateToProject("openhie-project");

    await workflowsPage.clickNewWorkflow();
    await workflowEdit.selectWorkflowType("Event-based Workflow");
    await workflowEdit.clickCreateWorkflow();

    // 2. Configure the first job
    await workflowEdit.diagram.clickJobNodeByIndex(0);

    // Verify job form is displayed in sidebar
    await expect(workflowEdit.jobForm(0).workflowForm).toBeAttached();

    await workflowEdit
      .jobForm(0)
      .adaptorSelect.selectOption("@openfn/language-http");

    await expect(workflowEdit.jobForm(0).versionSelect).toHaveValue(
      "@openfn/language-http@7.2.2"
    );
    await workflowEdit.jobForm(0).nameInput.click();
    await workflowEdit.jobForm(0).nameInput.fill("Fetch User Data");

    // 3. Add second job: Common adaptor
    await workflowEdit.diagram.clickFitView();

    await workflowEdit.diagram.clickNodePlusButtonOn("Fetch User Data");
    await workflowEdit.diagram.fillPlaceholderNodeName("Transform Data");

    await expect(workflowEdit.jobForm(1).header).toHaveText("Transform Data");

    await expect(workflowEdit.jobForm(1).versionSelect).toHaveValue(
      "@openfn/language-common@latest"
    );

    // 4. Verify unsaved changes indicator and save
    await expect(workflowEdit.unsavedChangesIndicator()).toBeVisible();

    await workflowEdit.clickSaveWorkflow();
    await workflowEdit.expectFlashMessage("Workflow saved successfully.");

    // 5. Add third job: PostgreSQL adaptor
    await workflowEdit.diagram.clickNodePlusButtonOn("Transform Data");
    await workflowEdit.diagram.fillPlaceholderNodeName("Save to Database");

    await expect(workflowEdit.jobForm(2).header).toHaveText("Save to Database");

    // Select PostgreSQL adaptor (or fallback to another database adaptor)
    await workflowEdit.jobForm(2).adaptorSelect.selectOption("postgresql");

    // Verify PostgreSQL adaptor version is selected
    await expect(workflowEdit.jobForm(2).versionSelect).toHaveValue(
      /@openfn\/language-postgresql@\d\.\d\.\d/
    );

    // 6. Verify workflow structure
    // Check that all jobs appear visually connected with arrows
    await workflowEdit.diagram.verifyNodeExists("Fetch User Data");
    await workflowEdit.diagram.verifyNodeExists("Transform Data");
    await workflowEdit.diagram.verifyNodeExists("Save to Database");

    // 7. Test job selection
    // Click on each job and verify job form opens in sidebar
    await workflowEdit.diagram.clickNode("Fetch User Data");
    await expect(workflowEdit.jobForm(0).header).toHaveText(/Fetch User Data/);

    await workflowEdit.diagram.clickNode(" Transform Data ");
    console.log(workflowEdit.jobForm(1).header);
    await expect(workflowEdit.jobForm(1).header).toHaveText(/Transform Data/);

    await workflowEdit.diagram.clickNode("Save to Database");
    await expect(workflowEdit.jobForm(2).header).toHaveText("Save to Database");

    await workflowEdit.waitForSocketSettled();

    // 8. Save and verify persistence
    await workflowEdit.clickSaveWorkflow();
    await workflowEdit.expectFlashMessage("Workflow saved successfully.");

    await workflowsPage.clickMenuItem("Workflows");
    await workflowsPage.navigateToWorkflow("Event-based Workflow");

    // Verify all jobs still exist and structure persists
    await workflowEdit.diagram.verifyNodeExists("Fetch User Data");
    await workflowEdit.diagram.verifyNodeExists("Transform Data");
    await workflowEdit.diagram.verifyNodeExists("Save to Database");

    // Verify job configurations persist
    await workflowEdit.diagram.clickNode("Fetch User Data");
    await expect(workflowEdit.jobForm(0).versionSelect).toHaveValue(
      "@openfn/language-http@7.2.2"
    );

    await workflowEdit.diagram.clickNode("Transform Data");
    await expect(workflowEdit.jobForm(1).versionSelect).toHaveValue(
      "@openfn/language-common@latest"
    );

    await workflowEdit.diagram.clickNode("Save to Database");
    await expect(workflowEdit.jobForm(2).versionSelect).toHaveValue(
      /@openfn\/language-postgresql@\d\.\d\.\d/
    );
  });
});
