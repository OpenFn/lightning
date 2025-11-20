import adze, { setup } from 'adze';

// Set the format to "json"
setup({
  activeLevel: 'debug',
  timestampFormatter: date =>
    date.toLocaleTimeString('en-US', { hour12: false }),
});

const logger = adze.seal();
export default logger;
