// Scenarios from annotations/shared/shared-workflow-yaml-format.md: what a
// workflow YAML file means once imported, and how a bad one is refused.
// Hosts: workflow-editor-new (the import dialog on /w/new: S01 to S10) and
// workflow-editor-ai-assistant (apply on an existing workflow: S11). The host
// owns the Given: it signs in, seeds and opens the page, and hands over an
// opener for the import dialog (the landing screen's import, or Ctrl+\). The
// functions paste the file, import it, and read the result from the database
// once the new workflow is saved.
import { expect, type Page } from '@playwright/test';
import YAML from 'yaml';

import {
  lastLine,
  modal,
  modalTitle,
  onNode,
  sql,
  submitButton,
  user,
} from '../steps';

// ---------------------------------------------------------------------------
// How the editor is built. Everything that knows the import dialog's shape
// lives here.
// ---------------------------------------------------------------------------

// The import dialog, by its accessible name
const importDialog = (page: Page) => modal(page, 'Import a workflow');

// Opens the dialog with the host's opener, unless it is open already
async function openOnce(page: Page, open: OpenImport) {
  const title = modalTitle(page, 'Import a workflow');
  if (!(await title.isVisible())) await open();
  await expect(title).toBeVisible();
}

// The dialog opens on file upload; "Paste text" switches it to a text box
async function paste(page: Page, yaml: string) {
  const dialog = importDialog(page);
  const toPaste = dialog.getByRole('button', { name: 'Paste text' });
  if (await toPaste.isVisible()) await toPaste.click();
  await dialog.getByRole('textbox').fill(yaml);
}

// The button that creates the workflow from the file
const createButton = (page: Page) => submitButton(importDialog(page), 'Create');

// The error box under the text: the innermost block holding its heading
const errorBox = (page: Page) =>
  importDialog(page)
    .locator('div')
    .filter({
      has: page.getByRole('heading', { name: /^Validation Errors?$/ }),
    })
    .last();

// ---------------------------------------------------------------------------

export type OpenImport = () => Promise<void>;

const workflowNamed = (projectId: string, name: string) =>
  sql<{ id: string }>(
    `select id from workflows where project_id = '${projectId}'
       and name = $n$${name}$n$ and deleted_at is null`
  );

// When I import <yaml> and create the workflow. Resolves to its id once saved.
async function importFile(
  page: Page,
  open: OpenImport,
  projectId: string,
  yaml: string
) {
  const name = (YAML.parse(yaml) as { name: string }).name;
  await openOnce(page, open);
  await paste(page, yaml);
  await expect(createButton(page)).toBeEnabled();
  await createButton(page).click();
  await expect
    .poll(() => workflowNamed(projectId, name).length, 'workflow saved')
    .toBe(1);
  return workflowNamed(projectId, name)[0].id;
}

// When I paste <yaml> and try to create it; Then it is refused with <codes>,
// and nothing reaches the project, even with Create pressed regardless
async function expectRefused(
  page: Page,
  open: OpenImport,
  projectId: string,
  yaml: string,
  ...shown: (string | RegExp)[]
) {
  await openOnce(page, open);
  await paste(page, yaml);
  for (const text of shown) await expect(errorBox(page)).toContainText(text);
  await createButton(page).click({ force: true });
  await page.waitForTimeout(1000);
  const name = (YAML.parse(yaml) as { name?: string }).name ?? '';
  expect(workflowNamed(projectId, name)).toHaveLength(0);
}

type Shape = {
  jobs: { name: string; adaptor: string; body: string }[];
  triggers: {
    type: string;
    enabled: boolean;
    webhook_reply: string | null;
    cron_expression: string | null;
    cron_cursor: string | null;
    custom_path: string | null;
  }[];
  edges: {
    from: string;
    to: string;
    condition: string;
    expression: string | null;
    label: string | null;
    enabled: boolean;
  }[];
};

