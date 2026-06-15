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
  test.each<[string, string, string | null]>([
    ['daily at 9 AM', '0 9 * * *', 'At 09:00 AM'],
    ['every 15 minutes', '*/15 * * * *', 'Every 15 minutes'],
    ['weekdays at 9 AM', '0 9 * * 1-5', 'At 09:00 AM, Monday through Friday'],
    [
      'monthly on the 15th',
      '30 9 15 * *',
      'At 09:30 AM, on day 15 of the month',
    ],
    ['weekly on Sunday midnight', '0 0 * * 0', 'At 12:00 AM, only on Sunday'],
    ['empty string → null', '', null],
    ['invalid expression → null', 'not a cron', null],
  ])('%s', (_label, expression, expected) => {
    expect(humanizeCron(expression)).toBe(expected);
  });
});
