import { test as setup } from '@playwright/test';
import { reset, isAvailable } from './e2e-helper';
import { resetTestDataCache } from './test-data';

/**
 * Global setup for E2E tests
 *
 * This runs once before all test suites and ensures:
 * 1. E2E infrastructure is available
 * 2. Database is reset to clean state
 * 3. Test data cache is cleared
 */

setup('prepare e2e environment', async () => {
  console.log('🔧 Setting up E2E test environment...');

  // Check if e2e infrastructure is available
  const available = await isAvailable();
  if (!available) {
    throw new Error(
      'E2E infrastructure not available. ' +
        'Make sure bin/e2e script exists and PostgreSQL is running. ' +
        'Run "bin/e2e setup" to initialize the database.'
    );
  }

  console.log('✅ E2E infrastructure is available');

  // Reset database to clean state using snapshot (fast)
  try {
    console.log('🔄 Resetting database to clean state...');
    await reset({ quiet: true });
    console.log('✅ Database reset complete');
  } catch (error) {
    console.error('❌ Database reset failed:', error);
    throw new Error(
      'Failed to reset e2e database. ' +
        'This could mean the snapshot is missing or corrupted. ' +
        'Try running "bin/e2e setup" to recreate the demo data and snapshot.'
    );
  }

  // Clear test data cache to force fresh fetch
  resetTestDataCache();
  console.log('✅ Test data cache cleared');

  console.log('🎉 E2E environment ready for testing!');
});
