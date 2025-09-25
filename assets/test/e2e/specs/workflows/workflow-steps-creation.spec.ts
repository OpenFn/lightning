import { test, expect } from "@playwright/test";
import { getTestData } from "../../test-data";
import { WorkflowEditPage, WorkflowsPage } from "../../pages";

test.describe("US-010: Workflow Steps - Basic Creation", () => {
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

  test("TC-010: Add and configure workflow steps", async ({ page }) => {
    const workflowsPage = new WorkflowsPage(page);
    const workflowEdit = new WorkflowEditPage(page);

    // Test follows exact steps from US-010 documentation

    // 1. Create a new event-based workflow
    // TODO: Update the user stories to reflect that you can't create a blank
    // workflow, you pick either event-based or scheduled.
    await workflowsPage.navigateToProject("openhie-project");

    await workflowsPage.waitForConnected();
    await workflowsPage.clickNewWorkflow();
    await workflowEdit.selectWorkflowType("Event-based Workflow");
    await workflowEdit.clickCreateWorkflow();

    // 2. Configure the first job
    await workflowEdit.diagram.clickJobNodeByIndex(0);
    // TODO: assert the canvas node is selected, has a border or something

    await expect(workflowEdit.jobForm(0).workflowForm).toBeAttached();

    await workflowEdit
      .jobForm(0)
      .adaptorSelect.selectOption("@openfn/language-http");

    await expect(workflowEdit.jobForm(0).versionSelect).toHaveValue(
      "@openfn/language-http@7.2.2"
    );
    await workflowEdit.jobForm(0).nameInput.click();
    // TODO: is there a better way to clear the text box? Or can fill just overwrite?
    // await workflowEdit.jobForm(0).nameInput.press("ControlOrMeta+a");
    await workflowEdit.jobForm(0).nameInput.fill("Fetch User Data");
    // Verify canvas node text is updated, right now I can't select it, z-index issue?
    // Verify the node icon is now the HTTP icon, not the common icon.

    // 3. Add second step: Common adaptor
    // - Click "+" button after first step
    // - Select Common adaptor
    // - Name: "Transform Data"
    // - Description: "Process and validate user data"

    // TODO: reference 'fit-view' button instead of hardcoding button index
    await workflowEdit.diagram.clickFitView();

    await workflowEdit.diagram.clickNodePlusButtonOn("Fetch User Data");
    await workflowEdit.diagram.fillPlaceholderNodeName("Transform Data");

    await expect(workflowEdit.jobForm(1).header).toHaveText("Transform Data");

    await expect(workflowEdit.jobForm(1).versionSelect).toHaveValue(
      "@openfn/language-common@latest"
    );

    // TODO: expect the save button to have the red dot, indicating unsaved changes.
    await expect(workflowEdit.unsavedChangesIndicator()).toBeVisible();

    await workflowEdit.clickSaveWorkflow();
    await workflowEdit.expectFlashMessage("Workflow saved successfully.");
    // TODO: what is getTestId

    // 2. Add first step: HTTP adaptor
    // - Click "Add Step" or "+" button
    // - Verify adaptor selection dialog appears
    // - Browse available adaptors
    // - Select HTTP adaptor
    // - Choose latest version
    // TODO: There is no Add or Confirm button, changes are immediate
    // - Click "Add" or confirm

    // 3. Configure first step:
    // - Name: "Fetch User Data"
    // TODO: there is no such thing as description yet
    // - Description: "Retrieve users from external API"
    // - Verify step appears on canvas connected to trigger

    // 5. Add third step: PostgreSQL adaptor (or another available database adaptor)
    // - Name: "Save to Database"
    // - Description: "Insert processed users into database"

    // 6. Verify workflow structure:
    // - All steps appear visually connected with arrows
    // - Step names display clearly on the canvas
    // - Steps are ordered visually (numbered or sequential)

    // 7. Test step selection:
    // - Click on each step
    // - Verify step is highlighted/selected

    // 8. Save workflow

    // 9. Reopen the workflow and verify the structure persists
  });
});
