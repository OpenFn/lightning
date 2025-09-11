import { test, expect } from "@playwright/test";
test("can navigate to collaborative editor and see React component", async ({
  page,
}) => {
  const workflowId = "2356a807-f8db-4097-b474-f37579fd0898";
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
  await page.waitForLoadState("networkidle");
  // Navigate to collaborative editor using liveSocket.historyRedirect
  await page.evaluate(
    ([workflowId]) => {
      window.liveSocket.historyRedirect(
        { isTrusted: true },
        `/projects/4adf2644-ed4e-4f97-a24c-ab35b3cb1efa/w/${workflowId}/collaborate`,
        "push",
        null,
        document.querySelector(`#workflow-${workflowId}`)
      );
    },
    [workflowId]
  );
  await page.waitForLoadState("networkidle");
  // Assert we can see the React component content
  await expect(page.locator("text=Hello from React!")).toBeVisible();
  await expect(page.locator("text=Collaborative Editor for:")).toBeVisible();
  await expect(page.locator(`text=Workflow ID: ${workflowId}`)).toBeVisible();
  // Assert the collaborative editor container is present
  const collaborativeEditor = page.locator(".collaborative-editor");
  await expect(collaborativeEditor).toBeVisible();
  // Assert no error messages are shown
  const errorMessage = page.locator("text=Something went wrong");
  await expect(errorMessage).not.toBeVisible();
  const invariantError = page.locator("text=Invariant failed");
  await expect(invariantError).not.toBeVisible();
});
