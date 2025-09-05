import { test, expect } from "@playwright/test";
import { getTestData } from "./test-data";

test.describe("Collaborative Editor with Dynamic Data", () => {
  let testData: Awaited<ReturnType<typeof getTestData>>;

  test.beforeAll(async () => {
    // Load test data once per test suite
    testData = await getTestData();
  });

  test("can navigate to collaborative editor and see React component", async ({
    page,
  }) => {
    await page.goto("/");

    // Check if we're already on the login page or need to navigate to it
    const loginForm = page.locator("#login form");
    const isOnLoginPage = await loginForm.isVisible();

    if (isOnLoginPage) {
      // Use dynamic test data for login
      await page
        .locator('input[name="user[email]"]')
        .fill(testData.users.editor.email);
      await page
        .locator('input[name="user[password]"]')
        .fill(testData.users.editor.password);
      await page.getByRole("button", { name: "Log in" }).click();
    }
    await page.waitForLoadState("networkidle");

    // Use dynamic test data for project navigation
    await page
      .getByRole("cell", { name: testData.projects.openhie.name })
      .click();
    await page.waitForLoadState("networkidle");

    // Navigate to collaborative editor using dynamic workflow ID
    await page.evaluate(
      ([projectId, workflowId]) => {
        window.liveSocket.historyRedirect(
          { isTrusted: true },
          `/projects/${projectId}/w/${workflowId}/collaborate`,
          "push",
          null,
          document.querySelector(`#workflow-${workflowId}`)
        );
      },
      [testData.projects.openhie.id, testData.workflows.openhie.id]
    );

    await page.waitForLoadState("networkidle");

    // Assert we can see the React component content with dynamic workflow ID
    await expect(page.locator("text=Hello from React!")).toBeVisible();
    await expect(page.locator("text=Collaborative Editor for:")).toBeVisible();
    await expect(
      page.locator(`text=Workflow ID: ${testData.workflows.openhie.id}`)
    ).toBeVisible();

    // Verify URL contains the actual workflow ID from database
    await expect(page).toHaveURL(
      new RegExp(
        `/projects/${testData.projects.openhie.id}/w/${testData.workflows.openhie.id}/collaborate`
      )
    );

    // Assert the collaborative editor container is present
    const collaborativeEditor = page.locator(".collaborative-editor");
    await expect(collaborativeEditor).toBeVisible();

    // Assert no error messages are shown
    const errorMessage = page.locator("text=Something went wrong");
    await expect(errorMessage).not.toBeVisible();

    const invariantError = page.locator("text=Invariant failed");
    await expect(invariantError).not.toBeVisible();
  });

  test("collaborative editor works with both projects", async ({ page }) => {
    await page.goto("/");

    // Login if needed
    const loginForm = page.locator("#login form");
    if (await loginForm.isVisible()) {
      await page
        .locator('input[name="user[email]"]')
        .fill(testData.users.editor.email);
      await page
        .locator('input[name="user[password]"]')
        .fill(testData.users.editor.password);
      await page.getByRole("button", { name: "Log in" }).click();
      await page.waitForLoadState("networkidle");
    }

    // Test collaborative editor with DHIS2 project as well
    await page
      .getByRole("cell", { name: testData.projects.dhis2.name })
      .click();
    await page.waitForLoadState("networkidle");

    // Navigate to DHIS2 workflow collaborative editor
    await page.evaluate(
      ([projectId, workflowId]) => {
        window.liveSocket.historyRedirect(
          { isTrusted: true },
          `/projects/${projectId}/w/${workflowId}/collaborate`,
          "push",
          null,
          document.querySelector(`#workflow-${workflowId}`)
        );
      },
      [testData.projects.dhis2.id, testData.workflows.dhis2.id]
    );

    await page.waitForLoadState("networkidle");

    // Verify DHIS2 workflow collaborative editor loads
    await expect(page.locator("text=Collaborative Editor for:")).toBeVisible();
    await expect(
      page.locator(`text=Workflow ID: ${testData.workflows.dhis2.id}`)
    ).toBeVisible();
  });
});
