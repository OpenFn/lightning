function generateRandomString(length) {
  let result = '';
  const characters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

  for (let i = 0; i < length; i++) {
    const randomIndex = Math.floor(Math.random() * characters.length);
    result += characters.charAt(randomIndex);
  }

  return result;
}

// Number of bytes you want (1023 in this case)
const numberOfBytes = 1023;


const logInterval = 3000; // Logging interval in milliseconds

// Function to log a message
function logMessage() {
  // Generate a random string of the specified length
  const randomString = generateRandomString(numberOfBytes);


  for (let i = 0; i < randomString.length; i++) {
    process.stdout.write(randomString.charAt(i));
  }

  // Append an emoji to the string
  process.stdout.write('😀');

  process.stdout.write('\n');

}

// Start logging
const intervalId = setInterval(logMessage, logInterval);

// Handle SIGTERM signal
process.on('SIGTERM', () => {
  console.log('Received SIGTERM signal. Gracefully shutting down...');

  // Stop logging and perform any necessary cleanup
  clearInterval(intervalId);

  // Add any other cleanup logic here if needed

  // Exit the process with a success status code (0)
  process.exit(0);
});
