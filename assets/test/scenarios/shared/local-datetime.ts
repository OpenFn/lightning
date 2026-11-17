// Scenarios from annotations/shared/shared-local-datetime.md.
//
// Each takes the page and the element (usually a table cell) that shows one
// timestamp. The host spec owns the Given: it makes that timestamp `given.Sxx`
// and sets the browser's time zone and today's date from it before the page
// loads. The functions hold the When and Then.
import { expect, type Locator, type Page } from '@playwright/test';

export const given = {
  S01: {
    utc: '2026-10-14 08:30:00',
    timezoneId: 'Africa/Blantyre',
    today: '2026-10-14T12:00:00+02:00',
  },
  S02: { utc: '2024-03-05 08:30:00', today: '2026-10-14T12:00:00Z' },
  S03: { utc: '2026-10-14 08:30:07', today: '2026-10-14T12:00:00Z' },
  S04: { utc: '2026-10-14 08:30:07' },
  S05: { utc: '2026-10-14 08:30:07' },
  S06: { utc: '2026-10-14 08:30:07.123456' },
};

// The timestamp's text; a cell may also hold other controls, without text
const timestamp = (cell: Locator) =>
  cell.getByText(/\d/).filter({ visible: true });

// @S01 A timestamp is shown in the viewer's time zone
//   Then the timestamp reads "today at 10:30 AM"
export async function S01(_page: Page, cell: Locator) {
  await expect(timestamp(cell)).toHaveText('today at 10:30 AM');
}

// @S02 A timestamp from another year shows the year
//   Then the timestamp starts with "2024-03-05,"
export async function S02(_page: Page, cell: Locator) {
  await expect(timestamp(cell)).toHaveText(/^2024-03-05,/);
}

// @S03 Detailed relative time shows seconds
//   Given the browser's time zone is UTC
//   Then the timestamp reads "today at 8:30:07 AM"
export async function S03(_page: Page, cell: Locator) {
  await expect(timestamp(cell)).toHaveText('today at 8:30:07 AM');
}

// @S04 Hovering a timestamp shows the exact UTC value
//   When I hover the timestamp
//   Then a tooltip shows "2026-10-14 08:30:07 UTC"
//   And the tooltip says "Click to copy timestamp"
export async function S04(page: Page, cell: Locator) {
  await timestamp(cell).hover();

  const tooltip = page.getByRole('tooltip');
  await expect(tooltip).toContainText(`${given.S04.utc} UTC`);
  await expect(tooltip).toContainText('Click to copy timestamp');
}

// @S05 Clicking a timestamp copies the UTC value
//   When I click the timestamp
//   Then my clipboard contains "2026-10-14 08:30:07 UTC"
//   And the tooltip briefly reads "Copied!"
export async function S05(page: Page, cell: Locator) {
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);

  await timestamp(cell).click();

  await expect
    .poll(() => page.evaluate(() => navigator.clipboard.readText()))
    .toBe(`${given.S05.utc} UTC`);
  const copied = page.getByRole('tooltip').filter({ hasText: 'Copied!' });
  await expect(copied).toBeVisible();
  await expect(copied).toBeHidden({ timeout: 3000 });
}

// @S06 Sub-second timestamps keep milliseconds
//   When I hover the timestamp
//   Then the tooltip shows "2026-10-14 08:30:07.123 UTC"
//   And clicking it copies "2026-10-14 08:30:07.123 UTC"
export async function S06(page: Page, cell: Locator) {
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  const exact = '2026-10-14 08:30:07.123 UTC';

  await timestamp(cell).hover();
  await expect(page.getByRole('tooltip')).toContainText(exact);

  await timestamp(cell).click();
  await expect
    .poll(() => page.evaluate(() => navigator.clipboard.readText()))
    .toBe(exact);
}

// @S07 A missing timestamp shows a placeholder
//   Then I see "--" in grey
//   And there is no tooltip and nothing to copy
export async function S07(page: Page, cell: Locator) {
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.evaluate(() => navigator.clipboard.writeText('untouched'));

  const placeholder = cell.getByText('--', { exact: true });
  await expect(placeholder).toBeVisible();
  // Painted on a canvas to read it as RGB: Tailwind v4 colours are oklch
  const [r, g, b] = await placeholder.evaluate(el => {
    const ctx = document.createElement('canvas').getContext('2d')!;
    ctx.fillStyle = getComputedStyle(el).color;
    ctx.fillRect(0, 0, 1, 1);
    return [...ctx.getImageData(0, 0, 1, 1).data];
  });
  expect(
    Math.max(r, g, b) - Math.min(r, g, b) < 30 && r > 60 && r < 200,
    `"--" should be grey, not rgb(${r}, ${g}, ${b})`
  ).toBe(true);

  await placeholder.hover();
  await expect(page.getByRole('tooltip')).toHaveCount(0);
  await placeholder.click();
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(
    'untouched'
  );
}
