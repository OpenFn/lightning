// Where today's channel request page (HEEx) and the design-system one differ.
// Everything that knows how either version is built lives here, so a redesign
// of /projects/:id/history/channels/:id only changes this file.
import { expect, type Locator, type Page } from '@playwright/test';

const escaped = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// The button that opens and closes a card or sub-section ("Request",
// "Response", "Timing", "Context", and "Headers" or "Body" inside a card).
// Its name starts with the title; what follows is a size or status badge.
export const toggle = (within: Page | Locator, title: string) =>
  within.getByRole('button', { name: new RegExp(`^\\s*${escaped(title)}\\b`) });

// The card or sub-section a toggle opens, its header included. In both
// versions the toggle's parent holds it.
export const section = (within: Page | Locator, title: string) =>
  toggle(within, title).locator('xpath=..');

// A group of the summary card ("Client", "Destination", "Timing"), found by
// its heading. The Timing card has a heading of the same name a level up.
export const group = (page: Page, title: string) =>
  page
    .getByRole('heading', { name: title, exact: true, level: 4 })
    .locator('xpath=..');

// The value labelled <label> within <within>: a fact of the summary or
// Context, or a header's value. Both versions put facts in a description
// list; today's headers are a two-column table, the design system's a list.
export const valueOf = (within: Locator, label: string) =>
  within
    .locator('dt')
    .filter({ hasText: new RegExp(`^\\s*${escaped(label)}\\s*$`) })
    .locator('xpath=following-sibling::dd[1]')
    .or(
      within
        .getByRole('row')
        .filter({
          has: within.page().getByRole('cell', { name: label, exact: true }),
        })
        .getByRole('cell')
        .nth(1)
    );

// What pointing at each segment of the timing bar says, left to right.
// Today each segment carries a title; the design system shows a tooltip on
// hover. Segments are the only parts of the bar sized by width.
export async function segmentTitles(page: Page) {
  const segments = section(page, 'Timing').locator('[style*="width"]');
  await expect(segments.first()).toBeVisible();
  const titles: string[] = [];
  for (const segment of await segments.all()) {
    const title = await segment.getAttribute('title');
    if (title) {
      titles.push(title);
      continue;
    }
    await page.mouse.move(0, 0);
    await expect(page.getByRole('tooltip')).toHaveCount(0);
    await segment.hover();
    const tip = page.getByRole('tooltip');
    await expect(tip).toBeVisible();
    titles.push((await tip.innerText()).trim());
  }
  return titles;
}
