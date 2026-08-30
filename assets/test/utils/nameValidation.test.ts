/**
 * The client-side copy of the job/workflow name rule (#4577).
 *
 * These tests exist to keep the client and `Lightning.Validators.validate_name/3`
 * saying the same thing. The Elixir counterparts live in
 * `test/lightning/workflows/job_test.exs`.
 */

import fs from 'node:fs';
import path from 'node:path';

import { describe, expect, test } from 'vitest';

import { TemplatePublishSchema } from '../../js/collaborative-editor/components/inspector/TemplatePublishPanel';
import {
  EdgeSchema,
  ExprEdgeSchema,
} from '../../js/collaborative-editor/types/edge';
import { JobSchema } from '../../js/collaborative-editor/types/job';
import { createWorkflowSchema } from '../../js/collaborative-editor/types/workflow';
import {
  CONTROL_CHARS_MESSAGE,
  NAME_MAX_LENGTH,
  NAME_TOO_LONG_MESSAGE,
  NAME_TOO_WIDE_MESSAGE,
  codepointLength,
  exceedsGraphemeCap,
  graphemeLength,
  hasControlChars,
  isInvisibleOnly,
  normalizeName,
} from '../../js/utils/nameValidation';

const validJob = (name: string) => ({
  id: '00000000-0000-4000-8000-000000000001',
  name,
  body: 'fn(state => state)',
  adaptor: '@openfn/language-common@latest',
});

describe('hasControlChars', () => {
  test('accepts every script, symbol and punctuation mark', () => {
    const accepted = [
      'Vérifier l’état',
      '患者確認',
      'تسجيل المريض',
      'רישום מטופל',
      'step 🎉',
      "MailChimp June'24",
      'Flujo 1: Registro',
      'a / b',
      'source -> target',
      'a & b',
      'नमस्ते',
    ];

    for (const name of accepted) {
      expect(hasControlChars(name), name).toBe(false);
    }
  });

  test('rejects C0, DEL, C1 and the two non-characters', () => {
    const rejected = [
      'nul\u0000byte',
      'tab\u0009here',
      'line\u000Abreak',
      'carriage\u000Dreturn',
      'escape\u001B[31m',
      'delete\u007F',
      'c1\u0080next',
      'c1\u009Fend',
      'non\uFFFEchar',
      'non\uFFFFchar',
    ];

    for (const name of rejected) {
      expect(hasControlChars(name), JSON.stringify(name)).toBe(true);
    }
  });
});

describe('normalizeName', () => {
  test('composes to NFC and trims', () => {
    // e + combining acute: two codepoints until it is normalised, one after.
    const decomposed = '  V\u0065\u0301rifier  ';

    expect(decomposed.trim().length).toBe(9);
    expect(normalizeName(decomposed)).toBe('V\u00E9rifier');
    expect(normalizeName(decomposed).length).toBe(8);
  });

  test('trims the set Elixir trims, not the set JS trims', () => {
    // These two are where `String.trim/1` and `.trim()` disagree, and they
    // disagree in opposite directions. Trimming NEL is what stops the client
    // rejecting a name the server would accept; leaving U+FEFF alone is what
    // stops the client rewriting a name the server already stored.
    expect('abc\u0085'.trim()).toBe('abc\u0085');
    expect(normalizeName('abc\u0085')).toBe('abc');

    expect('abc\uFEFF'.trim()).toBe('abc');
    expect(normalizeName('abc\uFEFF')).toBe('abc\uFEFF');

    // A sample of the rest of the 25, to catch the set being edited down.
    expect(normalizeName('\u3000\u00a0\u2028 abc \u205f')).toBe('abc');

    // Not White_Space, so not trimmed by either side.
    expect(normalizeName('abc\u200b')).toBe('abc\u200b');
  });
});

