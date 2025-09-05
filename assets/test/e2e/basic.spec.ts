import { test, expect } from "@playwright/test";
import { getTestData } from "./test-data";

test("homepage loads successfully", async ({ page }) => {
  await page.goto("/");

  // Wait for the page to load
  await page.waitForLoadState("networkidle");

  // Check that we can see some basic Lightning content
  await expect(page).toHaveTitle(/Lightning/);
});

test.describe("Workflow Navigation with Dynamic Data", () => {
  let testData: Awaited<ReturnType<typeof getTestData>>;

  test.beforeAll(async () => {
    // Load test data once per test suite
    testData = await getTestData();
  });

  test("can navigate to existing workflow and see React Flow with 6 nodes", async ({
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

    // Use dynamic test data for project and workflow navigation
    await page
      .getByRole("cell", { name: testData.projects.openhie.name })
      .click();
    await page
      .getByLabel(testData.workflows.openhie.name)
      .getByText(testData.workflows.openhie.name)
      .click();
    await page.waitForLoadState("networkidle");

    // Verify URL contains the actual workflow ID from database
    await expect(page).toHaveURL(
      new RegExp(`/w/${testData.workflows.openhie.id}`)
    );

    // Assert React Flow is present and working
    const reactFlowContainer = page.locator(".react-flow");
    await expect(reactFlowContainer).toBeVisible();

    // Assert the viewport is present
    const reactFlowViewport = page.locator(".react-flow__viewport");
    await expect(reactFlowViewport).toBeVisible();

    // Assert we have 6 nodes visible in the workflow
    const nodes = page.locator(".react-flow__node");
    await expect(nodes).toHaveCount(6);

    // Assert no error messages are shown
    const errorMessage = page.locator("text=Something went wrong");
    await expect(errorMessage).not.toBeVisible();

    const invariantError = page.locator("text=Invariant failed");
    await expect(invariantError).not.toBeVisible();
  });

  test("workflow data matches database state", async ({ page }) => {
    // Navigate to projects page to verify project data
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

    // Verify both projects are visible
    await expect(
      page.getByRole("cell", { name: testData.projects.openhie.name })
    ).toBeVisible();
    await expect(
      page.getByRole("cell", { name: testData.projects.dhis2.name })
    ).toBeVisible();
  });
});
