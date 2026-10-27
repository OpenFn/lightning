// Where today's run page (HEEx) and the design-system one differ.
// Everything that knows how either version is built lives here, so a redesign
// of /projects/:id/runs/:id only changes this file. The tabs, the log and the
// body viewer are shared components: shared/hash-tabs.ts,
// shared/log-viewer.ts and shared/dataclip-body-viewer.ts.
import { expect, type Page } from '@playwright/test';

import { tab } from '../shared/hash-tabs';

// The value labelled <label> in the run's summary ("Workflow", "Work Order",
// "Started by", "Started", "Finished", "Final Output", "Duration",
// "Status"). Both versions draw the summary as a description list.
export const detail = (page: Page, label: string) =>
  page
    .locator('dt')
    .filter({ hasText: new RegExp(`^\\s*${label}\\s*$`) })
    .locator('xpath=following-sibling::dd[1]');

// The label of a summary value, to say whether it is shown at all
export const detailLabel = (page: Page, label: string) =>
  page.locator('dt').filter({ hasText: new RegExp(`^\\s*${label}\\s*$`) });

export const breadcrumbs = (page: Page) =>
  page.getByRole('navigation', { name: 'Breadcrumbs' });

// The last crumb's words, with whitespace collapsed
export const lastCrumb = async (page: Page) =>
  (await breadcrumbs(page).getByRole('listitem').last().innerText())
    .replace(/\s+/g, ' ')
    .trim();

// The chip after the run's id: "latest" or a snapshot's first seven
// characters
export const versionChip = (page: Page) =>
  breadcrumbs(page).getByText(/^\s*(latest|[0-9a-f]{7})\s*$/);

// One step in the step list. Both versions mark each item with its step id.
export const runStep = (page: Page, stepId: string) =>
  page.locator(`li[data-step-id="${stepId}"]`);

// A step's own link, which holds its name. The port's name is a bare text
// node beside the inspect icon and the time, so it is found by the link.
const stepLink = (page: Page, stepId: string, name: string) =>
  runStep(page, stepId).getByRole('link').filter({ hasText: name }).first();

// The step named <name>, whatever its id
export const stepNamed = (page: Page, name: string) =>
  page.locator('li[data-step-id]').filter({ hasText: name });

// When I select step <name> in the step list
export const selectStep = (page: Page, stepId: string, name: string) =>
  stepLink(page, stepId, name).click();

// Then step <chosen> of <steps> (name -> id) is marked as selected. Neither
// version says so to assistive tech; both draw the selected step's name
// bolder than the others', so the look is what is compared.
export async function expectSelectedStep(
  page: Page,
  steps: Record<string, string>,
  chosen: string
) {
  const weight = (name: string) =>
    stepLink(page, steps[name], name).evaluate((link, text) => {
      const walk = document.createTreeWalker(link, NodeFilter.SHOW_TEXT);
      for (let n = walk.nextNode(); n; n = walk.nextNode())
        if (n.textContent?.trim() === text)
          return Number(getComputedStyle(n.parentElement!).fontWeight);
      return 0;
    }, name);
  await expect
    .poll(async () => {
      const mine = await weight(chosen);
      for (const name of Object.keys(steps))
        if (name !== chosen && (await weight(name)) >= mine) return false;
      return true;
    })
    .toBe(true);
}

// A step's duration ("1 s", "1 m", "Not started")
export const stepDuration = (page: Page, stepId: string) =>
  runStep(page, stepId)
    .getByText(/^\s*(\d+(\.\d+)? ?(ms|s|m|h|d)|Not started)\s*$/)
    .first();

// The icon that opens a step in the editor
export const inspectLink = (page: Page, stepId: string) =>
  runStep(page, stepId).getByRole('link', {
    name: 'Inspect Step',
    exact: true,
  });

export const workflowLink = (page: Page) =>
  detail(page, 'Workflow').getByRole('link');

export const cancelButton = (page: Page) =>
  page.getByRole('button', { name: 'Cancel', exact: true });

// When the page is asked to cancel run <runId>, whatever run it shows.
// Today's Cancel button names the run it cancels, so it is repointed and
// clicked.
export async function sendCancelFor(page: Page, runId: string) {
  await cancelButton(page).evaluate(
    (el, id) => el.setAttribute('phx-value-run_id', id),
    runId
  );
  await cancelButton(page).click();
}

// The panel a tab shows. Today each is a tab panel named by its tab.
export const panel = (page: Page, label: string) =>
  page.getByRole('tabpanel', { name: label, exact: true });

// Then tab <label> is disabled, and pointing at it says <reason>
export async function expectDisabledTab(
  page: Page,
  label: string,
  reason: string
) {
  await tab(page, label).hover({ force: true });
  await expect(
    page.getByRole('tooltip').filter({ hasText: reason })
  ).toBeVisible();
}

// What a not-retained panel tells people who cannot change the policy,
// and the admins it names on hover
export const projectAdmins = (page: Page) =>
  page.getByText('project admins', { exact: true }).filter({ visible: true });