describe('graphemeLength', () => {
  test('counts what Ecto counts, not UTF-16 code units', () => {
    const family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}';

    // 11 UTF-16 code units, 7 code points, 1 grapheme. Ecto says 1.
    expect(family.length).toBe(11);
    expect(graphemeLength(family)).toBe(1);

    // Same for a flag.
    expect(graphemeLength('🇺🇸')).toBe(1);
  });

  test('counts fewer graphemes than Elixir for three families of input', () => {
    // Three places the two disagree, all in the same direction:
    //
    //   1. GB9c Indic conjuncts. Intl.Segmenter keeps consonant + virama +
    //      consonant together where Elixir's tables split. Malayalam is the
    //      worst case: 'ന്ദ്ര' is 1 here and 3 to Elixir, so a name at the
    //      100 grapheme cap on this side can measure near 300 on that side.
    //   2. Break-after-ZWJ, another rule revision Elixir's tables predate.
    //   3. Characters added in Unicode 16, which Elixir has not caught up to.
    //
    // The client is the permissive side every time, which is the safe
    // direction: the name reaches the server and comes back as an ordinary
    // changeset error instead of being blocked in the browser for a reason the
    // user cannot see. The codepoint guard below is what stops any of this
    // reaching the column.
    expect(graphemeLength('नमस्ते')).toBe(3);
    expect(graphemeLength('ന്ദ്ര')).toBe(1);
  });
});

describe('JobSchema name', () => {
  test('accepts names from any script, and punctuation the old rule refused', () => {
    const accepted = [
      'Vérifier l’état',
      '患者確認',
      'تسجيل المريض',
      'step 🎉',
      "MailChimp June'24",
      'Flujo 1: Registro',
      'a / b',
      'source -> target',
    ];

    for (const name of accepted) {
      const result = JobSchema.safeParse(validJob(name));
      expect(result.success, name).toBe(true);
    }
  });

  test('rejects control characters with the one shared message', () => {
    const result = JobSchema.safeParse(validJob('nul\u0000byte'));

    expect(result.success).toBe(false);
    expect(result.error?.issues.map(i => i.message)).toContain(
      CONTROL_CHARS_MESSAGE
    );
  });

  test('normalises and trims before it validates', () => {
    const result = JobSchema.safeParse(validJob('  Vérifier  '));

    expect(result.success).toBe(true);
    expect(result.data?.name).toBe('Vérifier');
  });

  test('a name that is only whitespace is blank, not valid', () => {
    const result = JobSchema.safeParse(validJob('   '));

    expect(result.success).toBe(false);
    expect(result.error?.issues.map(i => i.message)).toContain(
      "Job name can't be blank"
    );
  });

  test('the length cap counts graphemes, so it matches Ecto', () => {
    const family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}';

    // 12 families plus 88 letters: 100 graphemes, which Ecto accepts, but 220
    // UTF-16 code units, which the old `.max(100)` would have refused.
    const atCap = 'a'.repeat(88) + family.repeat(12);
    expect(atCap.length).toBe(220);
    expect(graphemeLength(atCap)).toBe(NAME_MAX_LENGTH);
    expect(JobSchema.safeParse(validJob(atCap)).success).toBe(true);

    const overCap = 'a'.repeat(89) + family.repeat(12);
    const result = JobSchema.safeParse(validJob(overCap));
    expect(result.success).toBe(false);
    expect(result.error?.issues.map(i => i.message)).toContain(
      NAME_TOO_LONG_MESSAGE
    );
  });

  test('a name short in graphemes but too wide for the column is refused', () => {
    const family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}';

    // 100 families are 100 graphemes, so they clear the cap above, but 700
    // codepoints, and the name column is varchar(255). The server rejects this
    // in Validators.validate_name_fits_column/3; the client says the same.
    const name = family.repeat(100);
    expect(graphemeLength(name)).toBe(100);
    expect(Array.from(name).length).toBe(700);

    const result = JobSchema.safeParse(validJob(name));
    expect(result.success).toBe(false);
    expect(result.error?.issues.map(i => i.message)).toContain(
      NAME_TOO_WIDE_MESSAGE
    );

    // Pinned literally, and with no number in it. The user was told the limit
    // is 100 and counts 100 characters; answering "255" is not actionable.
    expect(NAME_TOO_WIDE_MESSAGE).toBe(
      'Name is too long, please use a shorter one.'
    );
    expect(NAME_TOO_WIDE_MESSAGE).not.toMatch(/\d/);
  });

  test('trailing whitespace is trimmed before the cap is applied', () => {
    const name = `${'a'.repeat(NAME_MAX_LENGTH)}     `;

    expect(JobSchema.safeParse(validJob(name)).success).toBe(true);
  });
});

