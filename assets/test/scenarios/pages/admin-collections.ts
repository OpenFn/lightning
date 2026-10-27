// Where today's collections admin page (HEEx) and the design-system one
// differ. Everything that knows how either version is built lives here, so a
// redesign of /settings/collections only changes this file.
import type { Locator, Page } from '@playwright/test';

import { clickable } from '../steps';

// "Edit" or "Delete" on a collection's row. Today the buttons are named
// "Edit" and "Delete"; the design system adds the collection's name
// ("Edit patients").
export const rowAction = (row: Locator, action: string) =>
  row.getByRole('button', { name: new RegExp(`^${action}\\b`) });

// The empty state's create control. On the design system the message is part
// of the button's name, so match the start only.
export const createFirstButton = (page: Page) =>
  clickable(page, /Create a new one\./);

// The project picker's chosen project, by name. Both versions draw a native
// select whose options carry the project's id as the value.
export const chosenOption = (select: Locator) =>
  select.evaluate(el => (el as HTMLSelectElement).selectedOptions[0]?.text);
