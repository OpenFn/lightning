/**
 * highlightJs - Tests for the diff-display JavaScript tokenizer
 *
 * The tokenizer is display-only, so these check that it never loses or
 * reorders source text, and that multi-line constructs keep their kind
 * across row boundaries (the case a per-line tokenizer gets wrong).
 */

import { describe, it, expect } from 'vitest';

import { tokenizeJs } from '../../../js/collaborative-editor/utils/highlightJs';

/** Text of one tokenized line, as it will render */
const render = (lines: ReturnType<typeof tokenizeJs>, index: number): string =>
  (lines[index] ?? []).map(token => token.text).join('');

const kinds = (lines: ReturnType<typeof tokenizeJs>, index: number) =>
  (lines[index] ?? []).map(token => token.kind);

describe('tokenizeJs', () => {
  it('preserves the source exactly, line by line', () => {
    const source = [
      'const x = fn(state => state.data);',
      '// a comment',
      'return { ...state, x };',
    ].join('\n');

    const lines = tokenizeJs(source);

    expect(lines).toHaveLength(3);
    source.split('\n').forEach((line, index) => {
      expect(render(lines, index)).toBe(line);
    });
  });

  it('keeps a template literal a string across the lines it spans', () => {
    const source = [
      'const msg = `line one',
      'line two ${x}',
      'line three`;',
    ].join('\n');

    const lines = tokenizeJs(source);

    // The middle row is inside the template, so its literal text is string —
    // a per-line tokenizer would see bare words here and colour them as code.
    // The interpolation is broken out and tokenized as the code it is.
    expect(render(lines, 1)).toBe('line two ${x}');
    expect(lines[1]?.[0]).toEqual({ text: 'line two ', kind: 'string' });
    expect(kinds(lines, 1)).toContain('operator');
    expect(lines[2]?.[0]?.kind).toBe('string');
  });

  it('keeps a block comment a comment across rows', () => {
    const source = ['/* first', 'second', 'third */ const x = 1;'].join('\n');

    const lines = tokenizeJs(source);

    expect(kinds(lines, 1)).toEqual(['comment']);
    expect(lines[2]?.[0]?.kind).toBe('comment');
    expect(render(lines, 2)).toBe('third */ const x = 1;');
  });

  it('marks keywords, strings, numbers and comments', () => {
    const lines = tokenizeJs("const n = 42; // note 'quoted'");
    const byKind = (kind: string) =>
      (lines[0] ?? []).filter(t => t.kind === kind).map(t => t.text);

    expect(byKind('keyword')).toContain('const');
    expect(byKind('number')).toContain('42');
    expect(byKind('comment')).toEqual(["// note 'quoted'"]);
  });

  it('does not treat an apostrophe in a comment as opening a string', () => {
    const source = ["// don't break here", 'const x = 1;'].join('\n');

    const lines = tokenizeJs(source);

    expect(kinds(lines, 0)).toEqual(['comment']);
    expect(lines[1]?.some(t => t.kind === 'keyword')).toBe(true);
  });

  it('stops an unterminated quote at the end of its line', () => {
    const source = ["const broken = 'oops", 'const after = 1;'].join('\n');

    const lines = tokenizeJs(source);

    // Without this guard a stray quote would swallow the rest of the body.
    expect(render(lines, 1)).toBe('const after = 1;');
    expect(lines[1]?.some(t => t.kind === 'keyword')).toBe(true);
  });

  it('handles an escaped quote inside a string', () => {
    const lines = tokenizeJs("const s = 'it\\'s fine'; const y = 2;");

    expect(render(lines, 0)).toBe("const s = 'it\\'s fine'; const y = 2;");
    expect((lines[0] ?? []).filter(t => t.kind === 'string')).toHaveLength(1);
  });

  it('returns one empty row for empty input', () => {
    expect(tokenizeJs('')).toEqual([[]]);
  });
});