// What a stored workflow does: its steps, triggers and edges, by name
export const shapeOf = (workflowId: string) =>
  sql<{ shape: Shape }>(
    `select json_build_object(
       'jobs', coalesce((select json_agg(json_build_object('name', name, 'adaptor', adaptor, 'body', rtrim(body, E' \\n'))
                         order by name) from jobs where workflow_id = '${workflowId}'), '[]'),
       'triggers', coalesce((select json_agg(json_build_object('type', t.type, 'enabled', t.enabled,
                               'webhook_reply', t.webhook_reply, 'cron_expression', t.cron_expression,
                               'cron_cursor', cj.name, 'custom_path', t.custom_path) order by t.type)
                             from triggers t left join jobs cj on cj.id = t.cron_cursor_job_id
                             where t.workflow_id = '${workflowId}'), '[]'),
       'edges', coalesce((select json_agg(json_build_object('from', coalesce(sj.name, st.type::text), 'to', tj.name,
                            'condition', e.condition_type, 'expression', rtrim(e.condition_expression, E' \\n'),
                            'label', e.condition_label, 'enabled', e.enabled)
                            order by coalesce(sj.name, st.type::text), tj.name)
                          from workflow_edges e
                          left join jobs sj on sj.id = e.source_job_id
                          left join triggers st on st.id = e.source_trigger_id
                          join jobs tj on tj.id = e.target_job_id
                          where e.workflow_id = '${workflowId}'), '[]')
     ) as shape`
  )[0].shape;

const job = (name: string, adaptor = '@openfn/language-common@latest') => ({
  name,
  adaptor,
  body: 'fn(state => state)\n',
});

// The canonical workflow in each format (test/fixtures/portability), without
// the credential reference, which names a credential the project lacks
const v1Canonical = (name: string) => ({
  name,
  jobs: {
    ingest: job('ingest', '@openfn/language-http@latest'),
    transform: job('transform'),
    'report-failure': job('report failure'),
    'maybe-skip': job('maybe skip'),
    load: job('load'),
  },
  triggers: {
    cron: {
      type: 'cron',
      enabled: false,
      cron_expression: '0 6 * * *',
      cron_cursor_job: 'ingest',
    },
    webhook: {
      type: 'webhook',
      enabled: true,
      webhook_reply: 'after_completion',
    },
  },
  edges: {
    'cron->ingest': edge({ source_trigger: 'cron' }, 'ingest'),
    'webhook->ingest': edge({ source_trigger: 'webhook' }, 'ingest'),
    'ingest->transform': edge(
      { source_job: 'ingest' },
      'transform',
      'on_job_success'
    ),
    'ingest->report-failure': edge(
      { source_job: 'ingest' },
      'report-failure',
      'on_job_failure'
    ),
    'ingest->maybe-skip': {
      ...edge({ source_job: 'ingest' }, 'maybe-skip', 'js_expression'),
      condition_label: 'Skip when no errors',
      condition_expression: '!state.errors && state.data\n',
      enabled: false,
    },
    'transform->load': edge({ source_job: 'transform' }, 'load'),
    'report-failure->load': edge({ source_job: 'report-failure' }, 'load'),
  },
});

function edge(
  source: { source_trigger: string } | { source_job: string },
  target: string,
  condition = 'always'
) {
  return {
    ...source,
    target_job: target,
    condition_type: condition,
    enabled: true,
  };
}

const step = (id: string, extra: object = {}) => ({
  id,
  name: id.replace('-', ' '),
  adaptor: '@openfn/language-common@latest',
  expression: 'fn(state => state)\n',
  ...extra,
});

const v2Canonical = (name: string) => ({
  id: 'canonical-workflow',
  name,
  start: 'cron',
  steps: [
    {
      id: 'cron',
      name: 'cron',
      enabled: false,
      type: 'cron',
      cron_expression: '0 6 * * *',
      cron_cursor: 'ingest',
      next: { ingest: { condition: 'always' } },
    },
    {
      id: 'webhook',
      name: 'webhook',
      enabled: true,
      type: 'webhook',
      webhook_reply: 'after_completion',
      next: { ingest: { condition: 'always' } },
    },
    step('ingest', {
      adaptor: '@openfn/language-http@latest',
      next: {
        'maybe-skip': {
          condition: '!state.errors && state.data\n',
          label: 'Skip when no errors',
          disabled: true,
        },
        'report-failure': { condition: 'on_job_failure' },
        transform: { condition: 'on_job_success' },
      },
    }),
    step('transform', { next: { load: { condition: 'always' } } }),
    step('report-failure', { next: { load: { condition: 'always' } } }),
    step('maybe-skip'),
    step('load'),
  ],
});

