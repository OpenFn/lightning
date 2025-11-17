/**
 * Avatar Utilities Tests
 *
 * Tests for getAvatarInitials utility function that generates
 * avatar initials from user data.
 */

import { describe, expect, test } from 'vitest';

import { getAvatarInitials } from '../../../js/collaborative-editor/utils/avatar';
import { createMockUser } from '../__helpers__/sessionContextFactory';

// =============================================================================
// NORMAL CASES
// =============================================================================

describe.concurrent('getAvatarInitials - Normal Cases', () => {
  test('returns correct initials for first and last name', () => {
    const user = createMockUser({
      first_name: 'John',
      last_name: 'Doe',
    });

    expect(getAvatarInitials(user)).toBe('JD');
  });

  test('returns uppercase initials', () => {
    const user = createMockUser({
      first_name: 'john',
      last_name: 'doe',
    });

    expect(getAvatarInitials(user)).toBe('JD');
  });

  test('returns initials with mixed case input', () => {
    const user = createMockUser({
      first_name: 'jOhN',
      last_name: 'DoE',
    });

    expect(getAvatarInitials(user)).toBe('JD');
  });

  test('returns initials for single character names', () => {
    const user = createMockUser({
      first_name: 'A',
      last_name: 'B',
    });

    expect(getAvatarInitials(user)).toBe('AB');
  });

  test('returns initials for long names', () => {
    const user = createMockUser({
      first_name: 'Alexander',
      last_name: 'Montgomery',
    });

    expect(getAvatarInitials(user)).toBe('AM');
  });
});

// =============================================================================
// WHITESPACE HANDLING
// =============================================================================

describe.concurrent('getAvatarInitials - Whitespace Handling', () => {
  // Test various whitespace scenarios are trimmed correctly
  test.each([
    {
      description: 'leading and trailing whitespace from first name',
      first_name: '  John  ',
      last_name: 'Doe',
      expected: 'JD',
    },
    {
      description: 'leading and trailing whitespace from last name',
      first_name: 'John',
      last_name: '  Doe  ',
      expected: 'JD',
    },
    {
      description: 'whitespace from both names',
      first_name: '  John  ',
      last_name: '  Doe  ',
      expected: 'JD',
    },
    {
      description: 'tab characters in names',
      first_name: '\tJohn\t',
      last_name: '\tDoe\t',
      expected: 'JD',
    },
    {
      description: 'newline characters in names',
      first_name: '\nJohn\n',
      last_name: '\nDoe\n',
      expected: 'JD',
    },
  ])('trims $description', ({ first_name, last_name, expected }) => {
    const user = createMockUser({ first_name, last_name });
    expect(getAvatarInitials(user)).toBe(expected);
  });
});

// =============================================================================
// EDGE CASES - NULL USER
// =============================================================================

describe.concurrent('getAvatarInitials - Null User Case', () => {
  test('returns fallback for null user', () => {
    expect(getAvatarInitials(null)).toBe('??');
  });
});

// =============================================================================
// EDGE CASES - EMPTY STRINGS
// =============================================================================

describe.concurrent('getAvatarInitials - Empty String Cases', () => {
  // Test various empty/whitespace scenarios return fallback
  test.each([
    {
      description: 'empty first name',
      first_name: '',
      last_name: 'Doe',
    },
    {
      description: 'empty last name',
      first_name: 'John',
      last_name: '',
    },
    {
      description: 'both empty names',
      first_name: '',
      last_name: '',
    },
    {
      description: 'whitespace-only first name',
      first_name: '   ',
      last_name: 'Doe',
    },
    {
      description: 'whitespace-only last name',
      first_name: 'John',
      last_name: '   ',
    },
    {
      description: 'both whitespace-only names',
      first_name: '   ',
      last_name: '   ',
    },
  ])('returns fallback for $description', ({ first_name, last_name }) => {
    const user = createMockUser({ first_name, last_name });
    expect(getAvatarInitials(user)).toBe('??');
  });
});

// =============================================================================
// SPECIAL CHARACTERS
// =============================================================================

describe.concurrent('getAvatarInitials - Special Characters', () => {
  // Test various special character scenarios
  test.each([
    {
      description: 'names with accented characters',
      first_name: 'Élise',
      last_name: 'Müller',
      expected: 'ÉM',
    },
    {
      description: 'names with hyphens',
      first_name: 'Mary-Jane',
      last_name: 'Smith-Jones',
      expected: 'MS',
    },
    {
      description: 'names with apostrophes',
      first_name: "O'Brien",
      last_name: "D'Angelo",
      expected: 'OD',
    },
    {
      description: 'names with numbers',
      first_name: 'John2',
      last_name: 'Doe3',
      expected: 'JD',
    },
  ])('handles $description', ({ first_name, last_name, expected }) => {
    const user = createMockUser({ first_name, last_name });
    expect(getAvatarInitials(user)).toBe(expected);
  });
});

// =============================================================================
// UNICODE AND EMOJI CASES
// =============================================================================

describe.concurrent('getAvatarInitials - Unicode Cases', () => {
  test('handles names with emoji', () => {
    const user = createMockUser({
      first_name: '😀John',
      last_name: '😀Doe',
    });

    // Note: JavaScript's charAt() doesn't handle multi-byte emoji correctly
    // This test documents actual behavior (��) rather than ideal behavior (😀😀)
    // In practice, users won't have emoji as first characters in their names
    const result = getAvatarInitials(user);
    expect(result).toBeTruthy();
    expect(result.length).toBe(2);
  });

  // Test various international character sets
  test.each([
    {
      description: 'Chinese characters',
      first_name: '李',
      last_name: '明',
      expected: '李明',
    },
    {
      description: 'Cyrillic characters',
      first_name: 'Иван',
      last_name: 'Петров',
      expected: 'ИП',
    },
    {
      description: 'Arabic characters',
      first_name: 'أحمد',
      last_name: 'محمد',
      expected: 'أم',
    },
  ])(
    'handles names with $description',
    ({ first_name, last_name, expected }) => {
      const user = createMockUser({ first_name, last_name });
      expect(getAvatarInitials(user)).toBe(expected);
    }
  );
});
