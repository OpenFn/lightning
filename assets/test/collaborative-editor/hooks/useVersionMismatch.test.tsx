/**
 * useVersionMismatch Hook Tests
 *
 * Tests the logic for detecting when a user is viewing the latest workflow
 * but a selected run was executed on an older version.
 */

import { renderHook } from '@testing-library/react';
import { describe, expect, test, vi } from 'vitest';

import { useVersionMismatch } from '../../../js/collaborative-editor/hooks/useVersionMismatch';

// Mock the dependency hooks
vi.mock('../../../js/collaborative-editor/hooks/useHistory', () => ({
  useHistory: vi.fn(),
}));

vi.mock('../../../js/collaborative-editor/hooks/useSessionContext', () => ({
  useLatestSnapshotLockVersion: vi.fn(),
  useVersions: vi.fn(() => []),
  useVersionsLoading: vi.fn(() => false),
  useVersionsError: vi.fn(() => null),
  useRequestVersions: vi.fn(() => vi.fn()),
}));

vi.mock('../../../js/collaborative-editor/hooks/useWorkflow', () => ({
  useWorkflowState: vi.fn(),
}));

import { useHistory } from '../../../js/collaborative-editor/hooks/useHistory';
import { useLatestSnapshotLockVersion } from '../../../js/collaborative-editor/hooks/useSessionContext';
import { useWorkflowState } from '../../../js/collaborative-editor/hooks/useWorkflow';

describe('useVersionMismatch', () => {
  test('returns mismatch when viewing latest and run used older version', () => {
    // Arrange
    const mockWorkflow = { id: 'wf-1', lock_version: 28 };
    const mockHistory = [
      {
        id: 'wo-1',
        version: 22, // Run executed on v22
        runs: [{ id: 'run-1', state: 'success' }],
      },
    ];

    vi.mocked(useWorkflowState).mockReturnValue(mockWorkflow);
    vi.mocked(useLatestSnapshotLockVersion).mockReturnValue(28);
    vi.mocked(useHistory).mockReturnValue(mockHistory);

    // Act
    const { result } = renderHook(() => useVersionMismatch('run-1'));

    // Assert
    expect(result.current).toEqual({
      runVersion: 22,
      currentVersion: 28,
    });
  });

  test('returns null when viewing snapshot that matches run version', () => {
    // Arrange: Viewing v22 snapshot, run also v22
    const mockWorkflow = { id: 'wf-1', lock_version: 22 };
    const mockHistory = [
      {
        id: 'wo-1',
        version: 22,
        runs: [{ id: 'run-1', state: 'success' }],
      },
    ];

    vi.mocked(useWorkflowState).mockReturnValue(mockWorkflow);
    vi.mocked(useLatestSnapshotLockVersion).mockReturnValue(28); // Latest is v28
    vi.mocked(useHistory).mockReturnValue(mockHistory);

    // Act
    const { result } = renderHook(() => useVersionMismatch('run-1'));

    // Assert: No mismatch because viewing v22 snapshot (not latest)
    expect(result.current).toBeNull();
  });

  test('returns null when no run is selected', () => {
    // Arrange
    const mockWorkflow = { id: 'wf-1', lock_version: 28 };
    const mockHistory = [
      {
        id: 'wo-1',
        version: 22,
        runs: [{ id: 'run-1', state: 'success' }],
      },
    ];

    vi.mocked(useWorkflowState).mockReturnValue(mockWorkflow);
    vi.mocked(useLatestSnapshotLockVersion).mockReturnValue(28);
    vi.mocked(useHistory).mockReturnValue(mockHistory);

    // Act: No run selected
    const { result } = renderHook(() => useVersionMismatch(null));

    // Assert
    expect(result.current).toBeNull();
  });

  test('returns null when workflow is null', () => {
    // Arrange
    const mockHistory = [
      {
        id: 'wo-1',
        version: 22,
        runs: [{ id: 'run-1', state: 'success' }],
      },
    ];

    vi.mocked(useWorkflowState).mockReturnValue(null);
    vi.mocked(useLatestSnapshotLockVersion).mockReturnValue(28);
    vi.mocked(useHistory).mockReturnValue(mockHistory);

    // Act
    const { result } = renderHook(() => useVersionMismatch('run-1'));

    // Assert
    expect(result.current).toBeNull();
  });

  test('returns null when latest snapshot version is null', () => {
    // Arrange
    const mockWorkflow = { id: 'wf-1', lock_version: 28 };
    const mockHistory = [
      {
        id: 'wo-1',
        version: 22,
        runs: [{ id: 'run-1', state: 'success' }],
      },
    ];

    vi.mocked(useWorkflowState).mockReturnValue(mockWorkflow);
    vi.mocked(useLatestSnapshotLockVersion).mockReturnValue(null);
    vi.mocked(useHistory).mockReturnValue(mockHistory);

    // Act
    const { result } = renderHook(() => useVersionMismatch('run-1'));

    // Assert
    expect(result.current).toBeNull();
  });

  test('returns null when selected run is not found in history', () => {
    // Arrange
    const mockWorkflow = { id: 'wf-1', lock_version: 28 };
    const mockHistory = [
      {
        id: 'wo-1',
        version: 22,
        runs: [{ id: 'run-1', state: 'success' }],
      },
    ];

    vi.mocked(useWorkflowState).mockReturnValue(mockWorkflow);
    vi.mocked(useLatestSnapshotLockVersion).mockReturnValue(28);
    vi.mocked(useHistory).mockReturnValue(mockHistory);

    // Act: Looking for non-existent run
    const { result } = renderHook(() => useVersionMismatch('run-999'));

    // Assert
    expect(result.current).toBeNull();
  });

  test('returns mismatch when versions differ even by small amount', () => {
    // Arrange: v29 vs v30 (still a mismatch)
    const mockWorkflow = { id: 'wf-1', lock_version: 30 };
    const mockHistory = [
      {
        id: 'wo-1',
        version: 29,
        runs: [{ id: 'run-1', state: 'success' }],
      },
    ];

    vi.mocked(useWorkflowState).mockReturnValue(mockWorkflow);
    vi.mocked(useLatestSnapshotLockVersion).mockReturnValue(30);
    vi.mocked(useHistory).mockReturnValue(mockHistory);

    // Act
    const { result } = renderHook(() => useVersionMismatch('run-1'));

    // Assert
    expect(result.current).toEqual({
      runVersion: 29,
      currentVersion: 30,
    });
  });

  test('returns null when viewing latest and run also used latest version', () => {
    // Arrange: Both at v28
    const mockWorkflow = { id: 'wf-1', lock_version: 28 };
    const mockHistory = [
      {
        id: 'wo-1',
        version: 28, // Same version
        runs: [{ id: 'run-1', state: 'success' }],
      },
    ];

    vi.mocked(useWorkflowState).mockReturnValue(mockWorkflow);
    vi.mocked(useLatestSnapshotLockVersion).mockReturnValue(28);
    vi.mocked(useHistory).mockReturnValue(mockHistory);

    // Act
    const { result } = renderHook(() => useVersionMismatch('run-1'));

    // Assert: No mismatch when versions match
    expect(result.current).toBeNull();
  });
});
