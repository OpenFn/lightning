/**
 * Syntax highlighting for the AI chat's diff blocks.
 *
 * Uses Prism's JavaScript grammar rather than anything hand-rolled. Monaco is
 * already in the bundle but `monaco.editor.colorize` renders with the globally
 * active theme, which is `vs-dark` here (see `js/monaco/index.tsx`), so its
 * tokens would be light-on-light over the diff rows and colouring one chat
 * block would mean re-theming every editor in the app.
 *
 * Prism is tokenized rather than rendered: `Prism.tokenize` returns data, so
 * nothing here touches the DOM or `innerHTML`. The result is regrouped into
 * one token list per line, which is what a diff renders. Tokenizing whole
 * bodies (not individual rows) keeps template literals, block comments and
 * multi-line strings correct where a hunk shows only part of them.
 */

// Must come first: it puts Prism in manual mode so importing Prism does not
// schedule a document-wide highlightAll that rewrites other components' DOM.
import './prismManual';
import Prism from 'prismjs';
import 'prismjs/components/prism-javascript';
import 'prismjs/components/prism-json';

export type TokenKind =
  | 'comment'
  | 'string'
  | 'number'
  | 'keyword'
  | 'function'
  | 'operator'
  | 'property'
  | 'plain';

export interface Token {
  text: string;
  kind: TokenKind;
}

/**
 * Prism's JavaScript grammar emits far more token types than a diff needs to
 * distinguish; anything unmapped renders as plain text.
 */
const KIND_BY_PRISM_TYPE: Record<string, TokenKind> = {
  comment: 'comment',
  prolog: 'comment',
  doctype: 'comment',
  cdata: 'comment',
  string: 'string',
  'template-string': 'string',
  'template-punctuation': 'string',
  char: 'string',
  regex: 'string',
  'attr-value': 'string',
  number: 'number',
  boolean: 'keyword',
  keyword: 'keyword',
  'control-flow': 'keyword',
  module: 'keyword',
  function: 'function',
  'function-variable': 'function',
  'class-name': 'function',
  'maybe-class-name': 'function',
  operator: 'operator',
  punctuation: 'operator',
  property: 'property',
  arrow: 'operator',
};

const kindFor = (type: string, alias?: string | string[]): TokenKind => {
  const aliases = Array.isArray(alias) ? alias : alias ? [alias] : [];
  for (const candidate of [type, ...aliases]) {
    const kind = KIND_BY_PRISM_TYPE[candidate];
    if (kind) return kind;
  }
  return 'plain';
};

/** Flattens Prism's nested token tree into a flat (text, kind) sequence */
const flatten = (
  nodes: Array<string | Prism.Token>,
  inherited: TokenKind,
  out: Token[]
): void => {
  for (const node of nodes) {
    if (typeof node === 'string') {
      out.push({ text: node, kind: inherited });
      continue;
    }

    const kind = kindFor(node.type, node.alias);
    const content = node.content;

    if (typeof content === 'string') {
      out.push({ text: content, kind });
    } else if (Array.isArray(content)) {
      flatten(content, kind, out);
    } else {
      flatten([content], kind, out);
    }
  }
};

/**
 * Splits `source` into one token list per line.
 *
 * A token never spans rows: a multi-line construct is emitted once per line
 * it covers, each part keeping the same kind, so the result renders directly
 * row by row.
 */
const tokenize = (source: string, grammar: string): Token[][] => {
  const flat: Token[] = [];
  flatten(Prism.tokenize(source, Prism.languages[grammar]!), 'plain', flat);

  const lines: Token[][] = [];
  let current: Token[] = [];

  for (const token of flat) {
    const parts = token.text.split('\n');
    parts.forEach((part, index) => {
      if (index > 0) {
        lines.push(current);
        current = [];
      }
      if (part !== '') current.push({ text: part, kind: token.kind });
    });
  }
  lines.push(current);

  return lines;
};

export const tokenizeJs = (source: string): Token[][] =>
  tokenize(source, 'javascript');

export const tokenizeJson = (source: string): Token[][] =>
  tokenize(source, 'json');

/**
 * Token colours, taken from GitHub's Primer light theme rather than
 * approximated with the nearest Tailwind shade.
 *
 * Restrained on purpose: the row tint carries the add/remove signal and has
 * to stay the loudest thing on screen, so most code is near-black and only a
 * few kinds are tinted.
 */
export const TOKEN_CLASS: Record<TokenKind, string> = {
  comment: 'text-[#59636e]',
  string: 'text-[#0a3069]',
  number: 'text-[#0550ae]',
  keyword: 'text-[#cf222e]',
  function: 'text-[#8250df]',
  operator: 'text-[#1f2328]',
  // JSON keys, which Primer tints the same blue it uses for numbers.
  property: 'text-[#0550ae]',
  plain: 'text-[#1f2328]',
};
