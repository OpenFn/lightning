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

const wait = async (delay = 500) =>
  new Promise(resolve => {
    setTimeout(resolve, delay);
  });

async function test() {
  // Launch the browser and open a new blank page
  const browser = await puppeteer.launch({
    executablePath: '/snap/bin/chromium', // needed for some reason on my local machine??
  });

  const page = await browser.newPage();

  // Navigate the page to a URL
  await page.goto(`http://localhost:${PORT}`);

  await page.setViewport({ width: 2000, height: 1600 });

  await wait(200);

  const chart = await page.$('.react-flow__pane');
  while (true) {
    const sel = await page.$('#select-workflow');
    const id = await page.evaluate(el => el.value, sel);
    console.log(id);
    await chart.screenshot({
      path: `tmp/${id}.png`,
    });

    const nextButton = await page.$('#next-workflow');

    const disabled = await page.evaluate(el => el.disabled, nextButton);
    if (disabled) {
      break;
    }
    await nextButton.click();
    await wait(50);
  }

  // await browser.close();

  console.log(' >> done!');
  process.exit(0);
}

server().then(test);
