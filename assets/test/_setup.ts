import '@testing-library/jest-dom';
import { enableMapSet } from 'immer';

// Enable Immer MapSet plugin for tests that use Set in Immer state
enableMapSet();

// Suppress debug logs during tests
console.debug = () => {};

// Or if you want to capture them but not display:
const originalDebug = console.debug;
console.debug = process.env.LOG_LEVEL === 'debug' ? originalDebug : () => {};

// Mock ResizeObserver for HeadlessUI components (Menu, Popover, etc.)
global.ResizeObserver = class ResizeObserver {
  observe() {}
  unobserve() {}
  disconnect() {}
};

// jsdom does not implement Element.scrollIntoView
Element.prototype.scrollIntoView = () => {};
