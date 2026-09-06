/**
 * createUIStore — landing screen modal tests
 *
 * The YAML import and template browser modals are rendered as siblings, each
 * gated on its own flag, and both close on Escape at the same priority. They
 * must never be open at once, or which one Escape closes comes down to
 * whichever registered its handler first.
 */

import { describe, expect, test } from 'vitest';

import { createUIStore } from '../../../js/collaborative-editor/stores/createUIStore';

describe('createUIStore — modal open/close', () => {
  test('both modals start closed and open and close independently', () => {
    const store = createUIStore();
    expect(store.getSnapshot().showYAMLImportModal).toBe(false);
    expect(store.getSnapshot().showTemplateBrowserModal).toBe(false);

    store.openYAMLImportModal();
    expect(store.getSnapshot().showYAMLImportModal).toBe(true);

    store.closeYAMLImportModal();
    expect(store.getSnapshot().showYAMLImportModal).toBe(false);

    store.openTemplateBrowserModal();
    expect(store.getSnapshot().showTemplateBrowserModal).toBe(true);

    store.closeTemplateBrowserModal();
    expect(store.getSnapshot().showTemplateBrowserModal).toBe(false);
  });
});

describe('createUIStore — modals are mutually exclusive', () => {
  test('opening the YAML import modal closes the template browser', () => {
    const store = createUIStore();
    store.openTemplateBrowserModal();

    store.openYAMLImportModal();

    expect(store.getSnapshot().showYAMLImportModal).toBe(true);
    expect(store.getSnapshot().showTemplateBrowserModal).toBe(false);
  });

  test('opening the template browser closes the YAML import modal', () => {
    const store = createUIStore();
    store.openYAMLImportModal();

    store.openTemplateBrowserModal();

    expect(store.getSnapshot().showTemplateBrowserModal).toBe(true);
    expect(store.getSnapshot().showYAMLImportModal).toBe(false);
  });
});