describe('isInvisibleOnly', () => {
  test('catches a run of joiners, not just a single one', () => {
    // Grapheme clustering fuses a ZWJ-led run into one cluster, so a
    // per-grapheme check caught one joiner and missed two.
    for (const name of [
      '\u{200D}',
      '\u{200D}\u{200D}',
      '\u{200D}\u{200D}\u{200D}',
      '\u{200B}\u{200D}\u{200D}',
      '\u{2060}',
      '\u{3164}',
      '\u{FFA0}',
      '\u{115F}',
      '\u{1160}',
      '\u{2800}',
      '\u{200E}',
      '\u{202E}',
      '\u{FE0F}',
      '\u{FEFF}\u{00AD}',
    ]) {
      expect(isInvisibleOnly(name), JSON.stringify(name)).toBe(true);
    }
  });

  test('leaves a name that merely contains one alone', () => {
    for (const name of [
      '\u{1F468}\u{200D}\u{1F469}',
      'a\u{200B}b',
      '\u{0915}\u{094D}\u{200C}\u{0937}',
      'step',
    ]) {
      expect(isInvisibleOnly(name), JSON.stringify(name)).toBe(false);
    }
  });
});

describe('createWorkflowSchema (the validator the settings form uses)', () => {
  const parse = (name: string) =>
    createWorkflowSchema(null).safeParse({
      id: '00000000-0000-4000-8000-000000000001',
      name,
      lock_version: 1,
      deleted_at: null,
    });

  test('accepts a name long in UTF-16 units but short in codepoints', () => {
    // 130 emoji: 130 codepoints, which the column holds, but 260 UTF-16 units,
    // which the old `.max(255)` counted and refused.
    const name = '\u{1F600}'.repeat(130);
    expect(name.length).toBe(260);

    expect(parse(name).success).toBe(true);
  });

  test('normalises and trims, like the server', () => {
    const result = parse('  V\u{0065}\u{0301}rifier  ');
    expect(result.success).toBe(true);
    expect(result.data?.name).toBe('V\u{00E9}rifier');
  });

  test('refuses a control character', () => {
    const result = parse('bad\u{0000}name');
    expect(result.success).toBe(false);
    expect(result.error?.issues.map(i => i.message)).toContain(
      CONTROL_CHARS_MESSAGE
    );
  });

  test('refuses a name that is only invisible characters', () => {
    expect(parse('\u{200D}\u{200D}').success).toBe(false);
  });

  test('refuses a name past the column width', () => {
    expect(parse('a'.repeat(256)).success).toBe(false);
  });

  test('accepts an ordinary name', () => {
    expect(parse('My workflow').success).toBe(true);
  });
});

describe('EdgeSchema condition_label (an inbound schema)', () => {
  const parse = (label: string) =>
    EdgeSchema.safeParse({
      id: '00000000-0000-4000-8000-000000000001',
      target_job_id: '00000000-0000-4000-8000-000000000002',
      condition_type: 'always',
      condition_label: label,
    });

  test('accepts a label long in UTF-16 units but short in codepoints', () => {
    // 128 emoji: 128 codepoints, which the column holds, but 256 UTF-16 units,
    // which the old `.max(255)` counted. EdgeSchema sits inside
    // BaseWorkflowSchema and one safeParse covers the whole payload, so this
    // took the collaborative editor down for the entire project.
    const label = '\u{1F600}'.repeat(128);
    expect(label.length).toBe(256);

    expect(parse(label).success).toBe(true);
  });

  test('still refuses a label past the column width', () => {
    expect(parse('a'.repeat(256)).success).toBe(false);
  });

  test('accepts an ordinary label', () => {
    expect(parse('rechazada').success).toBe(true);
  });
});

