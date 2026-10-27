// Scenarios from annotations/shared/shared-hash-tabs.md. The host page owns
// the Given: it opens itself (with or without a fragment) and hands over its
// tab labels, hashes and `panel`, which finds the panel a tab shows on that
// page. The functions hold the When and Then.
import { expect, type Locator, type Page } from '@playwright/test';

import { goBack, reload } from '../steps';

// A tab by its label. Both versions give tabs the tab role; today a disabled
// one is named by its tooltip, so the label is matched in its text.
export const tab = (page: Page, label: string) =>
  page.getByRole('tab').filter({ hasText: label });

export const expectSelected = (page: Page, label: string) =>
  expect(tab(page, label)).toHaveAttribute('aria-selected', 'true');

type Panel = (label: string) => Locator;

const fragment = (page: Page) => new URL(page.url()).hash;

// @S01 A page with no fragment opens on its default tab
//   Given a host page whose tab container has default tab "log"
//   When I open the host page with no fragment
//   Then the "Log" tab is selected
//   And only the "Log" panel is visible
export async function S01(
  page: Page,
  open: () => Promise<void>,
  panel: Panel,
  defaultLabel: string,
  others: string[]
) {
  await open();

  await expectSelected(page, defaultLabel);
  await expect(panel(defaultLabel)).toBeVisible();
  for (const label of others) await expect(panel(label)).toBeHidden();
}

// @S02 A fragment in the link opens that tab
//   Given a host page with an enabled tab "data-storage" that is not the default
//   When I open the host page with fragment "#data-storage"
//   Then the "Data Storage" tab is selected
//   And the default tab's panel is not visible
// `open` opens the page with the fragment.
export async function S02(
  page: Page,
  open: () => Promise<void>,
  panel: Panel,
  label: string,
  defaultLabel: string
) {
  await open();

  await expectSelected(page, label);
  await expect(panel(label)).toBeVisible();
  await expect(panel(defaultLabel)).toBeHidden();
}

// @S03 Choosing a tab names it in the address bar
//   Given I am on a host page on its default tab
//   When I click the "Output" tab
//   Then the URL ends in "#output"
//   And the "Output" panel is the only one visible
//   When I reload the page
//   Then the "Output" tab is still selected
export async function S03(
  page: Page,
  panel: Panel,
  label: string,
  hash: string,
  others: string[]
) {
  await tab(page, label).click();

  await expect.poll(() => fragment(page)).toBe(`#${hash}`);
  await expect(panel(label)).toBeVisible();
  for (const other of others) await expect(panel(other)).toBeHidden();
  await reload(page);
  await expectSelected(page, label);
}

// @S04 Back returns to the previous tab
//   Given I opened a host page with fragment "#credentials"
//   And I then clicked the "Collaboration" tab
//   When I press the browser Back button
//   Then the URL ends in "#credentials"
//   And the "Credentials" tab is selected
// `open` opens the page with the first tab's fragment.
export async function S04(
  page: Page,
  open: () => Promise<void>,
  first: { label: string; hash: string },
  second: string
) {
  await open();
  await expectSelected(page, first.label);
  await tab(page, second).click();
  await expectSelected(page, second);

  await goBack(page);

  await expect.poll(() => fragment(page)).toBe(`#${first.hash}`);
  await expectSelected(page, first.label);
}

// @S05 The open tab survives a server re-render
//   Given I am on a host page on a non-default tab
//   When the server re-renders the page
//   Then the same tab is still selected
//   And the default tab's panel is still hidden
// `rerender` makes the server send the page an update, and resolves once it
// shows.
export async function S05(
  page: Page,
  panel: Panel,
  label: string,
  defaultLabel: string,
  rerender: () => Promise<void>
) {
  await expectSelected(page, label);

  await rerender();

  await expectSelected(page, label);
  await expect(panel(defaultLabel)).toBeHidden();
}

// @S06 Clicking a disabled tab does nothing
//   Given a host page whose "Input" tab is disabled
//   And the "Log" tab is selected
//   When I click the "Input" tab
//   Then the URL fragment does not change
//   And the "Log" tab is still selected
export async function S06(page: Page, disabled: string, selected: string) {
  await expectSelected(page, selected);
  const before = fragment(page);

  await tab(page, disabled).click({ force: true });
  await page.waitForTimeout(500);

  expect(fragment(page)).toBe(before);
  await expectSelected(page, selected);
}
