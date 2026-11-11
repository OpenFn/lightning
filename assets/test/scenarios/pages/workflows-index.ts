// The project's workflows list (/projects/<id>/w) as the flows that start
// there use it: switching a workflow on or off and deleting one. The row
// helpers themselves are in steps.ts, shared with workflows-index.spec.ts;
// these are the actions on top of them, so a rebuild changes them here.
import { expect, type Page } from '@playwright/test';

import {
  clickAndConfirm,
  open,
  workflowRow,
  workflowsHeading,
  workflowsPath,
  workflowSwitch,
} from '../steps';

// When I open project <projectId>'s workflows list (signed in already)
export async function openWorkflowsList(page: Page, projectId: string) {
  await open(page, workflowsPath(projectId));
  await expect(workflowsHeading(page)).toBeVisible();
}

// When I click the switch on workflow <name>'s row
export const switchOnList = (page: Page, name: string) =>
  workflowSwitch(workflowRow(page, name)).click();

// When I click "Delete" on workflow <name>'s row and confirm — resolves to
// what I was asked
export const deleteOnList = (page: Page, name: string) =>
  clickAndConfirm(
    page,
    workflowRow(page, name).getByText('Delete', { exact: true }),
    'Delete workflow'
  );
