import "@testing-library/jest-dom";

// Increase max listeners to avoid warning during test runs
// This is safe for tests as multiple test files add cleanup handlers
process.setMaxListeners(20);

// Suppress debug logs during tests
console.debug = () => {};

// Or if you want to capture them but not display:
const originalDebug = console.debug;
console.debug = process.env.LOG_LEVEL === "debug" ? originalDebug : () => {};
