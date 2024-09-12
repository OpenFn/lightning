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
    // If chromium fails to launch, you may need to set this (and maybe update the path)
    // executablePath: '/snap/bin/chromium',
  });

  const page = await browser.newPage();

  // Navigate the page to a URL
  await page.goto(`http://localhost:${PORT}`);

  await page.setViewport({ width: 2000, height: 1600 });

  await wait(200);

  const chart = await page.$('.react-flow__pane');
  let p;
  while (true) {
    const sel = await page.$('#select-workflow');
    const id = await page.evaluate(el => el.value, sel);
    p = path.resolve(`tmp/${id}.png`)
    console.log('snapshotting', id);
    await chart.screenshot({
      path: p,
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
  console.log();
  console.log('See snapshots at ', path.dirname(p))
  process.exit(0);
}

server().then(test);
