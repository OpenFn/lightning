/**
 * The one rule for job and workflow names, shared by every place on the client
 * that checks one.
 *
 * Anything except a control character. U+2028 and U+2029 are in the rejected
 * set because they are line breaks in YAML 1.1, so a name holding one makes a
 * spec that some parsers reject and others read differently.
 *
 * This mirrors `Lightning.Validators.validate_name/3` in
 * `lib/lightning/utils/validators.ex`, so the client refuses exactly what the
 * server would refuse and nothing more. Change one and change the other.
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
 * still not fit: 100 ZWJ family emoji are 100 graphemes but 700 codepoints.
 * `Lightning.Validators.validate_name_fits_column/3` is the server half.
 */
export const NAME_COLUMN_LIMIT = 255;

/**
 * Deliberately quotes no number. The limit the user was shown is the grapheme
 * cap above; telling them 255 right after telling them 100 reads as a bug.
 * Mirrors the server message in `Lightning.Workflows.Job`.
 */
export const NAME_TOO_WIDE_MESSAGE =
  'Name is too long, please use a shorter one.';

/**
 * The 25 Unicode White_Space characters, which is what Elixir's `String.trim/1`
 * strips. JS `.trim()` differs in both directions: it leaves U+0085, which
 * Elixir strips, and eats U+FEFF, which Elixir keeps.
 */
const TRIM_CHARS =
  '\u0009\u000a\u000b\u000c\u000d\u0020\u0085\u00a0\u1680\u2000\u2001' +
  '\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029' +
  '\u202f\u205f\u3000';

const TRIM_REGEX = new RegExp(`^[${TRIM_CHARS}]+|[${TRIM_CHARS}]+$`, 'gu');

/**
 * NFC, then trim. The server normalises before it validates, so anything that
 * measures or checks a name on the client has to normalise first too,
 * otherwise the two disagree about length and about what counts as blank.
 */
export const normalizeName = (value: string): string =>
  value.normalize('NFC').replace(TRIM_REGEX, '');

export const hasControlChars = (value: string): boolean =>
  CONTROL_CHARS_REGEX.test(value);

/**
 * True only when the name is nothing but characters that draw nothing.
 *
 * A property test rather than a list, and the same rule as
 * `@invisible_regex` in lib/lightning/utils/validators.ex. JS exposes the
 * `Default_Ignorable_Code_Point` binary property directly; the format category
 * is unioned in for the characters that are Cf without being
 * default-ignorable, and U+2800 because the Braille blank is neither but still
 * draws nothing.
 *
 * `test/fixtures/invisible_codepoints.json` is generated from the server's
 * predicate and asserted against this one, so the two cannot drift.
 *
 * A name that merely contains one of these is fine: a joiner is how an emoji
 * sequence, a Devanagari conjunct and an Arabic ligature are written.
 */
const INVISIBLE_ONLY_REGEX =
  /^[\p{Default_Ignorable_Code_Point}\p{General_Category=Format}\u2800]+$/u;

export const isInvisibleOnly = (value: string): boolean =>
  value !== '' && INVISIBLE_ONLY_REGEX.test(value);

export const NAME_BLANK_MESSAGE = "Name can't be blank.";

/**
 * `Intl.Segmenter` is not declared in the `es2020` lib this project compiles
 * against, hence the local declaration rather than a lib bump.
 */
interface GraphemeSegmenter {
  segment(input: string): Iterable<{ segment: string }>;
}

interface SegmenterConstructor {
  new (
    locales?: string | string[],
    options?: { granularity: 'grapheme' | 'word' | 'sentence' }
  ): GraphemeSegmenter;
}

const SegmenterCtor = (
  Intl as unknown as {
    Segmenter?: SegmenterConstructor | undefined;
  }
).Segmenter;

const segmenter = SegmenterCtor
  ? new SegmenterCtor(undefined, { granularity: 'grapheme' })
  : undefined;

/**
 * Ecto's `validate_length` counts graphemes. A plain `.length` in JS counts
 * UTF-16 code units, so a family emoji is 1 to Elixir and 11 to JS, and the
 * two ends of the wire disagree about a 100 character cap. `Intl.Segmenter`
 * gives us the count Elixir uses.
 */
export const graphemeLength = (value: string): number => {
  // No fallback on purpose. Counting code points instead would be at least the
  // grapheme count and never less, so it would refuse names the server accepts
  // -- 60 of "q\u0327" is 60 graphemes and 120 code points. Stricter than the
  // server is the one direction this module must never be.
  if (!segmenter) {
    throw new Error('Intl.Segmenter is required to count graphemes');
  }

  return Array.from(segmenter.segment(value)).length;
};

/**
 * Call this rather than `graphemeLength`, which throws without a Segmenter, and
 * a throw inside a Zod `.refine()` escapes `safeParse` as an exception instead
 * of becoming a validation error. Without a Segmenter this says nothing and
 * lets the server answer.
 */
export const exceedsGraphemeCap = (value: string, max: number): boolean =>
  segmenter !== undefined && graphemeLength(value) > max;

export const isNameTooLong = (value: string): boolean =>
  exceedsGraphemeCap(value, NAME_MAX_LENGTH);

export const codepointLength = (value: string): number =>
  Array.from(value).length;

export const isNameTooWideForColumn = (value: string): boolean =>
  codepointLength(value) > NAME_COLUMN_LIMIT;