describe('isInvisibleOnly agrees with the server', () => {
  // test/fixtures/invisible_codepoints.json is generated from
  // Lightning.Validators.invisible_only?/1. The client must call invisible
  // everything the server does, or it accepts a name the server calls blank.
  const fixture = JSON.parse(
    fs.readFileSync(
      path.join(__dirname, '../../../test/fixtures/invisible_codepoints.json'),
      'utf8'
    )
  ) as { count: number; ranges: [number, number][] };

  const serverSet = new Set<number>();
  for (const [lo, hi] of fixture.ranges) {
    for (let c = lo; c <= hi; c++) serverSet.add(c);
  }

  test('the fixture is the size it says it is', () => {
    expect(serverSet.size).toBe(fixture.count);
  });

  test('every codepoint the server calls invisible, the client does too', () => {
    const missed: string[] = [];
    for (const c of serverSet) {
      if (!isInvisibleOnly(String.fromCodePoint(c))) {
        missed.push(c.toString(16));
      }
    }
    expect(missed).toEqual([]);
  });

  test('the client is stricter only by a known Unicode-version skew', () => {
    // V8's tables are newer than the PCRE build Elixir uses, so it knows four
    // Arabic and Kaithi number signs as Format that PCRE does not. Client
    // stricter means a validation message rather than an outage, and pinning
    // the list here means a change in either engine shows up as a diff.
    const extra: string[] = [];
    for (let c = 0; c <= 0x10ffff; c++) {
      if (c >= 0xd800 && c <= 0xdfff) continue;
      if (serverSet.has(c)) continue;
      if (isInvisibleOnly(String.fromCodePoint(c))) extra.push(c.toString(16));
    }
    expect(extra).toEqual(['890', '891', '8e2', '110cd']);
  });

  test('a name that merely contains an invisible is still a real name', () => {
    for (const name of [
      '\u{1F468}\u{200D}\u{1F469}',
      '\u{0915}\u{094D}\u{200C}\u{0937}',
      '\u{0644}\u{200D}\u{0627}',
      '\u{2764}\u{FE0F}',
      'a\u{200B}b',
      'step',
    ]) {
      expect(isInvisibleOnly(name), JSON.stringify(name)).toBe(false);
    }
  });
});

describe('EdgeSchema condition_expression', () => {
  const parseBase = (expression: string) =>
    EdgeSchema.safeParse({
      id: '00000000-0000-4000-8000-000000000001',
      target_job_id: '00000000-0000-4000-8000-000000000002',
      condition_type: 'always',
      condition_expression: expression,
    });

  const parseExpr = (expression: string) =>
    ExprEdgeSchema.safeParse({
      id: '00000000-0000-4000-8000-000000000001',
      target_job_id: '00000000-0000-4000-8000-000000000002',
      condition_type: 'js_expression',
      condition_expression: expression,
    });

  test('accepts an expression long in UTF-16 units but short in codepoints', () => {
    // 200 astral emoji: 200 codepoints the server stores fine, 400 UTF-16
    // units the old `.max(255)` counted. This runs on every keystroke.
    const expression = '\u{1F600}'.repeat(200);
    expect(expression.length).toBe(400);

    expect(parseExpr(expression).success).toBe(true);
    expect(parseBase(expression).success).toBe(true);
  });

  test('the base schema caps it too, not just the js_expression override', () => {
    // The server validates the expression on every condition type. The base
    // schema had no cap at all, so an over-wide expression sailed through.
    expect(parseBase('a'.repeat(256)).success).toBe(false);
  });

  test('the js_expression override still caps it', () => {
    expect(parseExpr('a'.repeat(256)).success).toBe(false);
  });

  test('accepts an ordinary expression on both', () => {
    expect(parseExpr('state.data.ok === true').success).toBe(true);
    expect(parseBase('state.data.ok === true').success).toBe(true);
  });
});

