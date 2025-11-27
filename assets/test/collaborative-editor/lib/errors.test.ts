/**
 * Tests for error formatting utilities
 *
 * Tests the formatChannelErrorMessage function which handles
 * nested error structures from Phoenix channel responses.
 */

import { describe, expect, it } from 'vitest';
import { formatChannelErrorMessage } from '../../../js/collaborative-editor/lib/errors';
import type { ChannelError } from '../../../js/collaborative-editor/types/errors';

describe('formatChannelErrorMessage', () => {
  it('should format base errors', () => {
    const error: ChannelError = {
      errors: {
        base: ['Something went wrong'],
      },
    };

    const result = formatChannelErrorMessage(error);
    expect(result).toBe('Something went wrong');
  });

  it('should format simple field errors (from nested structure)', () => {
    // The function expects errors to be nested in arrays, then flattened
    const error: ChannelError = {
      errors: {
        field: [[{ name: ['Name is required'] }]],
      },
    };

    const result = formatChannelErrorMessage(error);
    expect(result).toBe('Name: Name is required');
  });

  it('should format multiple errors for a single field (from nested structure)', () => {
    const error: ChannelError = {
      errors: {
        field: [[{ email: ['Email is required', 'Email must be valid'] }]],
      },
    };

    const result = formatChannelErrorMessage(error);
    expect(result).toBe('Email: Email is required, Email must be valid');
  });

  it('should format nested errors (edges with condition_expression)', () => {
    // Structure after flat(2): edges object -> edge-123 object -> field arrays
    const error: ChannelError = {
      errors: {
        edges: [
          [
            {
              condition_expression: ["can't be blank"],
            },
          ],
        ],
      },
    };

    const result = formatChannelErrorMessage(error);
    expect(result).toBe("Condition Expression: can't be blank");
  });

  it('should format nested errors with multiple fields', () => {
    const error: ChannelError = {
      errors: {
        jobs: [
          [
            {
              name: ['Name is too long'],
              adaptor: ['Adaptor not found'],
            },
          ],
        ],
      },
    };

    const result = formatChannelErrorMessage(error);
    expect(result).toContain('Name: Name is too long');
    expect(result).toContain('Adaptor: Adaptor not found');
  });

  it('should handle deeply nested errors', () => {
    const error: ChannelError = {
      errors: {
        triggers: [
          [
            {
              cron_expression: ['Invalid cron expression', 'Must be valid'],
            },
          ],
        ],
      },
    };

    const result = formatChannelErrorMessage(error);
    expect(result).toContain(
      'Cron Expression: Invalid cron expression, Must be valid'
    );
  });

  it('should return default message for empty errors', () => {
    const error: ChannelError = {
      errors: {},
    };

    const result = formatChannelErrorMessage(error);
    expect(result).toBe('An error occurred');
  });

  it('should return default message when no valid error found', () => {
    const error: ChannelError = {
      errors: {
        someField: [],
      },
    };

    const result = formatChannelErrorMessage(error);
    expect(result).toBe('An error occurred');
  });

  it('should capitalize field names properly', () => {
    const error: ChannelError = {
      errors: {
        field: [[{ condition_expression: ["can't be blank"] }]],
      },
    };

    const result = formatChannelErrorMessage(error);
    expect(result).toBe("Condition Expression: can't be blank");
  });

  it('should handle multiple nested error objects', () => {
    const error: ChannelError = {
      errors: {
        edges: [
          [
            {
              condition_label: ['Label is required'],
            },
          ],
        ],
      },
    };

    const result = formatChannelErrorMessage(error);
    // Should format the first error found
    expect(result).toBe('Condition Label: Label is required');
  });

  it('should preserve error message casing', () => {
    const error: ChannelError = {
      errors: {
        field: [[{ name: ['Name must start with UPPERCASE'] }]],
      },
    };

    const result = formatChannelErrorMessage(error);
    expect(result).toBe('Name: Name must start with UPPERCASE');
  });
});
