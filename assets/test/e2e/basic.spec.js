import { test, expect } from "@playwright/test";
test("homepage loads successfully", async ({ page }) => {
  await page.goto("/");
  // Wait for the page to load
  await page.waitForLoadState("networkidle");
  // Check that we can see some basic Lightning content
  await expect(page).toHaveTitle(/Lightning/);
});
test("can navigate to existing workflow and see React Flow with 6 nodes", async ({
  page,
}) => {
  await page.goto("/");
  // Check if we're already on the login page or need to navigate to it
  const loginForm = page.locator("#login form");
  const isOnLoginPage = await loginForm.isVisible();
  if (isOnLoginPage) {
    await page.locator('input[name="user[email]"]').fill("editor@openfn.org");
    await page.locator('input[name="user[password]"]').fill("welcome12345");
    await page.getByRole("button", { name: "Log in" }).click();
  }
  await page.waitForLoadState("networkidle");
  await page.getByRole("cell", { name: "openhie-project" }).click();
  await page
    .getByLabel("OpenHIE Workflow")
    .getByText("OpenHIE Workflow")
    .click();
  await page.waitForLoadState("networkidle");
  // // Assert React Flow is present and working
  const reactFlowContainer = page.locator(".react-flow");
  await expect(reactFlowContainer).toBeVisible();
  // // Assert the viewport is present
  const reactFlowViewport = page.locator(".react-flow__viewport");
  await expect(reactFlowViewport).toBeVisible();
  // // Assert we have 6 nodes visible in the workflow
  const nodes = page.locator(".react-flow__node");
  await expect(nodes).toHaveCount(6);
  // // Assert no error messages are shown
  const errorMessage = page.locator("text=Something went wrong");
  await expect(errorMessage).not.toBeVisible();
  const invariantError = page.locator("text=Invariant failed");
  await expect(invariantError).not.toBeVisible();
});
