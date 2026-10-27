// Scenarios from annotations/shared/shared-project-deletion-modal.md, run on
// a host page. The host seeds the project and passes `open`, which opens the
// modal on that host for the project with that id.
import { expect, type Page } from '@playwright/test';

import {
  expectAt,
  field,
  modal,
  modalTitle,
  onNode,
  scheduledDeletionOf,
  sql,
  submit,
} from '../steps';

import { toast } from './flash-messages';

type Project = { id: string; name: string };
type Open = (id: string) => Promise<void>;

const TITLE = 'Delete project';

async function dialog(page: Page) {
  await expect(modalTitle(page, TITLE)).toBeVisible();
  return modal(page, TITLE);
}

// The purge jobs queued for project <id>
const purgeJobsOf = (id: string) =>
  sql(
    `select 1 from oban_jobs where worker = 'Lightning.Projects'
     and args->>'type' = 'purge_deleted' and args->>'project_id' = '${id}'`
  );

// When I type "<typed>" into "Project name" and leave the field
async function typeName(page: Page, typed: string) {
  const d = await dialog(page);
  await field(d, 'Project name').fill(typed);
  await field(d, 'Project name').blur();
  return d;
}

// @S01 The modal names the project and the grace period
//   Given the modal is open for project "project-1"
//   Then I see "Enter the project name to confirm deletion: project-1"
//   And I see "The whole project will be deleted along with all workflows and work order history, 7 day(s) from today."
// The grace period is the instance's own setting.
export async function S01(page: Page, project: Project, open: Open) {
  const days = Number(
    onNode('Lightning.Config.purge_deleted_after_days()')
      .trim()
      .split('\n')
      .pop()
  );
  await open(project.id);

  const d = await dialog(page);
  await expect(d).toContainText(
    `Enter the project name to confirm deletion: ${project.name}`
  );
  await expect(d).toContainText(
    `The whole project will be deleted along with all workflows and work order history, ${
      days > 0 ? `${days} day(s) from today` : 'today'
    }.`
  );
}

// @S02 A mistyped name is refused
//   Given the modal is open for project "project-1"
//   When I type "project-2" into "Project name" and leave the field
//   Then I see "doesn't match the project name"
//   And "Delete project" is disabled
//   When I submit the form
//   Then the project is not scheduled for deletion and no purge job is enqueued
// `send` sends the modal's confirm with a typed name, past the page's own
// check, so the last Then can fail on a page that turns the button off.
export async function S02(
  page: Page,
  project: Project,
  open: Open,
  send: (typed: string) => Promise<void>
) {
  await open(project.id);
  const typed = `${project.name}-2`;
  const d = await typeName(page, typed);

  // Today's page says "The Project name does not match."
  await expect(d.getByText(/does(n't| not) match/)).toBeVisible();
  await submit(d, TITLE);
  await expect(modalTitle(page, TITLE)).toBeVisible();

  await send(typed);
  expect(scheduledDeletionOf(project.id)).toBeNull();
  expect(purgeJobsOf(project.id)).toEqual([]);
}

// @S03 Confirming an unscheduled project schedules it and returns to the host
//   Given the modal is open for unscheduled project "project-1" with "after delete" page "/projects"
//   When I type "project-1" into "Project name" and click "Delete project"
//   Then I am on "/projects"
//   And I see "Project scheduled for deletion"
//   And the flow "flow-schedule-project-deletion" has started for "project-1"
// The flow has started when the project carries a deletion date.
export async function S03(
  page: Page,
  project: Project,
  open: Open,
  afterDelete: string
) {
  await open(project.id);
  const d = await typeName(page, project.name);
  await submit(d, TITLE);

  await expectAt(page, afterDelete);
  await expect(toast(page, 'Project scheduled for deletion')).toBeVisible();
  expect(scheduledDeletionOf(project.id)).not.toBeNull();
}

// @S04 Confirming an already scheduled project starts the purge now
//   Given project "project-1" is scheduled for deletion
//   And the modal is open for it with "after delete" page "/settings/projects"
//   When I type "project-1" into "Project name" and click "Delete project"
//   Then I am on "/settings/projects"
//   And I see "Project deletion started. This may take a while to complete."
//   And a purge job for "project-1" is enqueued
export async function S04(
  page: Page,
  project: Project,
  open: Open,
  afterDelete: string
) {
  await open(project.id);
  const d = await typeName(page, project.name);
  await submit(d, TITLE);

  await expectAt(page, afterDelete);
  await expect(
    toast(page, 'Project deletion started. This may take a while to complete.')
  ).toBeVisible();
  expect(purgeJobsOf(project.id)).toHaveLength(1);
}

// @S05 Backing out returns to the host and changes nothing
//   Given the modal is open for project "project-1" with "cancel" page "<cancel_page>"
//   When I click <control>
//   Then I am on "<cancel_page>"
//   And the project is not scheduled for deletion
export async function S05(
  page: Page,
  project: Project,
  open: Open,
  control: string,
  cancelPage: string
) {
  await open(project.id);
  const d = await dialog(page);

  // Any case: today's close button is named "close"
  await d
    .getByRole('button', { name: new RegExp(`^${control}$`, 'i') })
    .click();

  await expectAt(page, cancelPage);
  await expect(modalTitle(page, TITLE)).toHaveCount(0);
  expect(scheduledDeletionOf(project.id)).toBeNull();
}
