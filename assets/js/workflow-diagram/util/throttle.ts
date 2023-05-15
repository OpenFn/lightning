export default (fn: () => void, duration = 100) => {
  let callAgain = false;
  let timeout;

  const run = () => {
    if (timeout) {
      // Callback/timeout in progress, do nothing (but register another go)
      callAgain = true;
    } else {
      // Start a new callback
      callAgain = false;

      // Call back after duration ms, if neccessary
      timeout = setTimeout(() => {
        timeout = undefined;
        if (callAgain) {
          run();
        }
      }, duration);

      // Run the function
      fn();
    }
  };

  run.cancel = () => {
    clearTimeout(timeout);
  };

  return run;
};
