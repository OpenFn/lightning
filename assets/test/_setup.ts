import '@testing-library/jest-dom';
import { enableMapSet } from 'immer';

// Enable Immer MapSet plugin for tests that use Set in Immer state
enableMapSet();

// Increase max listeners to avoid warning during test runs
// This is safe for tests as multiple test files add cleanup handlers
process.setMaxListeners(24);

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