// A small v1 file: one step "fetch" behind a webhook, with <jobs> overriding
const v1Small = (
  name: string,
  jobs: Record<string, object> = { fetch: job('fetch') },
  triggers: Record<string, object> = {
    webhook: { type: 'webhook', enabled: true },
  }
) => ({
  name,
  jobs,
  triggers,
  edges: Object.fromEntries(
    Object.keys(triggers).map(t => [
      `${t}->fetch`,
      edge({ source_trigger: t }, Object.keys(jobs)[0]),
    ])
  ),
});

export const given = {
  S01: {
    formats: {
      v1: (name: string) => YAML.stringify(v1Canonical(name)),
      v2: (name: string) => YAML.stringify(v2Canonical(name)),
    },
    steps: ['ingest', 'load', 'maybe skip', 'report failure', 'transform'],
  },
  S03: [
    { next: 'b', condition: 'always', expression: null },
    { next: { b: true }, condition: 'always', expression: null },
    {
      next: { b: { condition: 'on_job_failure' } },
      condition: 'on_job_failure',
      expression: null,
    },
    {
      next: { b: 'state.data.ok' },
      condition: 'js_expression',
      expression: 'state.data.ok',
    },
    {
      next: { b: false },
      condition: 'js_expression',
      expression: 'false',
    },
  ],
  S05: [
    {
      problem: 'job "fetch" has no "body"',
      jobs: {
        fetch: { name: 'fetch', adaptor: '@openfn/language-common@latest' },
      },
      code: 'SCHEMA_MISSING_PROPERTY',
      path: '/jobs/fetch',
    },
    {
      problem: 'job "fetch" has an extra key "timeout"',
      jobs: { fetch: { ...job('fetch'), timeout: 30 } },
      code: 'SCHEMA_INVALID_PROPERTY',
      path: '/jobs/fetch',
    },
    {
      problem: 'job "fetch" has "body: 42"',
      jobs: { fetch: { ...job('fetch'), body: 42 } },
      code: 'SCHEMA_TYPE_ERROR',
      path: '/jobs/fetch/body',
    },
  ],
  S09: [
    { format: 'v2', enabled: undefined, outcome: false },
    { format: 'v2', enabled: true, outcome: true },
    { format: 'v1', enabled: undefined, outcome: 'SCHEMA_MISSING_PROPERTY' },
  ] as const,
};

// @S01 Both workflow formats are accepted
//   Given the canonical workflow in <format> format
//   When I import it
//   Then the workflow has steps "ingest", "load", "maybe skip", "report failure" and "transform"
//   And it has a cron trigger and a webhook trigger
export async function S01(
  page: Page,
  open: OpenImport,
  projectId: string,
  format: keyof typeof given.S01.formats
) {
  const id = await importFile(
    page,
    open,
    projectId,
    given.S01.formats[format](`Canonical ${format}`)
  );

  const shape = shapeOf(id);
  expect(shape.jobs.map(j => j.name)).toEqual(given.S01.steps);
  expect(shape.triggers.map(t => t.type).sort()).toEqual(['cron', 'webhook']);
}

// @S02 A workflow keeps its logic through export and re-import
//   Given a workflow whose webhook replies "after_completion" and whose cron trigger runs "0 6 * * *" with cursor step "ingest"
//   And "ingest" leads to "transform" on success, to "report failure" on failure, and to "maybe skip" on the JS condition "!state.errors && state.data" labelled "Skip when no errors" and disabled
//   When I import the v2 YAML the code view produces for it
//   Then the imported workflow has the same steps, adaptors and code
//   And the same edges with the same conditions, label and disabled state
//   And the same webhook reply, cron expression and cron cursor
// The host seeds the workflow with seedCanonicalWorkflow and copies its code
// view's text into <exported>. Only the name differs, so it is renamed.
export async function S02(
  page: Page,
  open: OpenImport,
  projectId: string,
  original: { id: string; name: string },
  exported: string
) {
  const doc = YAML.parse(exported) as { name: string };
  expect(doc.name).toBe(original.name);
  doc.name = `${original.name} copy`;
  const id = await importFile(page, open, projectId, YAML.stringify(doc));

  const before = shapeOf(original.id);
  const after = shapeOf(id);
  expect(after.jobs).toEqual(before.jobs);
  expect(after.edges).toEqual(before.edges);
  // A trigger's enabled state follows the file (S09), not the source
  const behaviour = (s: Shape) =>
    s.triggers.map(t => ({ ...t, enabled: undefined }));
  expect(behaviour(after)).toEqual(behaviour(before));
}

