// Seeds one copy of the e2e scenario per extra Playwright worker, so parallel
// tests never share a user or project. Worker 0 keeps the instance's own
// scenario and manifest. Worker n gets owner-wn@openfn.org, example-project-wn
// and so on, through the same Kickstart run, with its own manifest. Kickstart
// derives ids from names, so re-seeding a worker is idempotent.
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, statSync, writeFileSync } from 'node:fs';

import type { FullConfig } from '@playwright/test';
import { load } from 'js-yaml';

import { STATE, workerManifest } from './workers';

export default function globalSetup(config: FullConfig) {
  if (process.env.TARGET === 'demo' || config.workers < 2) return;

  const instance = JSON.parse(
    readFileSync(`${STATE}/instance.json`, 'utf8')
  ) as { root: string; scenario: string; started_at: string };
  const started = Date.parse(instance.started_at);
  const text = readFileSync(instance.scenario, 'utf8');
  const scenario = JSON.stringify(
    instance.scenario.endsWith('.json') ? JSON.parse(text) : load(text)
  );
  const names = [
    ...text.matchAll(/^\s*-?\s*name:\s*['"]?([^'"\n#]+?)['"]?\s*(?:#.*)?$/gm),
  ].map(m => m[1]);

  for (let n = 1; n < config.workers; n++) {
    const manifest = workerManifest(n);
    if (existsSync(manifest) && statSync(manifest).mtimeMs > started) continue;

    let copy = scenario.replace(
      /([\w.]+)@openfn\.org/g,
      (_, local: string) => `${local}-w${n}@openfn.org`
    );
    for (const name of names)
      copy = copy.replaceAll(
        JSON.stringify(name),
        JSON.stringify(`${name}-w${n}`)
      );
    const file = `${STATE}/scenario-w${n}.json`;
    writeFileSync(file, copy);

    execFileSync('mix', ['lightning.kickstart', file, '--manifest', manifest], {
      cwd: instance.root,
      stdio: 'inherit',
      env: {
        ...process.env,
        MIX_ENV: 'dev',
        DATABASE_URL:
          process.env.LIGHTNING_DB ||
          'postgres://postgres:postgres@localhost/lightning_test_e2e',
      },
    });
  }
}
