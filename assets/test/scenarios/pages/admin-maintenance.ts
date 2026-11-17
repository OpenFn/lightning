// Where today's maintenance page (HEEx) and the design-system one differ.
// Everything that knows how either version is built lives here, so a
// redesign of /settings/maintenance only changes this file.
import type { Page } from '@playwright/test';

const RUN_IDS = {
  'Refresh Adaptor Registry': '#refresh-adaptors-button',
  'Refresh Adaptor Icons': '#refresh-icons-button',
};

export type MaintenanceCard = keyof typeof RUN_IDS;

// The "Run" button on <card>. Today both buttons are named just "Run" and sit
// in a plain box under the card's heading, so nothing a user can see tells
// them apart to a locator; both versions render these ids. (The design
// system names them "Run <card>".)
export const runButton = (page: Page, card: MaintenanceCard) =>
  page.locator(RUN_IDS[card]);
