// Where today's channel logs tab (HEEx) and the design-system one differ.
// Everything that knows how either version is built lives here, so a redesign
// of /projects/:id/history/channels only changes this file.
import { expect, type Locator, type Page } from '@playwright/test';

import { shortId } from '../steps';

// The channel filter chip, which reads "Channel is <name>" or "Channel is
// any" and opens the channel list. Both versions draw it as a button.
export const channelChip = (page: Page) =>
  page.getByRole('button', { name: /^Channel is\b/ });

// The chip's clear button, shown only while a channel is chosen
export const clearChannelButton = (page: Page) =>
  page.getByRole('button', { name: 'Clear filter' });

// The choices of the open channel list, top to bottom
export const channelChoices = (page: Page) => page.getByRole('menuitem');

// When I open the channel chip and choose <name>
export async function chooseChannel(page: Page, name: string | RegExp) {
  await channelChip(page).click();
  await channelChoices(page)
    .filter({ hasText: typeof name === 'string' ? exactly(name) : name })
    .click();
}

const exactly = (text: string) =>
  new RegExp(`^\\s*${text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\s*$`);

// A History tab ("Work Orders" or "Channel Logs"). Today's are plain links;
// the design system draws them as tabs.
export const historyTab = (page: Page, name: string) =>
  page
    .getByRole('tab', { name, exact: true })
    .or(page.getByRole('link', { name, exact: true }));

// The rows of the requests table that hold requests (not the header, not
// the empty-list row)
const requestRows = (page: Page) =>
  page
    .getByRole('row')
    .filter({ has: page.getByRole('cell') })
    .filter({ hasNot: page.getByText('No channel requests found.') });

// The row of the request whose ID is <requestId>
export const requestRow = (page: Page, requestId: string) =>
  requestRows(page).filter({
    has: page.getByRole('link', { name: shortId(requestId), exact: true }),
  });

// The short IDs of the listed requests, top to bottom. The ID is the
// first column in both versions.
export const listedRequests = async (page: Page) =>
  (await requestRows(page).locator('td:first-child').allInnerTexts()).map(t =>
    t.trim()
  );

// The cell of <row> under the column headed <header>, in any letter case
// (today's headers are title case)
export async function requestCell(page: Page, row: Locator, header: string) {
  const headers = (await page.getByRole('columnheader').allInnerTexts()).map(
    h => h.trim().toLowerCase()
  );
  const column = headers.indexOf(header.toLowerCase());
  expect(column, `a "${header}" column`).toBeGreaterThanOrEqual(0);
  return row.getByRole('cell').nth(column);
}
