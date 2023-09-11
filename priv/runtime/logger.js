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

// Generate a random string of the specified length
const randomString = generateRandomString(numberOfBytes);

// Append an emoji to the string
const stringWithEmoji = randomString + '😀';



const logInterval = 250; // Logging interval in milliseconds

// Function to log a message
function logMessage() {
  // console.log('Logging every 250ms... 😂😎🤣🔊🙌😕😁😅😎😊🤣');
  console.log(stringWithEmoji);
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
