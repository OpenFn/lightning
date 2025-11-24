/**
 * Test Helpers Index
 *
 * Central export file for all test helpers. This allows tests to import
 * multiple helpers from a single location:
 *
 * @example
 * import {
 *   createMockPhoenixChannel,
 *   setupAdaptorStoreTest,
 *   simulateStoreProvider
 * } from "./__helpers__";
 */

// Channel mocks
export {
  createMockPhoenixChannel,
  createMockPhoenixChannelProvider,
  type MockPhoenixChannel,
  type MockPhoenixChannelProvider,
  type MockPush,
} from './channelMocks';

// Store setup helpers
export {
  setupAdaptorStoreTest,
  setupSessionContextStoreTest,
  setupSessionStoreTest,
  setupUIStoreTest,
  setupMultipleStores,
  type AdaptorStoreTestSetup,
  type SessionContextStoreTestSetup,
  type SessionStoreTestSetup,
  type UIStoreTestSetup,
} from './storeHelpers';

// Workflow store helpers
export {
  setupWorkflowStoreTest,
  createEmptyWorkflowYDoc,
  createMinimalWorkflowYDoc,
  type WorkflowStoreTestSetup,
} from './workflowStoreHelpers';

// Workflow factory helpers
export {
  createWorkflowYDoc,
  createLinearWorkflowYDoc,
  createDiamondWorkflowYDoc,
  type CreateWorkflowInput,
} from './workflowFactory';

// Session store helpers
export {
  createMockSocket,
  triggerProviderSync,
  triggerProviderStatus,
  applyProviderUpdate,
  waitForState,
  waitForSessionReady,
  createTestYDoc,
  extractYDocData,
  simulateRemoteUserJoin,
  simulateRemoteUserLeave,
  waitForAsync,
} from './sessionStoreHelpers';

// Session context helpers
export {
  configureMockChannelForContext,
  emitSessionContextEvent,
  emitSessionContextUpdatedEvent,
  testSessionContextRequest,
  testSessionContextError,
  verifyEventHandlersRegistered,
  verifyEventHandlersRemoved,
  simulateContextUpdateSequence,
  verifyTimestampUpdated,
  createMockChannelForScenario,
} from './sessionContextHelpers';

// Store provider helpers
export {
  createStores,
  simulateChannelConnection,
  simulateStoreProvider,
  simulateStoreProviderWithConnection,
  verifyAllStoresPresent,
  verifyStoresAreIndependent,
  testStoreIsolation,
  testIndependentSubscriptions,
  simulateProviderLifecycle,
  type StoreProviderSimulation,
  type ConnectedStoreProviderSimulation,
} from './storeProviderHelpers';

// Breadcrumb helpers
export {
  createMockProject,
  selectBreadcrumbProjectData,
  generateBreadcrumbUrls,
  generateBreadcrumbStructure,
  testStoreFirstPattern,
  testPropsFallbackPattern,
  verifyBreadcrumbItem,
  verifyCompleteBreadcrumbStructure,
  createBreadcrumbScenario,
  createEdgeCaseTestData,
  type BreadcrumbItem,
} from './breadcrumbHelpers';
