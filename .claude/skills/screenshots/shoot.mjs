#!/usr/bin/env node
// Log into a running Lightning instance and screenshot a list of pages.
//
//   node .claude/skills/screenshots/shoot.mjs [options] <name>=<path> ...
//
// Options (all optional):
//   --base URL        default http://localhost:4003 (the bin/e2e port)
//   --email EMAIL     default editor@openfn.org
//   --password PASS   default welcome12345 (demo + kickstart default)
//   --out DIR         default ./screenshots
//   --width N         default 1440
//   --height N        default 900
//   --full            capture the full scrollable page, not just the viewport
//   --wait SELECTOR   extra selector to wait for on every page
//
// Each positional arg is name=path, e.g. projects=/projects. The screenshot is
// written to <out>/<name>.png. Use name=path@selector to wait for a specific
// element on that page before capturing.
//
// Playwright is resolved from assets/node_modules (run `npm install --prefix
// assets` first). The browser is CHROMIUM_PATH, defaulting to the cloud
// container's /opt/pw-browsers/chromium, so nothing is downloaded.

import { createRequire } from 'node:module';
import { existsSync, mkdirSync } from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const require = createRequire(path.join(root, 'assets', 'package.json'));
const { chromium } = require('@playwright/test');

const opts = {
  base: 'http://localhost:4003',
  email: 'editor@openfn.org',
  password: 'welcome12345',
  out: 'screenshots',
  width: 1440,
  height: 900,
  full: false,
  wait: null,
};
const pages = [];

const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === '--full') opts.full = true;
  else if (a.startsWith('--')) opts[a.slice(2)] = argv[++i];
  else {
    const [name, rest] = a.split(/=(.*)/s);
    const [p, sel] = rest.split('@');
    pages.push({ name, path: p, selector: sel });
  }
}
if (pages.length === 0) pages.push({ name: 'projects', path: '/projects' });

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

await page.goto(`${opts.base}/users/log_in`);
await page.fill('input[type="email"]', opts.email);
await page.fill('input[type="password"]', opts.password);
await Promise.all([
  page.waitForURL(u => !u.pathname.startsWith('/users/log_in'), { timeout: 30000 }),
  page.click('button[type="submit"]'),
]);
console.log(`logged in as ${opts.email} -> ${page.url()}`);

for (const p of pages) {
  const url = p.path.startsWith('http') ? p.path : `${opts.base}${p.path}`;
  await page.goto(url);
  await settle(p.selector);
  const file = path.join(opts.out, `${p.name}.png`);
  await page.screenshot({ path: file, fullPage: opts.full });
  console.log(`${file}  <- ${page.url()}`);
}

if (errors.length) {
  console.log('\npage errors:');
  for (const e of errors) console.log(`  ${e}`);
}

await browser.close();