// @S03 v2 edge conditions keep their meaning
//   Given a v2 file where step "a" has next "b" written as <next>
//   When I import it
//   Then the edge from "a" to "b" has condition <condition>
// <example> is one row of given.S03.
export async function S03(
  page: Page,
  open: OpenImport,
  projectId: string,
  example: (typeof given.S03)[number]
) {
  const name = `Edge conditions ${given.S03.indexOf(example) + 1}`;
  const yaml = YAML.stringify({
    name,
    steps: [
      {
        id: 'webhook',
        type: 'webhook',
        enabled: true,
        next: { a: { condition: 'always' } },
      },
      step('a', { next: example.next }),
      step('b'),
    ],
  });
  const id = await importFile(page, open, projectId, yaml);

  const fromA = shapeOf(id).edges.filter(e => e.from === 'a');
  expect(fromA).toHaveLength(1);
  expect(fromA[0]).toMatchObject({
    to: 'b',
    condition: example.condition,
    expression: example.expression,
  });
}

// @S04 Text that is not valid YAML is refused with the parser's reason
//   Given the YAML import dialog is open in paste mode
//   When I paste "invalid: [syntax"
//   Then I see "Validation Error" with the code "YAML_SYNTAX_ERROR"
//   And the message starts "YAML syntax error:" and ends "Please check your YAML formatting."
export async function S04(page: Page, open: OpenImport, projectId: string) {
  await openOnce(page, open);
  await paste(page, 'invalid: [syntax');
  await expect(errorBox(page)).toContainText('YAML_SYNTAX_ERROR');
  await expect(errorBox(page)).toContainText(
    /YAML syntax error:[\s\S]*Please check your YAML formatting\./
  );
  await createButton(page).click({ force: true });
  await page.waitForTimeout(1000);
  expect(
    sql(`select id from workflows where project_id = '${projectId}'`)
  ).toHaveLength(0);
}

// @S05 A file that does not match the format names the field and its path
//   Given the YAML import dialog is open in paste mode
//   When I paste a v1 workflow where <problem>
//   Then I see the code "<code>" and the path "<path>"
// <example> is one row of given.S05.
export async function S05(
  page: Page,
  open: OpenImport,
  projectId: string,
  example: (typeof given.S05)[number]
) {
  await expectRefused(
    page,
    open,
    projectId,
    YAML.stringify(v1Small('Bad field', example.jobs)),
    example.code,
    example.path
  );
}

// @S06 An edge to a missing step is refused
//   Given a <format> file whose edge from "ingest" targets "load-data", which the file does not define
//   When I import it
//   Then I see the code "JOB_NOT_FOUND" and a message naming "load-data"
//   And nothing is written to the workflow
export async function S06(
  page: Page,
  open: OpenImport,
  projectId: string,
  format: 'v1' | 'v2'
) {
  const name = 'Missing step';
  const yaml =
    format === 'v1'
      ? YAML.stringify({
          ...v1Small(name, { ingest: job('ingest') }),
          edges: {
            'webhook->ingest': edge({ source_trigger: 'webhook' }, 'ingest'),
            'ingest->load-data': edge({ source_job: 'ingest' }, 'load-data'),
          },
        })
      : YAML.stringify({
          name,
          steps: [
            {
              id: 'webhook',
              type: 'webhook',
              enabled: true,
              next: { ingest: { condition: 'always' } },
            },
            step('ingest', { next: { 'load-data': { condition: 'always' } } }),
          ],
        });
  await expectRefused(
    page,
    open,
    projectId,
    yaml,
    'JOB_NOT_FOUND',
    'load-data'
  );
}

