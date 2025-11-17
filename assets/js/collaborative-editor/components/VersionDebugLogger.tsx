/**
 * Version Debug Logger
 *
 * Debug component that logs version information to console
 * to help diagnose sync issues between Y.Doc and database.
 *
 * Logs:
 * - Y.Doc workflow lock_version (from WorkflowStore)
 * - Database latest lock_version (from SessionContextStore)
 * - Sync status (isSynced, isConnected)
 * - Job/Trigger/Edge counts to verify data completeness
 * - Color coding: green if versions match, red if mismatch
 */

import { useEffect } from 'react';

import { useSession } from '../hooks/useSession';
import {
  useLatestSnapshotLockVersion,
  useSessionContextLoading,
} from '../hooks/useSessionContext';
import { useWorkflowState } from '../hooks/useWorkflow';

/**
 * Logs version debug information to console with beautiful formatting
 */
export function logVersionDebug(debugInfo: {
  ydocVersion: number | null;
  dbVersion: number | null;
  isConnected: boolean;
  isSynced: boolean;
  sessionContextLoading: boolean;
  jobsCount: number;
  triggersCount: number;
  edgesCount: number;
}) {
  const {
    ydocVersion,
    dbVersion,
    isConnected,
    isSynced,
    sessionContextLoading,
    jobsCount,
    triggersCount,
    edgesCount,
  } = debugInfo;

  const isStale =
    ydocVersion !== null && dbVersion !== null && ydocVersion < dbVersion;

  const versionsMatch =
    ydocVersion !== null && dbVersion !== null && ydocVersion === dbVersion;

  // Styles
  const headerStyle = 'color: #FFC107; font-weight: bold; font-size: 14px;';
  const greenStyle = 'color: #4CAF50; font-weight: bold;';
  const redStyle = 'color: #F44336; font-weight: bold;';
  const yellowStyle = 'color: #FFC107; font-weight: bold;';
  const grayStyle = 'color: #9E9E9E;';
  const resetStyle = '';

  console.log('%c🔍 Version Debug', headerStyle);
  console.log('%c━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', grayStyle);

  // Lock Versions
  const versionStyle = versionsMatch
    ? greenStyle
    : isStale
      ? redStyle
      : yellowStyle;
  console.log(
    `%cY.Doc Lock Version: %c${ydocVersion ?? 'null'}`,
    grayStyle,
    versionStyle
  );
  console.log(
    `%cDB Lock Version:    %c${dbVersion ?? 'null'}`,
    grayStyle,
    versionStyle
  );

  console.log('%c━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', grayStyle);

  // Sync Status
  console.log(
    `%cConnected:  %c${isConnected ? '✓' : '✗'}`,
    grayStyle,
    isConnected ? greenStyle : redStyle
  );
  console.log(
    `%cSynced:     %c${isSynced ? '✓' : '✗'}`,
    grayStyle,
    isSynced ? greenStyle : redStyle
  );
  console.log(
    `%cContext:    %c${sessionContextLoading ? 'loading...' : 'loaded'}`,
    grayStyle,
    sessionContextLoading ? yellowStyle : greenStyle
  );

  console.log('%c━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', grayStyle);

  // Data Counts
  console.log(`%cJobs:       %c${jobsCount}`, grayStyle, resetStyle);
  console.log(`%cTriggers:   %c${triggersCount}`, grayStyle, resetStyle);
  console.log(`%cEdges:      %c${edgesCount}`, grayStyle, resetStyle);

  // Auto-reset indicator
  if (isStale && isSynced) {
    console.log('%c━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', grayStyle);
    console.log(
      '%c⚡ Auto-reset will trigger',
      'color: #FF9800; font-weight: bold;'
    );
  }

  console.log('%c━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n', grayStyle);
}

export function VersionDebugLogger() {
  const session = useSession();
  const workflow = useWorkflowState(state => state.workflow);
  const jobs = useWorkflowState(state => state.jobs);
  const triggers = useWorkflowState(state => state.triggers);
  const edges = useWorkflowState(state => state.edges);
  const sessionContextLoading = useSessionContextLoading();
  const latestSnapshotLockVersion = useLatestSnapshotLockVersion();

  const ydocVersion = workflow?.lock_version ?? null;
  const dbVersion = latestSnapshotLockVersion;

  // Log to console whenever state changes
  useEffect(() => {
    logVersionDebug({
      ydocVersion,
      dbVersion,
      isConnected: session.isConnected,
      isSynced: session.isSynced,
      sessionContextLoading,
      jobsCount: jobs.length,
      triggersCount: triggers.length,
      edgesCount: edges.length,
    });
  }, [
    ydocVersion,
    dbVersion,
    session.isConnected,
    session.isSynced,
    sessionContextLoading,
    jobs.length,
    triggers.length,
    edges.length,
  ]);

  return null;
}
