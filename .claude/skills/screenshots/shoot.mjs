#!/usr/bin/env node
// Log into a running Lightning instance and screenshot a list of pages.
//
//   node .claude/skills/screenshots/shoot.mjs [options] <name>=<path> ...
//   node .claude/skills/screenshots/shoot.mjs [options] --spec shots.json
//
// Options (all optional):
//   --base URL        default http://localhost:4000 (setup.sh's server)
//   --email EMAIL     default demo@openfn.org
//   --password PASS   default welcome12345 (demo + kickstart default)
//   --out DIR         default ./screenshots
//   --width N         default 1440
//   --height N        default 900
//   --full            capture the full scrollable page, not just the viewport
//   --wait SELECTOR   extra selector to wait for on every page
//   --spec FILE       JSON list of shots (below), instead of positional args
//
// Each positional arg is name=path, e.g. projects=/projects. Use
// name=path@selector to wait for a specific element before capturing.
//
// A spec file is a JSON array of shots, for when you need to click into
// something or crop to one component:
//
//   [{ "name": "editor-run-panel",
//      "path": "/projects/<id>/w/<id>",
//      "caption": "Run panel open on the first job",   // used by PR comments
//      "wait": "[data-testid=workflow-canvas]",         // optional
//      "steps": [{ "click": "text=Transform data" },    // optional, in order:
//                { "fill": ["input[name=q]", "foo"] },  //   click, fill, press,
//                { "press": "Enter" },                  //   hover, wait (selector),
//                { "wait": ".panel" },                  //   sleep (ms)
//                { "sleep": 500 }],
//      "element": ".panel",                             // optional: crop to this
//      "full": false }]                                 // optional
//
// Every run writes <out>/<name>.png per shot plus <out>/manifest.json
// ([{name, file, url, caption}]), which the pr-screenshots skill reads.
//
// Playwright is resolved from assets/node_modules (run `npm install --prefix
// assets` first). The browser is CHROMIUM_PATH, defaulting to the cloud
// container's /opt/pw-browsers/chromium, so nothing is downloaded.

import { createRequire } from 'node:module';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const require = createRequire(path.join(root, 'assets', 'package.json'));
const { chromium } = require('@playwright/test');

const opts = {
  base: 'http://localhost:4000',
  email: 'demo@openfn.org',
  password: 'welcome12345',
  out: 'screenshots',
  width: 1440,
  height: 900,
  full: false,
  wait: null,
  spec: null,
};
let shots = [];

const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--full') opts.full = true;
  else if (a.startsWith('--')) opts[a.slice(2)] = argv[++i];
  else {
    const [name, rest] = a.split(/=(.*)/s);
    const [p, wait] = rest.split('@');
    shots.push({ name, path: p, wait });
  }
}
if (opts.spec) shots = shots.concat(JSON.parse(readFileSync(opts.spec, 'utf8')));
if (shots.length === 0) shots.push({ name: 'projects', path: '/projects' });

mkdirSync(opts.out, { recursive: true });

// The repo's Playwright version usually doesn't match the browser build that's
// pre-installed in the container, so point at a concrete binary rather than
// letting Playwright look up its own (missing) revision. Override with
// CHROMIUM_PATH.
const launchOpts = { args: ['--no-sandbox'] };
const chromiumPath = process.env.CHROMIUM_PATH || '/opt/pw-browsers/chromium';
if (existsSync(chromiumPath)) launchOpts.executablePath = chromiumPath;

const browser = await chromium.launch(launchOpts);
const context = await browser.newContext({
  viewport: { width: +opts.width, height: +opts.height },
  deviceScaleFactor: 2,
});
// Dev-only overlays: the LiveDebugger bug button and the Tidewave toolbar.
// They aren't part of the product, so keep them out of the shot.
await context.addInitScript(() => {
  document.addEventListener('DOMContentLoaded', () => {
    const style = document.createElement('style');
    style.textContent = '#debug-button, #tidewave-toolbar { display: none !important; }';
    document.head.appendChild(style);
  });
});
const page = await context.newPage();
const errors = [];
page.on('pageerror', e => errors.push(`${page.url()}: ${e.message}`));

// LiveView pages are only interactive once the socket has joined; the root
// element gets the phx-connected class at that point.
async function settle(selector) {
  await page.waitForLoadState('domcontentloaded');
  await page
    .waitForSelector('.phx-connected, [data-phx-main].phx-connected', { timeout: 15000 })
    .catch(() => {});
  if (selector) await page.waitForSelector(selector, { timeout: 30000 });
  if (opts.wait) await page.waitForSelector(opts.wait, { timeout: 30000 });
  await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
  // The /projects welcome banner types itself out (TypewriterHook); wait until
  // the paragraph has stopped growing so the shot isn't mid-sentence.
  if (await page.$('#typewriter-p')) {
    let last = -1;
    for (let i = 0; i < 60; i++) {
      const len = await page.$eval('#typewriter-p', el => el.textContent.length);
      if (len > 0 && len === last) break;
      last = len;
      await page.waitForTimeout(500);
    }
  }
  await page.waitForTimeout(500); // let transitions and fonts finish
}

async function runStep(step) {
  if (step.click) await page.click(step.click);
  else if (step.fill) await page.fill(step.fill[0], step.fill[1]);
  else if (step.press) await page.keyboard.press(step.press);
  else if (step.hover) await page.hover(step.hover);
  else if (step.wait) await page.waitForSelector(step.wait, { timeout: 30000 });
  else if (step.sleep) await page.waitForTimeout(step.sleep);
  else throw new Error(`unknown step ${JSON.stringify(step)}`);
}

await page.goto(`${opts.base}/users/log_in`);
await page.fill('input[type="email"]', opts.email);
await page.fill('input[type="password"]', opts.password);
await Promise.all([
  page.waitForURL(u => !u.pathname.startsWith('/users/log_in'), { timeout: 30000 }),
  page.click('button[type="submit"]'),
]);
console.log(`logged in as ${opts.email} -> ${page.url()}`);

const manifest = [];
let failed = 0;
for (const s of shots) {
  const file = path.join(opts.out, `${s.name}.png`);
  try {
    const url = s.path.startsWith('http') ? s.path : `${opts.base}${s.path}`;
    await page.goto(url);
    await settle(s.wait);
    for (const step of s.steps || []) await runStep(step);
    if (s.steps?.length) await page.waitForTimeout(500);
    if (s.element) await page.locator(s.element).first().screenshot({ path: file });
    else await page.screenshot({ path: file, fullPage: s.full ?? opts.full });
    manifest.push({ name: s.name, file: `${s.name}.png`, url: page.url(), caption: s.caption || '' });
    console.log(`${file}  <- ${page.url()}`);
  } catch (e) {
    failed++;
    console.log(`FAILED ${s.name}: ${e.message.split('\n')[0]}`);
  }
}
writeFileSync(path.join(opts.out, 'manifest.json'), JSON.stringify(manifest, null, 2));

if (errors.length) {
  console.log('\npage errors:');
  for (const e of errors) console.log(`  ${e}`);
}

await browser.close();
process.exit(failed ? 1 : 0);
