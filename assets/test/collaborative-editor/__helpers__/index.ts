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

// AI Assistant helpers
export {
  setupAIAssistantStoreTest,
  createMockAIMessage,
  createMockAISession,
  createMockJobCodeContext,
  createMockWorkflowTemplateContext,
  populateAIStoreWithMessages,
  expectAIMessageInStore,
  expectAIStoreConnected,
  expectAIStoreSessionType,
  createMockConversation,
  createMockWorkflowYAML,
  waitForConnectionState,
  waitForMessages,
  type AIAssistantStoreTestSetup,
} from './aiAssistantHelpers';

// AI Channel mocks
export {
  createAIAssistantChannelMock,
  mockSessionJoinResponse,
  mockNewMessageResponse,
  mockListSessionsResponse,
  mockContextUpdateResponse,
  emitNewMessageEvent,
  emitMessageUpdatedEvent,
  emitSessionCreatedEvent,
  emitErrorEvent,
  createMockAIChannelForScenario,
  simulateMessageExchange,
  type PaginationMeta,
} from './aiChannelMocks';

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

// Session context factory
export {
  createSessionContext,
  createMockWorkflowTemplate,
  createMockUser,
  createMockConfig,
  mockWorkflowTemplate,
  mockUserContext,
  mockProjectContext,
  mockAppConfig,
  mockPermissions,
  type SessionContextResponse,
  type CreateSessionContextOptions,
} from './sessionContextFactory';

// URL state mocks
export {
  createMockURLState,
  getURLStateMockValue,
  type URLStateMock,
  type URLStateMockFns,
  type UseURLStateReturn,
} from './urlStateMocks';

// Store mocks
export {
  createMockSessionContextStore,
  createMockHistoryStore,
  createMockUIStore,
  createMockStoreContextValue,
  defaultSessionContextState,
  defaultUIState,
} from './storeMocks';

// DOM test helpers
export { getVisibleButtonText, queryVisibleButtonText } from './domTestHelpers';
