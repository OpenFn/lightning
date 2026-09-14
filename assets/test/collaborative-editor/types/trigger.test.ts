/**
 * `TriggerSchema` parses what the server sends, including pre-migration rows.
 * `TriggerDraftSchema` is the stricter rule for what a user may write.
 */

import { describe, expect, test } from 'vitest';

import {
  TriggerDraftSchema,
  TriggerSchema,
  isValidCustomPath,
  toCustomPath,
} from '../../../js/collaborative-editor/types/trigger';

const TRIGGER_ID = '11111111-1111-4111-8111-111111111111';

describe('TriggerSchema', () => {
  test('accepts a custom_path on a cron trigger', () => {
    // Serialised for every type, so rejecting it fails the whole parse.
    const result = TriggerSchema.safeParse({
      id: TRIGGER_ID,
      type: 'cron',
      enabled: true,
      cron_expression: '0 0 * * *',
      custom_path: 'orders.v1',
    });

    expect(result.success).toBe(true);
  });

  test('accepts a webhook path the current rules would reject', () => {
    const result = TriggerSchema.safeParse({
      id: TRIGGER_ID,
      type: 'webhook',
      enabled: true,
      custom_path: 'orders.v1',
    });

    expect(result.success).toBe(true);
  });
});

describe('TriggerDraftSchema', () => {
  const webhook = (custom_path: string | null) => ({
    id: TRIGGER_ID,
    type: 'webhook' as const,
    enabled: true,
    custom_path,
  });

  test('accepts a usable path, and no path at all', () => {
    expect(TriggerDraftSchema.safeParse(webhook('facility-001')).success).toBe(
      true
    );
    expect(TriggerDraftSchema.safeParse(webhook(null)).success).toBe(true);
    expect(
      TriggerDraftSchema.safeParse(webhook('orders_intake_v1')).success
    ).toBe(true);
  });

  test('rejects what the server rejects', () => {
    for (const path of [
      'Orders Intake',
      'orders/intake',
      'orders.v1',
      'ORDERS',
      '3fa85f64-5717-4562-b3fc-2c963f66afa6',
    ]) {
      expect(TriggerDraftSchema.safeParse(webhook(path)).success).toBe(false);
    }
  });
});

describe('toCustomPath', () => {
  test('leaves an already usable path alone', () => {
    // Deriving would strip the hyphens off values the server accepts.
    expect(toCustomPath('facility-001')).toBe('facility-001');
    expect(toCustomPath('-')).toBe('-');
    expect(toCustomPath('_leading')).toBe('_leading');
  });

  test('derives one where it can', () => {
    expect(toCustomPath('ET EMR Facility 003')).toBe('et-emr-facility-003');
    expect(toCustomPath('orders.v1?x=2')).toBe('orders-v1-x-2');
    expect(toCustomPath('  spaced  ')).toBe('spaced');
  });

  test('returns nothing when nothing in it is usable', () => {
    expect(toCustomPath('...')).toBe('');
    expect(toCustomPath('!!!')).toBe('');
  });
});

describe('isValidCustomPath', () => {
  test('matches the draft rule', () => {
    expect(isValidCustomPath('et-emr_facility-001')).toBe(true);
    expect(isValidCustomPath('orders_intake_v1')).toBe(true);
    expect(isValidCustomPath('orders.v1')).toBe(false);
    expect(isValidCustomPath('3fa85f64-5717-4562-b3fc-2c963f66afa6')).toBe(
      false
    );
  });
});
