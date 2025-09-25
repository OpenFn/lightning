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
    await page.waitForLoadState("networkidle");

    // await page.pause();
    console.log("Navigating to workflow:", testData.workflows.openhie.name);

    await expect(page.getByText("OpenHIE Workflow")).toBeVisible();

    // Have to wait a bit, seems like the event handlers for Phoenix LiveView
    // are not fully ready...
    // Maybe we listen for a specific event instead of waiting a fixed time?
    await page.waitForTimeout(100);
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

    // Assert we have 5 nodes visible in the workflow
    const nodes = page.locator(".react-flow__node");
    await expect(page.getByRole("main")).toMatchAriaSnapshot(`
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
    await expect(nodes).toHaveCount(5);

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
