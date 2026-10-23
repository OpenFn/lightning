import { ToastProvider, useToast } from '@openfn/ui';
import { StrictMode, useEffect } from 'react';
import { createRoot } from 'react-dom/client';

import type {
  GetPhoenixHookInternalThis,
  PhoenixHook,
} from '#/hooks/PhoenixHook';

/**
 * LiveView's flash, drawn as the design system's toast on every page. The
 * server keeps calling `put_flash`; each layout renders a `FlashBridge`
 * element carrying the text, and the hook hands it to one toaster that
 * app.js mounts outside the LiveView, so a toast survives navigation.
 */
type Tone = 'info' | 'error';
type Show = (message: string, tone: Tone) => void;

let show: Show | null = null;
// Messages that arrive before the toaster has rendered
const pending: [string, Tone][] = [];

const showFlash: Show = (message, tone) => {
  if (show) show(message, tone);
  else pending.push([message, tone]);
};

const Connect = () => {
  const toast = useToast();
  useEffect(() => {
    show = toast;
    for (const [message, tone] of pending.splice(0)) toast(message, tone);
    return () => {
      show = null;
    };
  }, [toast]);
  return null;
};

export const Toaster = () => (
  <ToastProvider>
    <Connect />
  </ToastProvider>
);

/** Mounts the toaster once, outside the LiveView. */
export const mountFlash = () => {
  const el = document.createElement('div');
  document.body.appendChild(el);
  createRoot(el).render(
    <StrictMode>
      <Toaster />
    </StrictMode>
  );
};

export const FlashBridge = {
  mounted() {
    this.seen = {};
    this.publish();
  },
  updated() {
    this.publish();
  },
  publish() {
    for (const key of ['info', 'error'] as const) {
      const message = this.el.dataset[key];
      // Any patch before the clear lands re-runs this; show each message once
      if (!message) {
        delete this.seen[key];
        continue;
      }
      if (message === this.seen[key]) continue;
      this.seen[key] = message;
      showFlash(message, key);
      // Cleared once shown, so the same message flashed again shows again
      this.pushEvent('lv:clear-flash', { key });
    }
  },
} satisfies ThisType<
  GetPhoenixHookInternalThis<
    PhoenixHook<{ publish(): void; seen: Partial<Record<Tone, string>> }>
  >
>;
