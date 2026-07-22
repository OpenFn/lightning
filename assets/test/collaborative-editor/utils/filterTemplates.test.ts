import { describe, expect, it } from 'vitest';

import type { WorkflowTemplate } from '#/collaborative-editor/types/template';
import { filterTemplates } from '#/collaborative-editor/utils/filterTemplates';

const make = (overrides: Partial<WorkflowTemplate> = {}): WorkflowTemplate => ({
  id: 'template-1',
  name: 'My Template',
  description: null,
  code: '',
  positions: null,
  tags: [],
  workflow_id: null,
  ...overrides,
});

describe('filterTemplates', () => {
  it('returns all templates when query is empty', () => {
    const templates = [make({ id: '1' }), make({ id: '2' })];
    expect(filterTemplates(templates, '')).toEqual(templates);
  });

  it('matches on name', () => {
    const match = make({ id: '1', name: 'DHIS2 to Postgres' });
    const noMatch = make({ id: '2', name: 'Kobo to Google Sheets' });
    expect(filterTemplates([match, noMatch], 'dhis2')).toEqual([match]);
  });

  it('matches on description', () => {
    const match = make({
      id: '1',
      description: 'Syncs patient records from OpenMRS',
    });
    const noMatch = make({ id: '2', description: 'Fetches survey data' });
    expect(filterTemplates([match, noMatch], 'openmrs')).toEqual([match]);
  });

  it('matches on tags', () => {
    const match = make({ id: '1', tags: ['webhook', 'kobo'] });
    const noMatch = make({ id: '2', tags: ['cron', 'http'] });
    expect(filterTemplates([match, noMatch], 'kobo')).toEqual([match]);
  });

  it('matches case-insensitively (caller normalizes to lowercase)', () => {
    const template = make({ name: 'OpenMRS Integration' });
    expect(filterTemplates([template], 'openmrs')).toEqual([template]);
    expect(filterTemplates([template], 'openm')).toEqual([template]);
  });

  it('returns empty array when nothing matches', () => {
    const templates = [make({ name: 'DHIS2' }), make({ name: 'Kobo' })];
    expect(filterTemplates(templates, 'salesforce')).toEqual([]);
  });

  it('matches if any field matches (name OR description OR tags)', () => {
    const template = make({
      name: 'My Workflow',
      description: 'Pulls from DHIS2',
      tags: ['scheduled'],
    });
    expect(filterTemplates([template], 'dhis2')).toEqual([template]);
    expect(filterTemplates([template], 'my workflow')).toEqual([template]);
    expect(filterTemplates([template], 'scheduled')).toEqual([template]);
  });

  it('handles null description without throwing', () => {
    const template = make({ description: null, name: 'Safe Template' });
    expect(() => filterTemplates([template], 'safe')).not.toThrow();
    expect(filterTemplates([template], 'safe')).toEqual([template]);
  });
});
