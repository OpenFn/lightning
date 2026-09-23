import { test, expect } from '@playwright/test';

import { LoginPage } from '../../pages';
import { startSentryListener } from '../../sentry-listener';
import { getTestData } from '../../test-data';

// Run with `npm run test:e2e:sentry`, which boots the server with both DSNs
// pointing at the listener. A server already running on that port without
// them fails the meta tag check.
const dsn = process.env.SENTRY_DSN;

test.skip(!dsn, 'SENTRY_DSN not set; run via npm run test:e2e:sentry');

test('browser and server errors reach Sentry', async ({ page }) => {
  const listener = await startSentryListener(Number(new URL(dsn!).port));
  const testData = await getTestData();

  try {
    await page.goto('/');
    await new LoginPage(page).loginIfNeeded(
      testData.users.editor.email,
      testData.users.editor.password
    );

    const meta = (name: string) =>
      page.locator(`meta[name='${name}']`).getAttribute('content');
    const environment = await meta('sentry-environment');
    const release = await meta('sentry-release');
    expect(environment, 'server rendered no sentry meta tags').toBeTruthy();

    const marker = `sentry-smoke-${Date.now()}`;

    await page.evaluate(message => {
      setTimeout(() => {
        throw new Error(message);
      });
    }, `${marker} browser`);

    // An id that isn't a UUID raises Ecto.Query.CastError in the controller,
    // which Sentry.PlugCapture reports.
    const response = await page.request.get(`/dataclip/body/${marker}`);
    expect(response.status()).toBeGreaterThanOrEqual(400);

    const find = (platform: string) =>
      listener.events().find(e => e.platform === platform);

    await expect
      .poll(() => find('javascript'), { timeout: 15_000 })
      .toBeTruthy();
    await expect.poll(() => find('elixir'), { timeout: 15_000 }).toBeTruthy();

    const browserEvent = find('javascript')!;
    const serverEvent = find('elixir')!;

    expect(JSON.stringify(browserEvent.exception)).toContain(
      `${marker} browser`
    );
    expect(browserEvent.environment).toBe(environment);
    expect(browserEvent.release).toBe(release);
    expect(serverEvent.request?.url).toContain(marker);

    const requestId = await meta('request-id');
    expect(requestId).toBeTruthy();
    expect(browserEvent.tags?.request_id).toBe(requestId);

    // An event the LiveView has no handle_event clause for crashes its
    // process, and Sentry.LoggerHandler reports the crash.
    await page.evaluate(event => {
      const el = document.querySelector('[data-phx-main]');
      (window as any).liveSocket.execJS(
        el,
        JSON.stringify([['push', { event }]])
      );
    }, `${marker}-unhandled`);

    const liveViewEvent = () =>
      listener
        .events()
        .find(
          e =>
            e.platform === 'elixir' &&
            JSON.stringify(e).includes(`${marker}-unhandled`)
        );
    await expect.poll(liveViewEvent, { timeout: 15_000 }).toBeTruthy();
    expect(liveViewEvent()!.tags?.request_id).toBe(requestId);
  } finally {
    await listener.close();
  }
});
