// Where today's dataclip page (HEEx) and the design-system one differ.
// Everything that knows how either version is built lives here, so a redesign
// of /projects/:id/dataclips/:id/show only changes this file. The body viewer
// is shared-dataclip-body-viewer's, in shared/dataclip-body-viewer.ts.
import type { Page } from '@playwright/test';

// The value labelled <label> in "Dataclip Details" ("ID", "Type", "Created",
// "Updated", "Wiped"). Both versions draw the details as a description list.
export const detail = (page: Page, label: string) =>
  page
    .locator('dt')
    .filter({ hasText: new RegExp(`^\\s*${label}\\s*$`) })
    .locator('xpath=following-sibling::dd[1]');

// The label of a detail, to say whether it is shown at all
export const detailLabel = (page: Page, label: string) =>
  page.locator('dt').filter({ hasText: new RegExp(`^\\s*${label}\\s*$`) });
