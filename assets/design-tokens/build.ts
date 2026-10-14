// Turns the Figma token exports in this folder into Tailwind theme variables.
//
//   cd assets && npm run design-tokens
//
// Writes css/design-tokens.css (committed; test/design-tokens.test.ts fails
// when it is stale) and warns about any token it had to drop. Problems in the
// exports are warned about, never fatal.
//
// Every class carries "ds" so a token class can be told apart from a bare
// Tailwind class and can never land on one: bg-ds-action-primary.

import { readFileSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

// Colour group -> Tailwind theme namespaces it is written into. The group
// itself is dropped from the class name (bg/default -> bg-ds-default), except
// icon, which keeps its name so it can't clash with text/.
const COLOUR_GROUPS: Record<string, { namespaces: string[]; keepName?: true }> =
  {
    bg: { namespaces: ['background-color'] },
    text: { namespaces: ['text-color'] },
    icon: { namespaces: ['text-color', 'fill'], keepName: true },
    border: { namespaces: ['border-color', 'ring-color', 'outline-color'] },
    // Tokens with no group (White, Black, Transparent) suit every colour utility
    '': {
      namespaces: [
        'background-color',
        'text-color',
        'fill',
        'border-color',
        'ring-color',
        'outline-color',
      ],
    },
  };

// Static group -> namespaces. `word` is the fixed word that tells cn() what
// kind of class it is (see js/utils/cn.ts).
const STATIC_GROUPS: Record<string, { namespaces: string[]; word?: string }> = {
  space: { namespaces: ['spacing'] },
  gap: { namespaces: ['gap'] },
  radius: { namespaces: ['radius'] },
  border: {
    namespaces: ['border-width', 'ring-width', 'outline-width'],
    word: 'width',
  },
};

const DIR = `${dirname(fileURLToPath(import.meta.url))}/`;
export const OUTPUT = `${DIR}../css/design-tokens.css`;

type Json = { [key: string]: unknown };
type Token = { path: string[]; value: unknown };

const isObject = (v: unknown): v is Json =>
  typeof v === 'object' && v !== null && !Array.isArray(v);

function flatten(node: Json, path: string[] = []): Token[] {
  if ('$value' in node) return [{ path, value: node['$value'] }];
  return Object.entries(node).flatMap(([key, child]) =>
    key.startsWith('$') || !isObject(child)
      ? []
      : flatten(child, [...path, key])
  );
}

// Follows "{text.default}"-style aliases to a final value within one export
function resolver(tokens: Token[]) {
  const byPath = new Map(tokens.map(t => [t.path.join('.'), t]));
  return function resolve(token: Token, seen: string[] = []): unknown {
    const match =
      typeof token.value === 'string' && /^\{(.+)\}$/.exec(token.value);
    if (!match) return token.value;
    const target = byPath.get(match[1]);
    if (!target || seen.includes(match[1])) return undefined;
    return resolve(target, [...seen, match[1]]);
  };
}

function colourToCss(value: unknown): string | undefined {
  if (!isObject(value) || typeof value['hex'] !== 'string') return undefined;
  const alpha = typeof value['alpha'] === 'number' ? value['alpha'] : 1;
  if (alpha >= 1) return value['hex'].toUpperCase();
  const a = Math.round(alpha * 255)
    .toString(16)
    .padStart(2, '0');
  return `${value['hex']}${a}`.toUpperCase();
}

const round = (n: number, places: number) => Number(n.toFixed(places));
const px = (n: number) => (n === 0 ? '0' : `${round(n, 2)}px`);
const rem = (n: number) => (n === 0 ? '0' : `${round(round(n, 2) / 16, 6)}rem`);

// bg/action/primary/default -> action-primary; bg/default stays default
function tokenName(segments: string[]): string {
  const parts =
    segments.length > 1 && segments.at(-1) === 'default'
      ? segments.slice(0, -1)
      : segments;
  return parts.join('-').toLowerCase().replace(/\s+/g, '-');
}

export function build(light: Json, statics: Json) {
  // Section heading -> lines of `--var: value;`
  const sections = new Map<string, string[]>();
  // --var -> the token path that claimed it, for clash detection
  const owners = new Map<string, string>();
  const warnings: string[] = [];

  function emit(
    section: string,
    variable: string,
    value: string,
    from: string
  ) {
    const owner = owners.get(variable);
    if (owner) {
      warnings.push(
        `--${variable} comes from both ${owner} and ${from}; kept ${owner}`
      );
      return;
    }
    owners.set(variable, from);
    sections.set(section, [
      ...(sections.get(section) ?? []),
      `--${variable}: ${value};`,
    ]);
  }

  // --- Colours ---------------------------------------------------------------

  const lightTokens = flatten(light);
  const resolveLight = resolver(lightTokens);
  // Grouped tokens first, so they win a clash with an ungrouped one
  const colourTokens = [
    ...lightTokens.filter(t => t.path.length > 1),
    ...lightTokens.filter(t => t.path.length === 1),
  ];

  for (const token of colourTokens) {
    const id = token.path.join('/');
    const group = token.path.length > 1 ? token.path[0] : '';
    const rule = COLOUR_GROUPS[group];
    if (!rule) {
      warnings.push(`${id}: no utility for group "${group}/"`);
      continue;
    }
    const value = colourToCss(resolveLight(token));
    if (!value) {
      warnings.push(`${id}: not a colour, or an alias that doesn't resolve`);
      continue;
    }
    const segments = rule.keepName || !group ? token.path : token.path.slice(1);
    const name = tokenName(segments);
    for (const ns of rule.namespaces) {
      emit(ns, `${ns}-ds-${name}`, value, id);
    }
  }

  // --- Space, gap, radius, border widths -------------------------------------

  const staticTokens = flatten(statics);
  const resolveStatic = resolver(staticTokens);

  for (const token of staticTokens) {
    const id = token.path.join('/');
    const [group, ...rest] = token.path;
    if (group === 'Type') continue;
    const rule = STATIC_GROUPS[group];
    const value = resolveStatic(token);
    if (!rule || rest.length === 0) {
      warnings.push(`${id}: no utility for group "${group}/"`);
      continue;
    }
    if (typeof value !== 'number') {
      warnings.push(`${id}: expected a number, got ${JSON.stringify(value)}`);
      continue;
    }
    const name = [rule.word, tokenName(rest)].filter(Boolean).join('-');
    const css = group === 'border' ? px(value) : rem(value);
    for (const ns of rule.namespaces) {
      emit(ns, `${ns}-ds-${name}`, css, id);
    }
  }

  // --- Type: families, weights, text styles ----------------------------------
  // Type/<family>, Type/weight/<weight>, and any group holding a `size` is a
  // text style (Type/weight/body/md -> text-ds-type-body-md).

  const typeTokens = staticTokens.filter(t => t.path[0] === 'Type');

  for (const token of typeTokens) {
    const id = token.path.join('/');
    const value = resolveStatic(token);
    const isStylePart = typeTokens.some(
      t =>
        t.path.length === token.path.length &&
        t.path.at(-1) === 'size' &&
        t.path.slice(0, -1).join('/') === token.path.slice(0, -1).join('/')
    );
    if (isStylePart) continue;

    if (token.path.length === 2 && typeof value === 'string') {
      const name = tokenName(token.path.slice(1));
      // A generic fallback, so a font that isn't loaded doesn't become Times
      const generic = name === 'mono' ? 'monospace' : 'sans-serif';
      emit('font', `font-ds-${name}`, `'${value}', ${generic}`, id);
    } else if (
      token.path[1] === 'weight' &&
      token.path.length === 3 &&
      typeof value === 'number'
    ) {
      const name = `weight-${tokenName(token.path.slice(2))}`;
      emit('font-weight', `font-weight-ds-${name}`, String(value), id);
    } else {
      warnings.push(`${id}: not a font, weight or part of a text style`);
    }
  }

  const styleGroups = typeTokens
    .filter(t => t.path.at(-1) === 'size')
    .map(t => t.path.slice(0, -1));

  for (const groupPath of styleGroups) {
    const id = groupPath.join('/');
    const part = (key: string) => {
      const t = typeTokens.find(t => t.path.join('/') === `${id}/${key}`);
      return t ? resolveStatic(t) : undefined;
    };
    const name = `type-${tokenName(groupPath.filter(s => s !== 'Type' && s !== 'weight'))}`;
    const variable = `text-ds-${name}`;
    const size = part('size');
    const lineHeight = part('line-height');
    const letterSpacing = part('letter-spacing');
    const weight = part('weight');

    if (typeof size !== 'number') {
      warnings.push(`${id}: size is not a number`);
      continue;
    }
    emit('text', variable, rem(size), id);
    if (typeof lineHeight === 'number') {
      emit('text', `${variable}--line-height`, rem(lineHeight), id);
    }
    if (typeof letterSpacing === 'number') {
      emit('text', `${variable}--letter-spacing`, rem(letterSpacing), id);
    }
    if (typeof weight === 'number') {
      emit('text', `${variable}--font-weight`, String(weight), id);
    }
    const missing = ['line-height', 'letter-spacing', 'weight'].filter(
      k => part(k) === undefined
    );
    if (missing.length) {
      warnings.push(`${id}: missing or unresolved ${missing.join(', ')}`);
    }
  }

  const css = [
    '/* Generated by assets/design-tokens/build.ts from the Figma exports beside it.',
    ' * Do not edit: change the exports or the script, then run `npm run design-tokens`. */',
    '',
    '@theme {',
    ...[...sections].flatMap(([section, lines], i) => [
      ...(i ? [''] : []),
      `  /* ${section} */`,
      ...lines.map(l => `  ${l}`),
    ]),
    '}',
    '',
  ].join('\n');

  return { css, warnings };
}

export function readExports() {
  const read = (file: string) =>
    JSON.parse(readFileSync(`${DIR}${file}`, 'utf8')) as Json;
  return {
    light: read('Light.tokens.json'),
    statics: read('Static.tokens.json'),
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const { light, statics } = readExports();
  const { css, warnings } = build(light, statics);
  writeFileSync(OUTPUT, css);
  for (const w of warnings) console.warn(w);
  console.log(`Wrote ${OUTPUT}`);
}
