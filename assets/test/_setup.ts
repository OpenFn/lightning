import "@testing-library/jest-dom";

// Suppress debug logs during tests
console.debug = () => {};

// Or if you want to capture them but not display:
const originalDebug = console.debug;
console.debug = process.env.LOG_LEVEL === "debug" ? originalDebug : () => {};
