import { describe as e2eDescribe } from './e2e-helper';

// Raw database structure from describe command
interface DatabaseState {
  projects: Array<{ id: string; name: string }>;
  users: Array<{
    id: string;
    email: string;
    first_name: string;
    last_name: string;
  }>;
  workflows: Array<{
    id: string;
    name: string;
    project_id: string;
  }>;
  timestamp: string;
}

// Developer-friendly shaped data
interface TestData {
  users: {
    admin: { email: string; password: string; id: string };
    editor: { email: string; password: string; id: string };
    viewer: { email: string; password: string; id: string };
    super?: { email: string; password: string; id: string };
  };
  projects: {
    openhie: { id: string; name: string };
    dhis2: { id: string; name: string };
  };
  workflows: {
    openhie: { id: string; name: string; projectId: string };
    dhis2: { id: string; name: string; projectId: string };
  };
}

// Memoized promise for database state
let testDataPromise: Promise<TestData> | null = null;

async function fetchDatabaseState(): Promise<DatabaseState> {
  try {
    const output = await e2eDescribe();
    return JSON.parse(output) as DatabaseState;
  } catch (error) {
    // Re-throw with consistent error handling
    throw error;
  }
}

function shapeDatabaseState(dbState: DatabaseState): TestData {
  // Validate that we have the expected data
  if (!dbState.projects || dbState.projects.length === 0) {
    throw new Error(
      'No projects found in database. Run "bin/e2e setup" to create demo data.'
    );
  }
  if (!dbState.users || dbState.users.length === 0) {
    throw new Error(
      'No users found in database. Run "bin/e2e setup" to create demo data.'
    );
  }
  if (!dbState.workflows || dbState.workflows.length === 0) {
    throw new Error(
      'No workflows found in database. Run "bin/e2e setup" to create demo data.'
    );
  }

  // Find users by email patterns
  const adminUser = dbState.users.find(u => u.email === 'demo@openfn.org');
  const editorUser = dbState.users.find(u => u.email === 'editor@openfn.org');
  const viewerUser = dbState.users.find(u => u.email === 'viewer@openfn.org');
  const superUser = dbState.users.find(u => u.email === 'super@openfn.org');

  if (!adminUser) {
    throw new Error(
      'Admin user (demo@openfn.org) not found in database. Check demo data setup.'
    );
  }
  if (!editorUser) {
    throw new Error(
      'Editor user (editor@openfn.org) not found in database. Check demo data setup.'
    );
  }
  if (!viewerUser) {
    throw new Error(
      'Viewer user (viewer@openfn.org) not found in database. Check demo data setup.'
    );
  }

  // Find projects by name patterns
  const openhieProject = dbState.projects.find(
    p => p.name === 'openhie-project'
  );
  const dhis2Project = dbState.projects.find(p => p.name === 'dhis2-project');

  if (!openhieProject) {
    throw new Error(
      'OpenHIE project not found in database. Check demo data setup.'
    );
  }
  if (!dhis2Project) {
    throw new Error(
      'DHIS2 project not found in database. Check demo data setup.'
    );
  }

  // Find workflows by project association
  const openhieWorkflow = dbState.workflows.find(
    w => w.project_id === openhieProject.id
  );
  const dhis2Workflow = dbState.workflows.find(
    w => w.project_id === dhis2Project.id
  );

  if (!openhieWorkflow) {
    throw new Error(
      'OpenHIE workflow not found in database. Check demo data setup.'
    );
  }
  if (!dhis2Workflow) {
    throw new Error(
      'DHIS2 workflow not found in database. Check demo data setup.'
    );
  }

  return {
    users: {
      admin: {
        email: adminUser.email,
        password: 'welcome12345',
        id: adminUser.id,
      },
      editor: {
        email: editorUser.email,
        password: 'welcome12345',
        id: editorUser.id,
      },
      viewer: {
        email: viewerUser.email,
        password: 'welcome12345',
        id: viewerUser.id,
      },
      ...(superUser && {
        super: {
          email: superUser.email,
          password: 'welcome12345',
          id: superUser.id,
        },
      }),
    },
    projects: {
      openhie: { id: openhieProject.id, name: openhieProject.name },
      dhis2: { id: dhis2Project.id, name: dhis2Project.name },
    },
    workflows: {
      openhie: {
        id: openhieWorkflow.id,
        name: openhieWorkflow.name,
        projectId: openhieWorkflow.project_id,
      },
      dhis2: {
        id: dhis2Workflow.id,
        name: dhis2Workflow.name,
        projectId: dhis2Workflow.project_id,
      },
    },
  };
}

/**
 * Get test data with memoized promise caching.
 *
 * This function fetches the current database state via `bin/e2e describe`
 * and shapes it into a developer-friendly format. Results are cached
 * for the duration of the test run.
 *
 * @returns Promise<TestData> Shaped test data for easy consumption
 */
export function getTestData(): Promise<TestData> {
  if (!testDataPromise) {
    testDataPromise = (async () => {
      try {
        const dbState = await fetchDatabaseState();
        const testData = shapeDatabaseState(dbState);
        return testData;
      } catch (error) {
        throw error;
      }
    })();
  }
  return testDataPromise;
}

/**
 * Synchronous version of getTestData - throws if data fetching fails.
 * Use this only when you're sure the database is ready and you need immediate access.
 *
 * @returns TestData Shaped test data
 * @deprecated Consider using getTestData() async version instead
 */
export function getTestDataSync(): TestData {
  throw new Error(
    'getTestDataSync() is no longer supported since fetchDatabaseState() is now async. ' +
      'Use await getTestData() instead.'
  );
}

/**
 * Reset the memoized cache, forcing a fresh database query on next call.
 * Useful for test isolation when database state may have changed.
 */
export function resetTestDataCache(): void {
  testDataPromise = null;
}

/**
 * Get raw database state without shaping.
 * Useful for debugging or advanced test scenarios.
 */
export async function getRawDatabaseState(): Promise<DatabaseState> {
  return await fetchDatabaseState();
}