// @S07 Two step names that would export to the same key are refused
//   Given a v1 file with steps named "a b" and "a-b"
//   When I import it
//   Then I see the code "DUPLICATE_JOB_NAME"
//   But a file with steps named "a b" and "a c" imports
export async function S07(page: Page, open: OpenImport, projectId: string) {
  const file = (name: string, second: string) =>
    YAML.stringify(
      v1Small(name, {
        fetch: job('a b'),
        second: job(second),
      })
    );
  await expectRefused(
    page,
    open,
    projectId,
    file('Clashing names', 'a-b'),
    'DUPLICATE_JOB_NAME'
  );

  const id = await importFile(
    page,
    open,
    projectId,
    file('Distinct names', 'a c')
  );
  expect(shapeOf(id).jobs.map(j => j.name)).toEqual(['a b', 'a c']);
}

// @S08 Only webhook and cron triggers are accepted
//   Given a v1 file with a trigger of type "kafka"
//   When I import it
//   Then I see the code "SCHEMA_INVALID_VALUE" and "Must be one of: cron, webhook"
export async function S08(page: Page, open: OpenImport, projectId: string) {
  await expectRefused(
    page,
    open,
    projectId,
    YAML.stringify(
      v1Small('Kafka trigger', undefined, {
        kafka: { type: 'kafka', enabled: true },
      })
    ),
    'SCHEMA_INVALID_VALUE',
    /Must be one of: cron, webhook/
  );
}

// @S09 Triggers are only on when the file says so
//   Given a <format> file whose webhook trigger <enabled>
//   When I import it
//   Then <outcome>
// <example> is one row of given.S09: an outcome of true or false is the
// imported trigger's enabled state, a code is the refusal naming "enabled".
export async function S09(
  page: Page,
  open: OpenImport,
  projectId: string,
  example: (typeof given.S09)[number]
) {
  const name = `Trigger ${example.format} ${String(example.enabled)}`;
  const webhook = {
    type: 'webhook',
    ...(example.enabled !== undefined && { enabled: example.enabled }),
  };
  const yaml =
    example.format === 'v1'
      ? YAML.stringify(v1Small(name, undefined, { webhook }))
      : YAML.stringify({
          name,
          steps: [
            {
              id: 'webhook',
              ...webhook,
              next: { fetch: { condition: 'always' } },
            },
            step('fetch'),
          ],
        });

  if (typeof example.outcome === 'string') {
    await expectRefused(
      page,
      open,
      projectId,
      yaml,
      example.outcome,
      'enabled'
    );
    return;
  }
  const id = await importFile(page, open, projectId, yaml);
  expect(shapeOf(id).triggers).toEqual([
    expect.objectContaining({ type: 'webhook', enabled: example.outcome }),
  ]);
}

// @S10 The workflow id in a file is ignored
//   Given workflow "Lab results" exists with id "<lab id>"
//   And a v1 file whose top-level "id" is "<lab id>"
//   When I import it as a new workflow
//   Then a separate workflow is created
//   And "Lab results" is unchanged
// The host seeds "Lab results" with seedCanonicalWorkflow.
export async function S10(
  page: Page,
  open: OpenImport,
  projectId: string,
  lab: { id: string }
) {
  const before = shapeOf(lab.id);
  const version = () =>
    sql<{ lock_version: number }>(
      `select lock_version from workflows where id = '${lab.id}'`
    )[0].lock_version;
  const was = version();

  const id = await importFile(
    page,
    open,
    projectId,
    YAML.stringify({ id: lab.id, ...v1Small('Lab results import') })
  );

  expect(id).not.toBe(lab.id);
  expect(shapeOf(id).jobs.map(j => j.name)).toEqual(['fetch']);
  expect(shapeOf(lab.id)).toEqual(before);
  expect(version()).toBe(was);
}

