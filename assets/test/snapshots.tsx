import puppeteer from 'puppeteer';

import path from 'node:path';
import esbuild from 'esbuild';
import { copy } from 'esbuild-plugin-copy';
import postcss from 'esbuild-postcss';

const PORT = 3322;

async function server() {
  // copied from dev-server.mjs
  const ctx = await esbuild.context({
    entryPoints: ['dev-server/src/index.tsx'],
    outdir: 'dev-server/dist/',
    bundle: true,
    splitting: true,
    sourcemap: false,
    format: 'esm',
    target: ['es2020'],
    plugins: [
      postcss(),
      copy({
        assets: {
          from: ['./dev-server/public/*'],
          to: ['.'],
        },
      }),
    ],
  });

  ctx.serve({
    servedir: 'dev-server/dist',
    port: PORT,
  });
}

const wait = async () =>
  new Promise(resolve => {
    setTimeout(resolve, 500);
  });

async function test() {
  console.log(' >> test');
  // Launch the browser and open a new blank page
  const browser = await puppeteer.launch({
    executablePath: '/snap/bin/chromium', // needed for some reason on my local machine??
  });
  console.log(' >> browser ready', browser.isConnected());
  console.log(await browser.userAgent());
  console.log(await browser.version());
  // console.log(await browser.pages());
  const page = await browser.newPage();
  console.log(' >>page ready');

  // Navigate the page to a URL
  await page.goto(`http://localhost:${PORT}`);
  console.log(' >> navigated');

  await page.setViewport({ width: 3000, height: 3000 });

  await wait();

  await page.screenshot({
    path: 'page.png',
  });

  // await browser.close();

  console.log(' >> done!');
  process.exit(0);
}

server().then(test);
