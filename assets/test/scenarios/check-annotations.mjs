// Drift check between annotations/ and the scenario specs.
//   node test/scenarios/check-annotations.mjs [--citations]
// (a) every annotation scenario id (views, flows, shared) has a test; (b) every test id exists in its
// annotation; (c) with --citations, every `file.ext:line` citation points at a real line.
// Exits 1 listing each problem. Status lives in the specs only.
import { readdirSync, readFileSync, existsSync, statSync } from 'node:fs';
import { join } from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const here = fileURLToPath(new URL('.', import.meta.url));
const root = join(here, '../../..');
const ann = join(root, 'annotations');
const specs = readdirSync(here).filter(f => f.endsWith('.spec.ts'));
const read = p => readFileSync(p, 'utf8');
const idsOf = md => new Set([...md.matchAll(/^\s*@(S\d+)\b/gm)].map(m => m[1]));
const names = dir =>
  readdirSync(join(ann, dir)).map(f => f.replace(/\.md$/, ''));

const problems = { a: [], b: [], c: [] };

// Test ids found in the specs: view tests are titled '@S01' (or `@S01 ${x}`);
// shared tests are 'shared-x@S01 on page', or `shared-x@${id}` in a loop whose
// ids are the quoted 'Sxx' strings between the nearest `for (` and the test.
const viewTests = {}; // view -> Set(id)
const sharedTests = {}; // shared-x -> Map(id -> spec)
for (const f of specs) {
  const src = read(join(here, f));
  const view = f.replace(/\.spec\.ts$/, '');
  for (const m of src.matchAll(/\btest(?:\.\w+)?\(\s*[`'"]@(S\d+)/g))
    (viewTests[view] ??= new Set()).add(m[1]);
  // direct calls: `import * as alias from './shared/x'` then `alias.S01(`
  for (const im of src.matchAll(
    /import \* as (\w+) from '\.\/shared\/([\w-]+)'/g
  ))
    for (const c of src.matchAll(new RegExp(`\\b${im[1]}\\.(S\\d+)\\(`, 'g')))
      (sharedTests['shared-' + im[2]] ??= new Map()).set(c[1], f);
  // a page test that already covers a shared scenario: `// covers shared-x@S01 with @S05`
  for (const m of src.matchAll(
    /\/\/ covers (shared-[a-z-]+)@(S\d+) with @S\d+/g
  ))
    (sharedTests[m[1]] ??= new Map()).set(m[2], f);
  for (const m of src.matchAll(/[`'"](shared-[a-z-]+)@(S\d+|\$\{\w+\})/g)) {
    const map = (sharedTests[m[1]] ??= new Map());
    if (m[2][0] === 'S') map.set(m[2], f);
    else if (/=>\s*$/.test(src.slice(Math.max(0, m.index - 40), m.index))) {
      // helper `const name = (id) => `shared-x@${id}...``: ids come from the
      // name('S01') calls and loop headers up to the next helper definition.
      const rest = src.slice(m.index + 10);
      const end = rest.search(/const name = /);
      const region = end < 0 ? rest : rest.slice(0, end);
      for (const c of region.matchAll(/\bname\(\s*'(S\d+)'/g)) map.set(c[1], f);
      for (const c of region.matchAll(
        /for \([^)]*?\bof\s*\[([^\]]*)\][^)]*\)\s*test\(\s*name\(/g
      ))
        for (const id of c[1].matchAll(/'(S\d+)'/g)) map.set(id[1], f);
    } else {
      // loop: the quoted ids in the nearest `for (... of [...])` header
      const start = src.lastIndexOf('for (', m.index);
      const head = src
        .slice(start, m.index)
        .match(/^for \([^)]*?\bof\s*([\s\S]*?)\)(?=\s*(?:\{\s*)?test\()/);
      if (head && !src.slice(start + head[0].length, m.index).includes(');'))
        for (const id of head[1].matchAll(/'(S\d+)'/g)) map.set(id[1], f);
    }
  }
}

for (const dir of ['views', 'flows', 'shared']) {
  for (const name of names(dir)) {
    const want = idsOf(read(join(ann, dir, name + '.md')));
    const have =
      dir === 'shared'
        ? new Set(sharedTests[name]?.keys() ?? [])
        : (viewTests[name] ?? new Set());
    for (const id of want)
      if (!have.has(id)) problems.a.push(`${name}@${id}: no test`);
    for (const id of have)
      if (!want.has(id))
        problems.b.push(`${name}@${id}: test names an id the annotation lacks`);
  }
}
for (const x of Object.keys(sharedTests))
  if (!existsSync(join(ann, 'shared', x + '.md')))
    problems.b.push(`${x}: tests name a shared annotation that does not exist`);
for (const v of Object.keys(viewTests))
  if (!['views', 'flows'].some(d => existsSync(join(ann, d, v + '.md'))))
    problems.b.push(`${v}.spec.ts: no matching annotation`);

// (c) citations
if (process.argv.includes('--citations')) {
  const walk = (d, out = []) => {
    for (const e of readdirSync(d, { withFileTypes: true })) {
      if (e.name === 'node_modules') continue;
      const p = join(d, e.name);
      if (e.isDirectory()) walk(p, out);
      else out.push(p);
    }
    return out;
  };
  const all = ['lib', 'assets/js', 'test'].flatMap(d => walk(join(root, d)));
  const lines = new Map();
  const lineCount = p =>
    lines.get(p) ??
    (lines.set(
      p,
      read(p).split('\n').length - (read(p).endsWith('\n') ? 1 : 0)
    ),
    lines.get(p));
  const EXT = 'exs?|heex|eex|tsx?|jsx?|css|json|sql';
  const cite = new RegExp(
    `([\\w./@-]+\\.(?:${EXT})):(\\d+)(?:-(\\d+))?|(?:\`|, |; | and )(?::(\\d+)(?:-(\\d+))?)`,
    'g'
  );
  for (const dir of ['views', 'flows', 'shared'])
    for (const name of names(dir)) {
      read(join(ann, dir, name + '.md'))
        .split('\n')
        .forEach((line, i) => {
          let last = null;
          for (const m of line.matchAll(cite)) {
            const file = m[1] ?? last;
            if (!file) continue;
            last = file;
            const n = Math.max(+(m[3] ?? m[5] ?? 0), +(m[2] ?? m[4]));
            const where = `${name}.md:${i + 1}: ${file}:${m[2] ?? m[4]}${m[3] || m[5] ? '-' + (m[3] ?? m[5]) : ''}`;
            let hits =
              existsSync(join(root, file)) &&
              statSync(join(root, file)).isFile()
                ? [join(root, file)]
                : [];
            if (!hits.length) hits = all.filter(p => p.endsWith('/' + file));
            if (hits.length !== 1)
              problems.c.push(
                `${where}: ${hits.length ? 'ambiguous (' + hits.length + ' matches)' : 'unresolved'}`
              );
            else if (lineCount(hits[0]) < n)
              problems.c.push(`${where}: file has ${lineCount(hits[0])} lines`);
          }
        });
    }
}

const title = {
  a: 'annotation id without a test',
  b: 'test id not in annotation',
  c: 'bad citation',
};
let total = 0;
for (const k of 'abc') {
  if (k === 'c' && !process.argv.includes('--citations')) continue;
  console.log(`\n(${k}) ${title[k]}: ${problems[k].length}`);
  for (const p of problems[k]) console.log('  ' + p);
  total += problems[k].length;
}
process.exit(total ? 1 : 0);
