/**
 * The one rule for job and workflow names, shared by every place on the client
 * that checks one. Mirrors `Lightning.Validators.validate_name/3` in
 * `lib/lightning/utils/validators.ex`. Change one and change the other.
 */

export const CONTROL_CHARS_REGEX =
  // eslint-disable-next-line no-control-regex
  /[\u0000-\u001F\u007F-\u009F\u2028\u2029\uFFFE\uFFFF]/u;

export const CONTROL_CHARS_MESSAGE = "Name can't contain control characters.";

export const NAME_MAX_LENGTH = 100;

export const NAME_TOO_LONG_MESSAGE = `Name should not exceed ${String(
  NAME_MAX_LENGTH
)} characters.`;

/**
 * The width of the `jobs.name` and `workflows.name` columns. Postgres counts a
 * varchar in codepoints, not graphemes, so a name can clear the cap above and
 * still not fit. Server half: `Validators.validate_name_fits_column/3`.
 */
export const NAME_COLUMN_LIMIT = 255;

/**
 * Deliberately quotes no number: the limit the user was shown is the grapheme
 * cap above. Mirrors the server message in `Lightning.Workflows.Job`.
 */
export const NAME_TOO_WIDE_MESSAGE =
  'Name is too long, please use a shorter one.';

// The 25 Unicode White_Space characters, which is what Elixir's
// `String.trim/1` strips. JS `.trim()` differs in both directions: it leaves
// U+0085, which Elixir strips, and eats U+FEFF, which Elixir keeps.
const TRIM_CHARS =
  '\u0009\u000a\u000b\u000c\u000d\u0020\u0085\u00a0\u1680\u2000\u2001' +
  '\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029' +
  '\u202f\u205f\u3000';

const TRIM_REGEX = new RegExp(`^[${TRIM_CHARS}]+|[${TRIM_CHARS}]+$`, 'gu');

/**
 * NFC, then trim. The server normalises before it validates, so anything that
 * measures or checks a name on the client has to normalise first too.
 */
export const normalizeName = (value: string): string =>
  value.normalize('NFC').replace(TRIM_REGEX, '');

export const hasControlChars = (value: string): boolean =>
  CONTROL_CHARS_REGEX.test(value);

// True only when the name is nothing but characters that draw nothing. The
// same rule as `@invisible_regex` in lib/lightning/utils/validators.ex,
// written as a property test rather than a list. U+2800 is in because the
// Braille blank is not default-ignorable but still draws nothing.
// `test/fixtures/invisible_codepoints.json` is generated from the server's
// predicate and asserted against this one, so the two cannot drift.
const INVISIBLE_ONLY_REGEX =
  /^[\p{Default_Ignorable_Code_Point}\p{General_Category=Format}\u2800]+$/u;

export const isInvisibleOnly = (value: string): boolean =>
  value !== '' && INVISIBLE_ONLY_REGEX.test(value);

export const NAME_BLANK_MESSAGE = "Name can't be blank.";

const segmenter =
  typeof Intl.Segmenter === 'function'
    ? new Intl.Segmenter(undefined, { granularity: 'grapheme' })
    : undefined;

/**
 * Ecto's `validate_length` counts graphemes. A plain `.length` in JS counts
 * UTF-16 code units. `Intl.Segmenter` gives us the count Elixir uses.
 */
export const graphemeLength = (value: string): number => {
  // Counting code points instead would be at least the grapheme count and never
  // less, so it would refuse names the server accepts: 60 of "q\u0327" is 60
  // graphemes and 120 code points. Stricter than the server is the one
  // direction this module must never be.
  if (!segmenter) {
    throw new Error('Intl.Segmenter is required to count graphemes');
  }

  return [...segmenter.segment(value)].length;
};

/**
 * Call this rather than `graphemeLength`, so a browser without `Intl.Segmenter`
 * lets the server answer instead of throwing inside a Zod `.refine()`, where a
 * throw escapes `safeParse` as an exception rather than a validation error.
 */
export const exceedsGraphemeCap = (value: string, max: number): boolean =>
  segmenter !== undefined && graphemeLength(value) > max;

export const isNameTooLong = (value: string): boolean =>
  exceedsGraphemeCap(value, NAME_MAX_LENGTH);

export const codepointLength = (value: string): number =>
  Array.from(value).length;

export const isNameTooWideForColumn = (value: string): boolean =>
  codepointLength(value) > NAME_COLUMN_LIMIT;