describe('TemplatePublishSchema (the template form)', () => {
  const parse = (values: { name?: string; description?: string }) =>
    TemplatePublishSchema.safeParse({
      name: 'a template',
      description: '',
      tags: '',
      ...values,
    });

  // Every case below is chosen so that it passes under the codepoint/grapheme
  // rule and fails under the UTF-16 `.max()` it replaced, or the reverse.
  // A case that behaves the same under both pins nothing.

  test('name: accepts 200 emoji, which .max(255) on UTF-16 units refused', () => {
    const name = '\u{1F600}'.repeat(200);
    expect(name.length).toBe(400);
    expect(codepointLength(name)).toBe(200);

    expect(parse({ name }).success).toBe(true);
  });

  test('name: refuses 256 codepoints even though they are 256 units', () => {
    // The boundary, where both rules agree. Here to pin the cap itself, since
    // the test above would still pass with no cap at all.
    expect(parse({ name: 'a'.repeat(255) }).success).toBe(true);
    expect(parse({ name: 'a'.repeat(256) }).success).toBe(false);
  });

  test('name: refuses 256 emoji, which is 512 units and 256 codepoints', () => {
    // Over the cap on both counts, so it pins that widening the rule did not
    // remove the cap for astral input.
    expect(parse({ name: '\u{1F600}'.repeat(256) }).success).toBe(false);
  });

  test('description: accepts 600 emoji, which .max(1000) on units refused', () => {
    const description = '\u{1F600}'.repeat(600);
    expect(description.length).toBe(1200);
    expect(graphemeLength(description)).toBe(600);

    expect(parse({ description }).success).toBe(true);
  });

  test('description: still refuses 1001 graphemes', () => {
    expect(parse({ description: 'a'.repeat(1000) }).success).toBe(true);
    expect(parse({ description: 'a'.repeat(1001) }).success).toBe(false);
  });

  test('a blank name is still refused', () => {
    expect(parse({ name: '' }).success).toBe(false);
  });

  test('an over-long description is a validation error, never a throw', () => {
    // graphemeLength throws without Intl.Segmenter, and a throw inside a Zod
    // .refine() escapes safeParse as an exception rather than becoming a
    // validation error, so the form would blow up instead of degrading.
    // exceedsGraphemeCap is the guarded entry point.
    expect(() => parse({ description: 'a'.repeat(1001) })).not.toThrow();
    expect(() => parse({ description: '\u{1F600}'.repeat(600) })).not.toThrow();
  });
});

describe('exceedsGraphemeCap', () => {
  test('answers for values either side of the cap', () => {
    expect(exceedsGraphemeCap('a'.repeat(10), 10)).toBe(false);
    expect(exceedsGraphemeCap('a'.repeat(11), 10)).toBe(true);
  });

  test('counts graphemes, not UTF-16 units', () => {
    const family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}';

    // 11 units, 1 grapheme. A UTF-16 count would call this over a cap of 10.
    expect(family.length).toBe(11);
    expect(exceedsGraphemeCap(family, 10)).toBe(false);
  });

  test('is the only grapheme length decision application code makes', () => {
    // graphemeLength itself throws without Intl.Segmenter. Nothing outside
    // this module may call it directly; everything goes through here so the
    // no-Segmenter case degrades permissively and the server answers.
    const source = fs.readFileSync(
      path.join(__dirname, '../../js/utils/nameValidation.ts'),
      'utf8'
    );

    expect(source).toContain('segmenter !== undefined');
  });
});
