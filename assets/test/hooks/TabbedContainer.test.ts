import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';

import { TabbedContainer } from '../../js/hooks/TabbedContainer';

// Mirrors the markup lib/lightning_web/components/ui/tabs.ex renders.
function render(defaultHash: string | null) {
  document.body.innerHTML = `
    <div id="container" ${defaultHash ? `data-default-hash="${defaultHash}"` : ''}>
      <div role="tablist">
        <a id="log-tab" aria-controls="log-panel" aria-selected="false" role="tab" href="#log">Log</a>
        <a id="input-tab" aria-controls="input-panel" aria-selected="false" role="tab" href="#input">Input</a>
        <span id="output-tab" aria-controls="output-panel" aria-selected="false" role="tab" data-disabled>Output</span>
      </div>
      <div id="log-panel" role="tabpanel" class="flex hidden">log</div>
      <div id="input-panel" role="tabpanel" class="flex hidden">input</div>
      <div id="output-panel" role="tabpanel" class="flex hidden">output</div>
    </div>`;
  return document.getElementById('container')!;
}

function mount(defaultHash: string | null = 'log') {
  const handlers: Record<string, (payload: any) => void> = {};
  const hook = Object.assign(Object.create(TabbedContainer), {
    el: render(defaultHash),
    handleEvent: (name: string, cb: (payload: any) => void) => {
      handlers[name] = cb;
    },
  });
  hook.mounted();
  return { hook, handlers };
}

function selected() {
  const tab = document.querySelector('[aria-selected="true"]');
  const panels = [...document.querySelectorAll('[role=tabpanel]')]
    .filter(p => !p.classList.contains('hidden'))
    .map(p => p.id);
  return { tab: tab?.id ?? null, panels };
}

function setHash(hash: string) {
  window.location.hash = hash;
  window.dispatchEvent(new HashChangeEvent('hashchange'));
}

describe('TabbedContainer', () => {
  let mounted: ReturnType<typeof mount> | undefined;

  beforeEach(() => {
    vi.stubGlobal('requestAnimationFrame', (cb: FrameRequestCallback) => {
      cb(0);
      return 0;
    });
    history.replaceState(null, '', '/');
  });

  afterEach(() => {
    mounted?.hook.destroyed();
    mounted = undefined;
    vi.unstubAllGlobals();
  });

  test('opens the tab in the URL hash, falling back to the default', () => {
    mounted = mount('log');
    expect(selected()).toEqual({ tab: 'log-tab', panels: ['log-panel'] });
    mounted.hook.destroyed();

    history.replaceState(null, '', '/#input');
    mounted = mount('log');
    expect(selected()).toEqual({ tab: 'input-tab', panels: ['input-panel'] });
  });

  test('shows nothing when there is no hash and no default', () => {
    mounted = mount(null);
    expect(selected()).toEqual({ tab: null, panels: [] });
  });

  test('switches tab when the hash changes, and ignores unknown hashes', () => {
    mounted = mount('log');

    setHash('input');
    expect(selected()).toEqual({ tab: 'input-tab', panels: ['input-panel'] });

    setHash('nonsense');
    expect(selected()).toEqual({ tab: 'input-tab', panels: ['input-panel'] });
  });

  test('opens a disabled tab when its hash is in the URL', () => {
    mounted = mount('log');
    setHash('output');
    expect(selected()).toEqual({ tab: 'output-tab', panels: ['output-panel'] });
  });

  test('re-applies the hash after a LiveView update', () => {
    history.replaceState(null, '', '/#input');
    mounted = mount('log');

    // A server patch without lv-keep-* would reset the markup like this.
    document
      .getElementById('input-tab')!
      .setAttribute('aria-selected', 'false');
    document.getElementById('input-panel')!.classList.add('hidden');
    mounted.hook.updated();

    expect(selected()).toEqual({ tab: 'input-tab', panels: ['input-panel'] });
  });

  test('sets the hash on a push-hash server event', () => {
    mounted = mount('log');
    mounted.handlers['push-hash']({ hash: 'input' });
    expect(window.location.hash).toBe('#input');
  });

  test('stops listening for hash changes once destroyed', () => {
    mounted = mount('log');
    mounted.hook.destroyed();
    mounted = undefined;

    setHash('input');
    expect(selected()).toEqual({ tab: 'log-tab', panels: ['log-panel'] });
  });
});
