/**
 * humanizeCron tests
 *
 * Covers `humanizeCron` — the cron → friendly text helper used by the cron
 * show panel, the builder preview and the diagram node. (Schedule authoring is
 * handled by the CronFieldBuilder dropdown, which does its own parsing, so
 * there is no natural-language parser to test.)
 */

import { describe, expect, test } from 'vitest';

import { humanizeCron } from '../../js/utils/humanizeCron';

describe('humanizeCron', () => {
  test.each<[string, string, string | null]>([
    ['daily at 9 AM', '0 9 * * *', 'At 09:00 AM UTC'],
    ['every 15 minutes', '*/15 * * * *', 'Every 15 minutes'],
    [
      'every 2 hours',
      '0 */2 * * *',
      'At 0 minutes past the hour, every 2 hours',
    ],
    [
      'weekdays at 9 AM',
      '0 9 * * 1-5',
      'At 09:00 AM UTC, Monday through Friday',
    ],
    [
      'monthly on the 15th',
      '30 9 15 * *',
      'At 09:30 AM UTC, on day 15 of the month',
    ],
    [
      'weekly on Sunday midnight',
      '0 0 * * 0',
      'At 12:00 AM UTC, only on Sunday',
    ],
    [
      'hour range',
      '0 9-17 * * 1-5',
      'Every hour, between 09:00 AM and 05:00 PM UTC, Monday through Friday',
    ],
    ['empty string → null', '', null],
    ['invalid expression → null', 'not a cron', null],
  ])('%s', (_label, expression, expected) => {
    expect(humanizeCron(expression)).toBe(expected);
  });
});
