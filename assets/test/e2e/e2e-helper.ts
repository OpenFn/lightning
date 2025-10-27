import * as path from 'path';
import { execSync } from 'child_process';
import { existsSync, readFileSync, unlinkSync } from 'fs';
import { fileURLToPath } from 'url';

// ES module equivalent of __dirname
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * Helper module for interacting with the bin/e2e script.
 * Provides async wrappers for common e2e operations.
 */

interface ExecuteOptions {
  timeout?: number;
  cwd?: string;
}

export const binPath = path.resolve(__dirname, '../../..', 'bin/e2e');

/**
 * Execute a bin/e2e command with proper error handling
 */
function executeCommand(command: string, options: ExecuteOptions = {}): string {
  try {
    const output = execSync(`${binPath} ${command}`, {
      encoding: 'utf-8',
      timeout: options.timeout || 30000, // 30 second default timeout
      ...options,
    });

    return output.trim();
  } catch (error) {
    // Enhanced error messages for common scenarios
    if (error instanceof Error) {
      if (error.message.includes('ENOENT')) {
        throw new Error(
          `E2E script not found at ${binPath}. ` +
            `Make sure you're running from the correct directory and the script exists.`
        );
      }

      if (error.message.includes('timeout')) {
        throw new Error(
          `E2E command '${command}' timed out after ${options.timeout || 30000}ms. ` +
            `The database setup or command may be taking longer than expected.`
        );
      }

      if (
        error.message.includes('Connection refused') ||
        error.message.includes('could not connect')
      ) {
        throw new Error(
          `Database connection failed during '${command}'. ` +
            `Make sure PostgreSQL is running and accessible.`
        );
      }
    }

    throw new Error(`E2E command '${command}' failed: ${error}`);
  }
}

/**
 * Get current database state as JSON
 */
export async function describe(): Promise<string> {
  return new Promise((resolve, reject) => {
    try {
      const output = executeCommand('describe');

      // Check for null/empty output
      if (!output || output === 'null') {
        reject(
          new Error(
            'E2E describe command returned null or empty response. ' +
              'This usually means the e2e database is not set up. ' +
              'Run "bin/e2e setup" to initialize the database with demo data.'
          )
        );
        return;
      }

      // Validate JSON format
      try {
        JSON.parse(output);
        resolve(output);
      } catch (parseError) {
        reject(
          new Error(
            `E2E describe returned invalid JSON: ${output.slice(0, 200)}... ` +
              `Parse error: ${parseError}`
          )
        );
      }
    } catch (error) {
      reject(error);
    }
  });
}

/**
 * Reset database to clean state using snapshot (fast)
 */
export async function reset(options: { quiet?: boolean } = {}): Promise<void> {
  return new Promise((resolve, reject) => {
    try {
      const command = options.quiet ? 'reset --quiet' : 'reset';
      executeCommand(command, { timeout: 60000 }); // 1 minute timeout for reset
      resolve();
    } catch (error) {
      reject(new Error(`Database reset failed: ${error}`));
    }
  });
}

/**
 * Enable experimental features for a user (defaults to editor@openfn.org)
 *
 * This allows the user to access experimental features like the collaborative
 * editor. The setting is persisted in the database and will remain enabled
 * until reset or explicitly disabled.
 *
 * @param userEmail - Optional email of the user to enable features for
 * @returns Promise that resolves when features are enabled
 * @throws Error if the command fails
 *
 * @example
 * ```typescript
 * // Enable for default user (editor@openfn.org)
 * await enableExperimentalFeatures();
 *
 * // Enable for specific user
 * await enableExperimentalFeatures("admin@openfn.org");
 * ```
 */
export async function enableExperimentalFeatures(
  userEmail: string = 'editor@openfn.org'
): Promise<void> {
  return new Promise((resolve, reject) => {
    try {
      const command =
        userEmail === 'editor@openfn.org'
          ? 'enable-experimental-features'
          : `enable-experimental-features ${userEmail}`;

      executeCommand(command);
      resolve();
    } catch (error) {
      reject(
        new Error(
          `Failed to enable experimental features for ${userEmail}: ${error}`
        )
      );
    }
  });
}

/**
 * Start the e2e server (for manual testing or debugging)
 * Note: This will not return until the server is stopped
 */
export async function startServer(): Promise<void> {
  return new Promise((resolve, reject) => {
    try {
      executeCommand('server'); // No timeout - server runs indefinitely
      resolve();
    } catch (error) {
      reject(new Error(`Failed to start e2e server: ${error}`));
    }
  });
}

/**
 * Check if e2e infrastructure is available
 */
export async function isAvailable(): Promise<boolean> {
  try {
    executeCommand('help', { timeout: 5000 });
    return true;
  } catch {
    return false;
  }
}

/**
 * Check if e2e server is already running by checking PID file
 */
export function isServerRunning(): boolean {
  const pidFile = '/tmp/lightning_e2e_server';

  try {
    // Check if PID file exists
    if (!existsSync(pidFile)) {
      return false;
    }

    // Read PID from file
    const pidContent = readFileSync(pidFile, 'utf-8').trim();
    const pid = parseInt(pidContent, 10);

    if (isNaN(pid) || pid <= 0) {
      return false;
    }

    // Check if process is running
    try {
      process.kill(pid, 0); // Signal 0 just checks if process exists
      return true;
    } catch (error) {
      // Process doesn't exist, clean up stale PID file
      try {
        unlinkSync(pidFile);
      } catch {
        // Ignore cleanup errors
      }
      return false;
    }
  } catch (error) {
    return false;
  }
}

/**
 * Check if e2e server is already running (safe version with proper imports)
 */
export function checkServerRunning(): boolean {
  const pidFile = '/tmp/lightning_e2e_server';

  try {
    if (!existsSync(pidFile)) {
      return false;
    }

    const pidContent = readFileSync(pidFile, 'utf-8').trim();
    const pid = parseInt(pidContent, 10);

    if (isNaN(pid) || pid <= 0) {
      return false;
    }

    try {
      process.kill(pid, 0);
      return true;
    } catch {
      try {
        unlinkSync(pidFile);
      } catch {
        // Ignore cleanup errors
      }
      return false;
    }
  } catch {
    return false;
  }
}
