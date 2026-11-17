// Where today's workflow health page and the design-system one differ.
// Everything that knows how either version is built lives here, so a redesign
// of /projects/:id/w/:id/health only changes this file.
import type { Page } from '@playwright/test';

const heading = (page: Page, name: string) =>
  page.getByRole('heading', { name, exact: true });

// The card a heading titles. The design system marks its cards; today's page
// puts the heading in a row inside the card.
export const card = (page: Page, title: string) =>
  heading(page, title).locator(
    'xpath=ancestor::*[@data-ui="card"][1] | self::*[not(ancestor::*[@data-ui="card"])]/../..'
  );

// The small print beside a card's title that names the buckets and timezone
// ("daily buckets · Etc/UTC"), the same words on both versions
export const meta = (page: Page, title: string) =>
  card(page, title).getByText(/ buckets · /);
