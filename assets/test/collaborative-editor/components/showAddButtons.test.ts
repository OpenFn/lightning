import { describe, expect, it } from 'vitest';

import { showAddButtons } from '#/collaborative-editor/components/AIAssistantPanelWrapper';

describe('showAddButtons', () => {
  const base = { page: 'job_code', isGlobal: false, hasCodeMessage: false };

  it('offers Add for a job chat reply on the job page', () => {
    expect(showAddButtons(base)).toBe(true);
  });

  it('does not offer Add for a global reply, even on the job page', () => {
    // Add pastes into the open job. A global reply applies its own changes and
    // shows them as diffs, so its code blocks are data it quoted back or work
    // it has already done, and the open job is not what they are about.
    expect(showAddButtons({ ...base, isGlobal: true })).toBe(false);
  });

  it('does not offer Add away from the job page', () => {
    expect(showAddButtons({ ...base, page: 'workflow_template' })).toBe(false);
    expect(showAddButtons({ ...base, page: undefined })).toBe(false);
  });

  it('does not offer Add when the reply carries its own code to apply', () => {
    expect(showAddButtons({ ...base, hasCodeMessage: true })).toBe(false);
  });
});
