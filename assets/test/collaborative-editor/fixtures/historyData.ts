/**
 * Test fixtures for workflow run history data
 *
 * Provides consistent test data for testing the MiniHistory component
 * and related functionality.
 */

import type {
  WorkOrder,
  Run,
} from '../../../js/collaborative-editor/types/history';

// Extended types with selection for testing
type RunWithSelection = Run & { selected?: boolean };
type WorkOrderWithSelection = Omit<WorkOrder, 'runs'> & {
  runs: RunWithSelection[];
  selected?: boolean;
};

// Run state type for testing
type RunState = Run['state'];

/**
 * Helper to create a mock Run with sensible defaults
 */
export function createMockRun(
  overrides: Partial<RunWithSelection> = {}
): RunWithSelection {
  return {
    id: '7d5e0711-e2fd-44a4-91cc-fa0c335f88e4',
    state: 'success',
    started_at: '2025-10-23T21:00:01.106711Z',
    finished_at: '2025-10-23T21:00:02.098356Z',
    error_type: null,
    selected: false,
    ...overrides,
  };
}

/**
 * Helper to create a mock WorkOrder with sensible defaults
 */
export function createMockWorkOrder(
  overrides: Partial<WorkOrderWithSelection> = {}
): WorkOrderWithSelection {
  return {
    id: 'e2107d46-cf29-4930-b11b-cbcfcf83549d',
    version: 29,
    state: 'success',
    runs: [createMockRun()],
    last_activity: '2025-10-23T21:00:02.293382Z',
    selected: false,
    ...overrides,
  };
}

/**
 * Sample work order with successful run
 */
export const mockSuccessfulWorkOrder: WorkOrderWithSelection =
  createMockWorkOrder({
    id: 'e2107d46-cf29-4930-b11b-cbcfcf83549d',
    state: 'success',
    runs: [
      createMockRun({
        id: '7d5e0711-e2fd-44a4-91cc-fa0c335f88e4',
        state: 'success',
        started_at: '2025-10-23T21:00:01.106711Z',
        finished_at: '2025-10-23T21:00:02.098356Z',
      }),
    ],
    last_activity: '2025-10-23T21:00:02.293382Z',
  });

/**
 * Sample work order with failed run
 */
export const mockFailedWorkOrder: WorkOrderWithSelection = createMockWorkOrder({
  id: '547d11ad-cf57-434f-b0d1-2b511b9557dc',
  state: 'failed',
  runs: [
    createMockRun({
      id: '14ee8074-9f6a-4b8a-b44d-138e96702087',
      state: 'failed',
      started_at: '2025-10-23T20:45:01.709297Z',
      finished_at: '2025-10-23T20:45:02.505881Z',
      error_type: 'RUNTIME_ERROR',
    }),
  ],
  last_activity: '2025-10-23T20:45:02.712046Z',
});

/**
 * Sample work order with crashed run
 */
export const mockCrashedWorkOrder: WorkOrderWithSelection = createMockWorkOrder(
  {
    id: '6443ba23-79e8-4779-b1bd-25158bd66cbe',
    state: 'crashed',
    runs: [
      createMockRun({
        id: 'f37c0de9-c4fb-49e6-af78-27b95ce03240',
        state: 'crashed',
        started_at: '2025-10-23T20:30:01.070370Z',
        finished_at: '2025-10-23T20:30:01.900177Z',
        error_type: 'CRASH',
      }),
    ],
    last_activity: '2025-10-23T20:30:02.064561Z',
  }
);

/**
 * Sample work order with multiple runs
 */
export const mockMultiRunWorkOrder: WorkOrderWithSelection =
  createMockWorkOrder({
    id: 'b65107f9-2a5f-4bd1-b97d-b8500a58f621',
    state: 'success',
    runs: [
      createMockRun({
        id: '8c7087f8-7f9e-48d9-a074-dc58b5fd9fb9',
        state: 'success',
        started_at: '2025-10-23T20:15:01.791928Z',
        finished_at: '2025-10-23T20:15:02.619074Z',
      }),
      createMockRun({
        id: '9c7087f8-7f9e-48d9-a074-dc58b5fd9fc0',
        state: 'success',
        started_at: '2025-10-23T20:15:03.791928Z',
        finished_at: '2025-10-23T20:15:04.619074Z',
      }),
      createMockRun({
        id: 'ac7087f8-7f9e-48d9-a074-dc58b5fd9fd1',
        state: 'success',
        started_at: '2025-10-23T20:15:05.791928Z',
        finished_at: '2025-10-23T20:15:06.619074Z',
      }),
    ],
    last_activity: '2025-10-23T20:15:02.825683Z',
  });

/**
 * Sample work order with running state
 */
export const mockRunningWorkOrder: WorkOrderWithSelection = createMockWorkOrder(
  {
    id: 'b18b25b7-0b4a-4467-bdb2-d5676595de86',
    state: 'running',
    runs: [
      createMockRun({
        id: 'e76ce911-d215-4dfa-ab09-fba0959ed8ba',
        state: 'started',
        started_at: '2025-10-23T20:00:01.400483Z',
        finished_at: null,
        error_type: null,
      }),
    ],
    last_activity: '2025-10-23T20:00:02.462210Z',
  }
);

/**
 * Sample work order with selected run
 */
export const mockSelectedWorkOrder: WorkOrderWithSelection =
  createMockWorkOrder({
    id: '7f0419b6-e35b-4b7c-8ddd-f1fbfa84cf2c',
    state: 'success',
    selected: true,
    runs: [
      createMockRun({
        id: 'd1f87a82-1052-4a51-b279-a6205adfa2e7',
        state: 'success',
        started_at: '2025-10-23T19:45:01.960858Z',
        finished_at: '2025-10-23T19:45:02.955735Z',
        selected: true,
      }),
    ],
    last_activity: '2025-10-23T19:45:03.123050Z',
  });

/**
 * Sample history list with various states
 */
export const mockHistoryList: WorkOrderWithSelection[] = [
  mockSuccessfulWorkOrder,
  mockFailedWorkOrder,
  mockCrashedWorkOrder,
  mockRunningWorkOrder,
];

/**
 * All possible run states for testing status pills
 */
export const allRunStates: RunState[] = [
  'available',
  'claimed',
  'started',
  'success',
  'failed',
  'crashed',
  'cancelled',
  'killed',
  'exception',
  'lost',
];

/**
 * Helper to create work orders for each run state
 * Work orders get a matching state where possible, otherwise "success"
 */
export function createWorkOrdersForAllStates(): WorkOrderWithSelection[] {
  return allRunStates.map((runState, index) => {
    // Map run states to work order states where they overlap
    const workOrderState: WorkOrder['state'] = (
      [
        'success',
        'failed',
        'killed',
        'exception',
        'crashed',
        'cancelled',
        'lost',
        'pending',
        'running',
        'rejected',
      ] as const
    ).includes(runState as any)
      ? (runState as WorkOrder['state'])
      : 'success';

    return createMockWorkOrder({
      id: `work-order-${index}`,
      state: workOrderState,
      runs: [
        createMockRun({
          id: `run-${index}`,
          state: runState,
        }),
      ],
    });
  });
}
