/** @type import('./app.d.ts') */
//
// We import the CSS which is extracted to its own file by esbuild.
// Remove this line if you add a your own CSS build pipeline (e.g postcss).

// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import 'phoenix_html';
// Establish Phoenix Socket and LiveView configuration.
import * as Sentry from '@sentry/react';
// Enable Immer plugins for Set/Map support in stores
import { enableMapSet } from 'immer';
import { Socket } from 'phoenix';
import { LiveSocket } from 'phoenix_live_view';

import topbar from '../vendor/topbar.cjs';

import * as Hooks from './hooks';
import LogViewer from './log-viewer';

enableMapSet();

const metaContent = name =>
  document.querySelector(`meta[name='${name}']`)?.getAttribute('content') ||
  undefined;

// Rendered by <.sentry_frontend_tags /> in root.html.heex only when the
// deployment sets SENTRY_FRONTEND_DSN; without a DSN the SDK stays disabled
// and sends nothing.
const sentryDsn = metaContent('sentry-dsn');
const requestId = metaContent('request-id');

// localStorage throws when the browser blocks site data.
const localFlag = key => {
  try {
    return localStorage.getItem(key) === 'true';
  } catch {
    return false;
  }
};

Sentry.init({
  dsn: sentryDsn,
  environment: metaContent('sentry-environment'),
  release: metaContent('sentry-release'),
  initialScope: { tags: { request_id: requestId } },
  debug: localFlag('sentryDebug'),
  beforeSend: event => {
    if (!localFlag('sentryDryRun')) return event;
    console.log('[sentry dry-run]', event);
    return null;
  },
  ignoreErrors: [
    // Benign, browser-generated, and not actionable.
    'ResizeObserver loop limit exceeded',
    'ResizeObserver loop completed with undelivered notifications.',
  ],
  denyUrls: [
    // Errors originating in browser-extension code, not ours.
    /^chrome-extension:\/\//i,
    /^moz-extension:\/\//i,
    /^safari-(web-)?extension:\/\//i,
  ],
});

const hooks = {
  LogViewer,
  ...Hooks,
};

// @ts-ignore
const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute('content');

const liveSocket = new LiveSocket('/live', Socket, {
  params: { _csrf_token: csrfToken, request_id: requestId },
  hooks,
  dom: {
    onBeforeElUpdated(from, to) {
      // If an element has any of the 'lv-keep-*' attributes, copy across
      // the given attribute to maintain various styles and properties
      // that have had their control handed-over to a Hook or JS implementation.
      if (from.attributes['lv-keep-style']) {
        const style = from.getAttribute('style');
        if (style != null) {
          to.setAttribute('style', style);
        }
      }

      if (from.attributes['lv-keep-class']) {
        const className = from.getAttribute('class');
        if (className != null) {
          to.setAttribute('class', className);
        }
      }

      if (from.attributes['lv-keep-hidden']) {
        const hidden = from.getAttribute('hidden');
        if (hidden != null) {
          to.setAttribute('hidden', hidden);
        }
      }

      if (from.attributes['lv-keep-type']) {
        const type = from.getAttribute('type');
        if (type != null) {
          to.setAttribute('type', type);
        }
      }

      if (from.attributes['lv-keep-aria']) {
        Object.values(from.attributes).forEach(attr => {
          if (attr.name.startsWith('aria-')) {
            to.setAttribute(attr.name, attr.value);
          }
        });
      }

      return true;
    },
  },
});

// Show progress bar on live navigation and form submits
// Include a 120ms timeout to avoid small flashes when things load quickly.
topbar.config({ barColors: { 0: '#29d' }, shadowColor: 'rgba(0, 0, 0, .3)' });

let topBarScheduled = 0;

window.addEventListener('phx:page-loading-start', () => {
  if (!topBarScheduled) {
    topBarScheduled = setTimeout(() => topbar.show(), 120);
  }
});

window.addEventListener('phx:page-loading-stop', () => {
  clearTimeout(topBarScheduled);
  topBarScheduled = 0;
  topbar.hide();
});

// connect if there are any LiveViews on the page
liveSocket.connect();
// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

// Testing helper to simulate a reconnect
window.triggerReconnect = function triggerReconnect(timeout = 5000) {
  liveSocket.disconnect(() => {});
  setTimeout(liveSocket.connect.bind(liveSocket), timeout);
};
