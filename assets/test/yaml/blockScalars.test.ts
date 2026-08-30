/**
 * The block scalar fixture, parsed by the npm parser.
 *
 * `test/fixtures/block_scalars.json` is generated from
 * `Lightning.ExportUtils.Scalar.encode_block/2` and checked on the Elixir side
 * against yamerl, which is what the CLI reads specs with. This file is the
 * other half: the browser reads and writes the same specs through `yaml`, and
 * the two parsers do not agree by default. A `|2` block with a trailing
 * whitespace-only line round-trips in yamerl and loses that line here (#4577),
 * and nothing caught it because no Elixir test can run this parser.
 *
 * If this fails after a change to encode_block/2, the fixture and this test
 * disagree with the encoder: regenerate the fixture and check both parsers.
 */
import fs from 'node:fs';
import path from 'node:path';

import { describe, expect, test } from 'vitest';
import YAML from 'yaml';

interface BlockCase {
  label: string;
  value: string;
  document: string;
}

const cases = JSON.parse(
  fs.readFileSync(
    path.join(__dirname, '../../../test/fixtures/block_scalars.json'),
    'utf8'
  )
) as BlockCase[];

describe('block scalars round-trip through the npm parser', () => {
  test('the fixture is not empty', () => {
    expect(cases.length).toBeGreaterThan(20);
  });

  test.each(cases)('$label', ({ value, document }) => {
    const parsed = YAML.parse(document) as { root: { body: string } };
    const got = parsed.root.body;

    // Exact, or with the single trailing newline the reader has always added
    // to a value that did not have one.
    expect(got === value || got === `${value}\n`).toBe(true);
  });
});