// @S11 Re-applying a file that does not mention a webhook path keeps the live path
//   Given workflow "Intake" has a webhook trigger with custom path "facility-001"
//   When a v1 file for "Intake" that keeps the trigger's id but has no "custom_path" is applied
//   Then the webhook trigger still has custom path "facility-001"
//   But when the file says "custom_path: facility-002" the trigger has "facility-002"
// The host seeds "Intake" with seedCanonicalWorkflow(..., { customPath:
// 'facility-001' }), opens it, and gives <apply>, which applies a file to the
// open workflow (the AI assistant's apply), and <save>, which saves it.
export async function S11(
  _page: Page,
  intake: SeededCanonical,
  apply: (yaml: string) => Promise<void>,
  save: () => Promise<void>
) {
  const file = (customPath?: string) =>
    YAML.stringify({
      id: intake.id,
      name: intake.name,
      jobs: { ingest: job('ingest', '@openfn/language-http@latest') },
      triggers: {
        webhook: {
          id: intake.webhookId,
          type: 'webhook',
          enabled: true,
          ...(customPath && { custom_path: customPath }),
        },
      },
      edges: {
        'webhook->ingest': edge({ source_trigger: 'webhook' }, 'ingest'),
      },
    });
  const path = () =>
    sql<{ custom_path: string | null }>(
      `select custom_path from triggers where id = '${intake.webhookId}'`
    )[0]?.custom_path;

  await apply(file());
  await save();
  await expect
    .poll(() => shapeOf(intake.id).jobs.map(j => j.name))
    .toEqual(['ingest']);
  expect(path()).toBe('facility-001');

  await apply(file('facility-002'));
  await save();
  await expect.poll(path).toBe('facility-002');
}

// Seeding for hosts

export type SeededCanonical = { id: string; name: string; webhookId: string };

// Given "<by>" built the canonical workflow <name> in project <projectId>
// through Lightning: the steps, edges and triggers of
// test/fixtures/portability. A <customPath> goes on its webhook trigger.
export function seedCanonicalWorkflow(
  projectId: string,
  by: string,
  { name = 'Intake', customPath }: { name?: string; customPath?: string } = {}
): SeededCanonical {
  const ex = (v: unknown) => JSON.stringify(v);
  const jobs = Object.entries(v1Canonical(name).jobs)
    .map(
      ([key, j]) =>
        `%{id: ids[${ex(key)}], name: ${ex(j.name)}, adaptor: ${ex(j.adaptor)}, body: ${ex(j.body)}}`
    )
    .join(', ');
  const edges = Object.values(v1Canonical(name).edges)
    .map(e => {
      const source =
        'source_trigger' in e
          ? `source_trigger_id: ids[${ex(e.source_trigger)}]`
          : `source_job_id: ids[${ex(e.source_job)}]`;
      const js =
        'condition_expression' in e
          ? `, condition_expression: ${ex(e.condition_expression)}, condition_label: ${ex(e.condition_label)}`
          : '';
      return `%{id: Ecto.UUID.generate(), ${source}, target_job_id: ids[${ex(e.target_job)}], condition_type: :${e.condition_type}, enabled: ${e.enabled}${js}}`;
    })
    .join(', ');
  const out = lastLine(
    onNode(`
      by = Lightning.Repo.get!(Lightning.Accounts.User, ${ex(user(by).id)})
      ids = Map.new(~w(ingest transform report-failure maybe-skip load cron webhook), &{&1, Ecto.UUID.generate()})
      {:ok, wf} = Lightning.Workflows.save_workflow(%{name: ${ex(name)}, project_id: ${ex(projectId)},
        jobs: [${jobs}],
        triggers: [
          %{id: ids["cron"], type: :cron, enabled: false, cron_expression: "0 6 * * *", cron_cursor_job_id: ids["ingest"]},
          %{id: ids["webhook"], type: :webhook, enabled: true, webhook_reply: :after_completion${customPath ? `, custom_path: ${ex(customPath)}` : ''}}
        ],
        edges: [${edges}]}, by)
      Jason.encode!(%{id: wf.id, webhookId: ids["webhook"]})`)
  );
  return {
    name,
    ...(JSON.parse(JSON.parse(out) as string) as {
      id: string;
      webhookId: string;
    }),
  };
}
