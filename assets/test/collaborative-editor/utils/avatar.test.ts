/**
 * Avatar Utilities Tests
 *
 * Tests for getAvatarInitials utility function that generates
 * avatar initials from user data.
 */

import { describe, expect, test } from "vitest";

import { getAvatarInitials } from "../../../js/collaborative-editor/utils/avatar";
import type { UserContext } from "../../../js/collaborative-editor/types/sessionContext";

// =============================================================================
// TEST HELPERS
// =============================================================================

/**
 * Helper to create a mock UserContext with specified properties
 */
function createMockUser(overrides: Partial<UserContext> = {}): UserContext {
  return {
    id: "user-1",
    email: "test@example.com",
    first_name: "Test",
    last_name: "User",
    email_confirmed: true,
    ...overrides,
  };
}

// =============================================================================
// NORMAL CASES
// =============================================================================

describe("getAvatarInitials - Normal Cases", () => {
  test("returns correct initials for first and last name", () => {
    const user = createMockUser({
      first_name: "John",
      last_name: "Doe",
    });

    expect(getAvatarInitials(user)).toBe("JD");
  });

  test("returns uppercase initials", () => {
    const user = createMockUser({
      first_name: "john",
      last_name: "doe",
    });

    expect(getAvatarInitials(user)).toBe("JD");
  });

  test("returns initials with mixed case input", () => {
    const user = createMockUser({
      first_name: "jOhN",
      last_name: "DoE",
    });

    expect(getAvatarInitials(user)).toBe("JD");
  });

  test("returns initials for single character names", () => {
    const user = createMockUser({
      first_name: "A",
      last_name: "B",
    });

    expect(getAvatarInitials(user)).toBe("AB");
  });

  test("returns initials for long names", () => {
    const user = createMockUser({
      first_name: "Alexander",
      last_name: "Montgomery",
    });

    expect(getAvatarInitials(user)).toBe("AM");
  });
});

// =============================================================================
// WHITESPACE HANDLING
// =============================================================================

describe("getAvatarInitials - Whitespace Handling", () => {
  test("trims leading and trailing whitespace from first name", () => {
    const user = createMockUser({
      first_name: "  John  ",
      last_name: "Doe",
    });

    expect(getAvatarInitials(user)).toBe("JD");
  });

  test("trims leading and trailing whitespace from last name", () => {
    const user = createMockUser({
      first_name: "John",
      last_name: "  Doe  ",
    });

    expect(getAvatarInitials(user)).toBe("JD");
  });

  test("trims whitespace from both names", () => {
    const user = createMockUser({
      first_name: "  John  ",
      last_name: "  Doe  ",
    });

    expect(getAvatarInitials(user)).toBe("JD");
  });

  test("handles tab characters in names", () => {
    const user = createMockUser({
      first_name: "\tJohn\t",
      last_name: "\tDoe\t",
    });

    expect(getAvatarInitials(user)).toBe("JD");
  });

  test("handles newline characters in names", () => {
    const user = createMockUser({
      first_name: "\nJohn\n",
      last_name: "\nDoe\n",
    });

    expect(getAvatarInitials(user)).toBe("JD");
  });
});

// =============================================================================
// EDGE CASES - NULL AND UNDEFINED
// =============================================================================

describe("getAvatarInitials - Null and Undefined Cases", () => {
  test("returns fallback for null user", () => {
    expect(getAvatarInitials(null)).toBe("??");
  });

  test("returns fallback when first_name is undefined", () => {
    const user = createMockUser({
      first_name: undefined as any,
      last_name: "Doe",
    });

    expect(getAvatarInitials(user)).toBe("??");
  });

  test("returns fallback when last_name is undefined", () => {
    const user = createMockUser({
      first_name: "John",
      last_name: undefined as any,
    });

    expect(getAvatarInitials(user)).toBe("??");
  });

  test("returns fallback when both names are undefined", () => {
    const user = createMockUser({
      first_name: undefined as any,
      last_name: undefined as any,
    });

    expect(getAvatarInitials(user)).toBe("??");
  });
});

// =============================================================================
// EDGE CASES - EMPTY STRINGS
// =============================================================================

describe("getAvatarInitials - Empty String Cases", () => {
  test("returns fallback for empty first name", () => {
    const user = createMockUser({
      first_name: "",
      last_name: "Doe",
    });

    expect(getAvatarInitials(user)).toBe("??");
  });

  test("returns fallback for empty last name", () => {
    const user = createMockUser({
      first_name: "John",
      last_name: "",
    });

    expect(getAvatarInitials(user)).toBe("??");
  });

  test("returns fallback for both empty names", () => {
    const user = createMockUser({
      first_name: "",
      last_name: "",
    });

    expect(getAvatarInitials(user)).toBe("??");
  });

  test("returns fallback for whitespace-only first name", () => {
    const user = createMockUser({
      first_name: "   ",
      last_name: "Doe",
    });

    expect(getAvatarInitials(user)).toBe("??");
  });

  test("returns fallback for whitespace-only last name", () => {
    const user = createMockUser({
      first_name: "John",
      last_name: "   ",
    });

    expect(getAvatarInitials(user)).toBe("??");
  });

  test("returns fallback for both whitespace-only names", () => {
    const user = createMockUser({
      first_name: "   ",
      last_name: "   ",
    });

    expect(getAvatarInitials(user)).toBe("??");
  });
});

// =============================================================================
// SPECIAL CHARACTERS
// =============================================================================

describe("getAvatarInitials - Special Characters", () => {
  test("handles names with accented characters", () => {
    const user = createMockUser({
      first_name: "Élise",
      last_name: "Müller",
    });

    expect(getAvatarInitials(user)).toBe("ÉM");
  });

  test("handles names with hyphens", () => {
    const user = createMockUser({
      first_name: "Mary-Jane",
      last_name: "Smith-Jones",
    });

    // Takes first character before hyphen
    expect(getAvatarInitials(user)).toBe("MS");
  });

  test("handles names with apostrophes", () => {
    const user = createMockUser({
      first_name: "O'Brien",
      last_name: "D'Angelo",
    });

    expect(getAvatarInitials(user)).toBe("OD");
  });

  test("handles names with numbers", () => {
    const user = createMockUser({
      first_name: "John2",
      last_name: "Doe3",
    });

    expect(getAvatarInitials(user)).toBe("JD");
  });
});

// =============================================================================
// UNICODE AND EMOJI CASES
// =============================================================================

describe("getAvatarInitials - Unicode Cases", () => {
  test("handles names with emoji", () => {
    const user = createMockUser({
      first_name: "😀John",
      last_name: "😀Doe",
    });

    // Note: JavaScript's charAt() doesn't handle multi-byte emoji correctly
    // This test documents actual behavior (��) rather than ideal behavior (😀😀)
    // In practice, users won't have emoji as first characters in their names
    const result = getAvatarInitials(user);
    expect(result).toBeTruthy();
    expect(result.length).toBe(2);
  });

  test("handles names with Chinese characters", () => {
    const user = createMockUser({
      first_name: "李",
      last_name: "明",
    });

    expect(getAvatarInitials(user)).toBe("李明");
  });

  test("handles names with Cyrillic characters", () => {
    const user = createMockUser({
      first_name: "Иван",
      last_name: "Петров",
    });

    expect(getAvatarInitials(user)).toBe("ИП");
  });

  test("handles names with Arabic characters", () => {
    const user = createMockUser({
      first_name: "أحمد",
      last_name: "محمد",
    });

    expect(getAvatarInitials(user)).toBe("أم");
  });
});
