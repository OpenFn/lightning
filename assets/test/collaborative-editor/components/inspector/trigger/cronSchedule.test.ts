/**
 * cronSchedule utility tests
 *
 * Covers `humanizeCron` — the cron → friendly text helper used by the cron
 * show panel. (Schedule authoring is handled by the CronFieldBuilder dropdown,
 * which does its own parsing, so there is no natural-language parser to test.)
 */

import { describe, expect, test } from 'vitest';

import { humanizeCron } from '../../../../../js/collaborative-editor/components/inspector/trigger/cronSchedule';

describe('humanizeCron', () => {
  test('returns a friendly string for a valid expression', () => {
    const result = humanizeCron('0 9 * * *');
    expect(result).not.toBeNull();
    expect(typeof result).toBe('string');
    expect((result as string).length).toBeGreaterThan(0);
  });

  test('returns null for an invalid expression', () => {
    expect(humanizeCron('not a cron')).toBeNull();
  });
});
