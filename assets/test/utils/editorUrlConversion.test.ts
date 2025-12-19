import { describe, expect, it } from 'vitest';

import {
  buildClassicalEditorUrl,
  buildCollaborativeEditorUrl,
  classicalToCollaborativeParams,
  collaborativeToClassicalParams,
  getMappingConfig,
  isValidModeType,
  isValidPanelType,
} from '../../js/utils/editorUrlConversion';

describe('editorUrlConversion', () => {
  describe('collaborativeToClassicalParams', () => {
    it('converts run parameter', () => {
      const input = new URLSearchParams('run=run-123');
      const output = collaborativeToClassicalParams(input);

      expect(output.get('a')).toBe('run-123');
      expect(output.get('run')).toBeNull();
    });

    it('converts job parameter to s', () => {
      const input = new URLSearchParams('job=job-abc');
      const output = collaborativeToClassicalParams(input);

      expect(output.get('s')).toBe('job-abc');
      expect(output.get('job')).toBeNull();
    });

    it('converts trigger parameter to s', () => {
      const input = new URLSearchParams('trigger=trigger-xyz');
      const output = collaborativeToClassicalParams(input);

      expect(output.get('s')).toBe('trigger-xyz');
      expect(output.get('trigger')).toBeNull();
    });

    it('converts edge parameter to s', () => {
      const input = new URLSearchParams('edge=edge-456');
      const output = collaborativeToClassicalParams(input);

      expect(output.get('s')).toBe('edge-456');
      expect(output.get('edge')).toBeNull();
    });

    it('converts panel=editor to m=expand', () => {
      const input = new URLSearchParams('panel=editor');
      const output = collaborativeToClassicalParams(input);

      expect(output.get('m')).toBe('expand');
      expect(output.get('panel')).toBeNull();
    });

    it('converts panel=run to m=workflow_input', () => {
      const input = new URLSearchParams('panel=run');
      const output = collaborativeToClassicalParams(input);

      expect(output.get('m')).toBe('workflow_input');
      expect(output.get('panel')).toBeNull();
    });

    it('converts panel=settings to m=settings', () => {
      const input = new URLSearchParams('panel=settings');
      const output = collaborativeToClassicalParams(input);

      expect(output.get('m')).toBe('settings');
    });

    it('preserves standard params', () => {
      const input = new URLSearchParams(
        'v=123&method=ai&w-chat=chat-1&j-chat=chat-2&code=true'
      );
      const output = collaborativeToClassicalParams(input);

      expect(output.get('v')).toBe('123');
      expect(output.get('method')).toBe('ai');
      expect(output.get('w-chat')).toBe('chat-1');
      expect(output.get('j-chat')).toBe('chat-2');
      expect(output.get('code')).toBe('true');
    });

    it('preserves unknown params for future compatibility', () => {
      const input = new URLSearchParams('unknown=value');
      const output = collaborativeToClassicalParams(input);

      expect(output.get('unknown')).toBe('value');
    });

    it('handles complex conversion with multiple params', () => {
      const input = new URLSearchParams(
        'run=run-123&job=job-abc&panel=editor&v=5&method=ai'
      );
      const output = collaborativeToClassicalParams(input);

      expect(output.get('a')).toBe('run-123');
      expect(output.get('s')).toBe('job-abc');
      expect(output.get('m')).toBe('expand');
      expect(output.get('v')).toBe('5');
      expect(output.get('method')).toBe('ai');
    });
  });

  describe('classicalToCollaborativeParams', () => {
    it('converts a parameter to run', () => {
      const input = new URLSearchParams('a=run-123');
      const output = classicalToCollaborativeParams(input);

      expect(output.get('run')).toBe('run-123');
      expect(output.get('a')).toBeNull();
    });

    it('converts s parameter to job by default', () => {
      const input = new URLSearchParams('s=item-123');
      const output = classicalToCollaborativeParams(input);

      expect(output.get('job')).toBe('item-123');
      expect(output.get('s')).toBeNull();
    });

    it('converts s parameter based on context', () => {
      const input = new URLSearchParams('s=trigger-xyz');
      const output = classicalToCollaborativeParams(input, {
        selectedType: 'trigger',
      });

      expect(output.get('trigger')).toBe('trigger-xyz');
      expect(output.get('job')).toBeNull();
    });

    it('converts m=expand to panel=editor', () => {
      const input = new URLSearchParams('m=expand');
      const output = classicalToCollaborativeParams(input);

      expect(output.get('panel')).toBe('editor');
      expect(output.get('m')).toBeNull();
    });

    it('converts m=workflow_input to panel=run', () => {
      const input = new URLSearchParams('m=workflow_input');
      const output = classicalToCollaborativeParams(input);

      expect(output.get('panel')).toBe('run');
    });

    it('converts m=settings to panel=settings', () => {
      const input = new URLSearchParams('m=settings');
      const output = classicalToCollaborativeParams(input);

      expect(output.get('panel')).toBe('settings');
    });

    it('skips nil/empty values', () => {
      const input = new URLSearchParams('a=&s=job-123');
      const output = classicalToCollaborativeParams(input);

      expect(output.get('run')).toBeNull();
      expect(output.get('job')).toBe('job-123');
    });

    it('preserves standard params', () => {
      const input = new URLSearchParams(
        'v=123&method=ai&w-chat=chat-1&j-chat=chat-2'
      );
      const output = classicalToCollaborativeParams(input);

      expect(output.get('v')).toBe('123');
      expect(output.get('method')).toBe('ai');
      expect(output.get('w-chat')).toBe('chat-1');
      expect(output.get('j-chat')).toBe('chat-2');
    });
  });

  describe('buildClassicalEditorUrl', () => {
    it('builds URL for existing workflow', () => {
      const url = buildClassicalEditorUrl({
        projectId: 'proj-123',
        workflowId: 'wf-456',
        searchParams: new URLSearchParams('run=run-789&job=job-abc'),
        isNewWorkflow: false,
      });

      expect(url).toBe('/projects/proj-123/w/wf-456?a=run-789&s=job-abc');
    });

    it('builds URL for new workflow', () => {
      const url = buildClassicalEditorUrl({
        projectId: 'proj-123',
        workflowId: null,
        searchParams: new URLSearchParams('job=job-abc&panel=editor'),
        isNewWorkflow: true,
      });

      expect(url).toBe('/projects/proj-123/w/new?s=job-abc&m=expand');
    });

    it('builds URL without query params when empty', () => {
      const url = buildClassicalEditorUrl({
        projectId: 'proj-123',
        workflowId: 'wf-456',
        searchParams: new URLSearchParams(),
        isNewWorkflow: false,
      });

      expect(url).toBe('/projects/proj-123/w/wf-456');
    });

    it('handles complex parameter conversion', () => {
      const url = buildClassicalEditorUrl({
        projectId: 'proj-1',
        workflowId: 'wf-1',
        searchParams: new URLSearchParams(
          'run=r-1&trigger=t-1&panel=run&v=5&method=ai'
        ),
        isNewWorkflow: false,
      });

      expect(url).toBe(
        '/projects/proj-1/w/wf-1?a=r-1&s=t-1&m=workflow_input&v=5&method=ai'
      );
    });
  });

  describe('buildCollaborativeEditorUrl', () => {
    it('builds URL for existing workflow', () => {
      const url = buildCollaborativeEditorUrl({
        projectId: 'proj-123',
        workflowId: 'wf-456',
        searchParams: new URLSearchParams('a=run-789&s=job-abc&m=expand'),
        isNewWorkflow: false,
        selectedType: 'job',
      });

      expect(url).toBe(
        '/projects/proj-123/w/wf-456/collaborate?run=run-789&job=job-abc&panel=editor'
      );
    });

    it('builds URL for new workflow', () => {
      const url = buildCollaborativeEditorUrl({
        projectId: 'proj-123',
        workflowId: null,
        searchParams: new URLSearchParams('s=job-abc'),
        isNewWorkflow: true,
      });

      expect(url).toBe(
        '/projects/proj-123/w/new/collaborate?method=template&job=job-abc'
      );
    });

    it('builds URL without query params when empty', () => {
      const url = buildCollaborativeEditorUrl({
        projectId: 'proj-123',
        workflowId: 'wf-456',
        searchParams: new URLSearchParams(),
        isNewWorkflow: false,
      });

      expect(url).toBe('/projects/proj-123/w/wf-456/collaborate');
    });
  });

  describe('Type guards', () => {
    describe('isValidPanelType', () => {
      it('returns true for valid panel types', () => {
        expect(isValidPanelType('editor')).toBe(true);
        expect(isValidPanelType('run')).toBe(true);
        expect(isValidPanelType('settings')).toBe(true);
      });

      it('returns false for invalid panel types', () => {
        expect(isValidPanelType('invalid')).toBe(false);
        expect(isValidPanelType('')).toBe(false);
        expect(isValidPanelType('expand')).toBe(false);
      });
    });

    describe('isValidModeType', () => {
      it('returns true for valid mode types', () => {
        expect(isValidModeType('expand')).toBe(true);
        expect(isValidModeType('workflow_input')).toBe(true);
        expect(isValidModeType('settings')).toBe(true);
      });

      it('returns false for invalid mode types', () => {
        expect(isValidModeType('invalid')).toBe(false);
        expect(isValidModeType('')).toBe(false);
        expect(isValidModeType('editor')).toBe(false);
      });
    });
  });

  describe('getMappingConfig', () => {
    it('returns the mapping configuration', () => {
      const config = getMappingConfig();

      expect(config).toHaveProperty('classicalToCollaborative');
      expect(config).toHaveProperty('collaborativeToClassical');
      expect(config).toHaveProperty('preservedParams');
      expect(config.preservedParams).toContain('v');
      expect(config.preservedParams).toContain('method');
    });
  });

  describe('Bidirectional conversion', () => {
    it('maintains consistency when converting back and forth', () => {
      // Start with classical params
      const classical1 = new URLSearchParams(
        'a=run-123&s=job-abc&m=expand&v=5'
      );

      // Convert to collaborative
      const collaborative = classicalToCollaborativeParams(classical1, {
        selectedType: 'job',
      });

      expect(collaborative.get('run')).toBe('run-123');
      expect(collaborative.get('job')).toBe('job-abc');
      expect(collaborative.get('panel')).toBe('editor');
      expect(collaborative.get('v')).toBe('5');

      // Convert back to classical
      const classical2 = collaborativeToClassicalParams(collaborative);

      expect(classical2.get('a')).toBe('run-123');
      expect(classical2.get('s')).toBe('job-abc');
      expect(classical2.get('m')).toBe('expand');
      expect(classical2.get('v')).toBe('5');
    });
  });
});
