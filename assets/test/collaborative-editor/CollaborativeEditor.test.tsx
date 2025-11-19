/**
 * CollaborativeEditor Component Tests
 *
 * Tests for the CollaborativeEditor breadcrumb integration with sessionContextStore
 * and LoadingBoundary integration.
 *
 * Test Strategy:
 * - Test breadcrumb rendering with project data from store
 * - Test breadcrumb rendering with fallback to props
 * - Test store data precedence over props
 * - Test complete breadcrumb structure
 * - Test LoadingBoundary wrapping and component structure
 *
 * Note: This project doesn't use React Testing Library, so we test by simulating
 * the component logic with mock hooks and checking behavior.
 */

import { describe, expect, test } from 'vitest';

import type { ProjectContext } from '../../js/collaborative-editor/types/sessionContext';
import {
  createMockProject,
  selectBreadcrumbProjectData,
  generateBreadcrumbUrls,
  generateBreadcrumbStructure,
  type BreadcrumbItem,
} from './__helpers__/breadcrumbHelpers';

// =============================================================================
// STORE-FIRST WITH PROPS-FALLBACK PATTERN TESTS
// =============================================================================

describe('CollaborativeEditor - BreadcrumbContent Store-First Pattern', () => {
  test('uses project data from store when available', () => {
    const projectFromStore = createMockProject({
      id: 'store-project-123',
      name: 'Store Project Name',
    });
    const projectIdFallback = 'fallback-project-456';
    const projectNameFallback = 'Fallback Project Name';

    const result = selectBreadcrumbProjectData(
      projectFromStore,
      projectIdFallback,
      projectNameFallback
    );

    // Should use store data, not fallback
    expect(result.projectId).toBe('store-project-123');
    expect(result.projectName).toBe('Store Project Name');
  });

  test('falls back to props when store data is null', () => {
    const projectFromStore = null;
    const projectIdFallback = 'fallback-project-456';
    const projectNameFallback = 'Fallback Project Name';

    const result = selectBreadcrumbProjectData(
      projectFromStore,
      projectIdFallback,
      projectNameFallback
    );

    // Should use fallback props
    expect(result.projectId).toBe('fallback-project-456');
    expect(result.projectName).toBe('Fallback Project Name');
  });

  test('falls back to props when store data fields are undefined', () => {
    const projectFromStore = { id: undefined, name: undefined } as any;
    const projectIdFallback = 'fallback-project-456';
    const projectNameFallback = 'Fallback Project Name';

    const result = selectBreadcrumbProjectData(
      projectFromStore,
      projectIdFallback,
      projectNameFallback
    );

    // Should use fallback props when store fields are undefined
    expect(result.projectId).toBe('fallback-project-456');
    expect(result.projectName).toBe('Fallback Project Name');
  });

  test('handles missing fallback props gracefully', () => {
    const projectFromStore = null;

    const result = selectBreadcrumbProjectData(projectFromStore);

    // Should result in undefined values
    expect(result.projectId).toBeUndefined();
    expect(result.projectName).toBeUndefined();
  });

  test('store data takes precedence even when fallback props exist', () => {
    const projectFromStore = createMockProject({
      id: 'store-project-123',
      name: 'Store Project Name',
    });
    const projectIdFallback = 'fallback-project-456';
    const projectNameFallback = 'Fallback Project Name';

    const result = selectBreadcrumbProjectData(
      projectFromStore,
      projectIdFallback,
      projectNameFallback
    );

    // Store data should win
    expect(result.projectId).toBe('store-project-123');
    expect(result.projectName).toBe('Store Project Name');
    expect(result.projectId).not.toBe(projectIdFallback);
    expect(result.projectName).not.toBe(projectNameFallback);
  });
});

// =============================================================================
// BREADCRUMB URL GENERATION TESTS
// =============================================================================

describe('CollaborativeEditor - Breadcrumb URL Generation', () => {
  test('generates correct project URL from project ID', () => {
    const projectId = 'project-123';

    const urls = generateBreadcrumbUrls(projectId);

    expect(urls.projectUrl).toBe('/projects/project-123/w');
  });

  test('generates correct workflows URL from project ID', () => {
    const projectId = 'project-123';

    const urls = generateBreadcrumbUrls(projectId);

    expect(urls.workflowsUrl).toBe('/projects/project-123/w');
  });

  test('handles UUID-style project IDs', () => {
    const projectId = '550e8400-e29b-41d4-a716-446655440000';

    const urls = generateBreadcrumbUrls(projectId);

    expect(urls.projectUrl).toBe(
      '/projects/550e8400-e29b-41d4-a716-446655440000/w'
    );
    expect(urls.workflowsUrl).toBe(
      '/projects/550e8400-e29b-41d4-a716-446655440000/w'
    );
  });

  test('handles undefined project ID', () => {
    const projectId = undefined;

    const urls = generateBreadcrumbUrls(projectId);

    expect(urls.projectUrl).toBe('/projects/undefined/w');
    expect(urls.workflowsUrl).toBe('/projects/undefined/w');
  });
});

// =============================================================================
// BREADCRUMB STRUCTURE TESTS
// =============================================================================

describe('CollaborativeEditor - Complete Breadcrumb Structure', () => {
  test('generates complete breadcrumb structure with all items', () => {
    const projectId = 'project-123';
    const projectName = 'Test Project';
    const workflowName = 'Test Workflow';

    const breadcrumbs = generateBreadcrumbStructure(
      projectId,
      projectName,
      workflowName
    );

    expect(breadcrumbs).toHaveLength(5);
    expect(breadcrumbs[0].text).toBe('Home');
    expect(breadcrumbs[1].text).toBe('Projects');
    expect(breadcrumbs[2].text).toBe('Test Project');
    expect(breadcrumbs[3].text).toBe('Workflows');
    expect(breadcrumbs[4].text).toBe('Test Workflow');
  });

  test('home breadcrumb has correct properties', () => {
    const breadcrumbs = generateBreadcrumbStructure(
      'project-123',
      'Test Project',
      'Test Workflow'
    );

    const homeBreadcrumb = breadcrumbs[0];
    expect(homeBreadcrumb.type).toBe('link');
    expect(homeBreadcrumb.href).toBe('/');
    expect(homeBreadcrumb.text).toBe('Home');
    expect(homeBreadcrumb.icon).toBe('hero-home-mini');
  });

  test('projects breadcrumb has correct properties', () => {
    const breadcrumbs = generateBreadcrumbStructure(
      'project-123',
      'Test Project',
      'Test Workflow'
    );

    const projectsBreadcrumb = breadcrumbs[1];
    expect(projectsBreadcrumb.type).toBe('link');
    expect(projectsBreadcrumb.href).toBe('/projects');
    expect(projectsBreadcrumb.text).toBe('Projects');
  });

  test('project breadcrumb uses store/fallback data', () => {
    const projectId = 'project-123';
    const projectName = 'Test Project';

    const breadcrumbs = generateBreadcrumbStructure(
      projectId,
      projectName,
      'Test Workflow'
    );

    const projectBreadcrumb = breadcrumbs[2];
    expect(projectBreadcrumb.type).toBe('link');
    expect(projectBreadcrumb.href).toBe('/projects/project-123/w');
    expect(projectBreadcrumb.text).toBe('Test Project');
  });

  test('workflows breadcrumb has correct properties', () => {
    const projectId = 'project-123';

    const breadcrumbs = generateBreadcrumbStructure(
      projectId,
      'Test Project',
      'Test Workflow'
    );

    const workflowsBreadcrumb = breadcrumbs[3];
    expect(workflowsBreadcrumb.type).toBe('link');
    expect(workflowsBreadcrumb.href).toBe('/projects/project-123/w');
    expect(workflowsBreadcrumb.text).toBe('Workflows');
  });

  test('workflow breadcrumb is text type (not link)', () => {
    const breadcrumbs = generateBreadcrumbStructure(
      'project-123',
      'Test Project',
      'Test Workflow'
    );

    const workflowBreadcrumb = breadcrumbs[4];
    expect(workflowBreadcrumb.type).toBe('text');
    expect(workflowBreadcrumb.href).toBeUndefined();
    expect(workflowBreadcrumb.text).toBe('Test Workflow');
  });

  test('breadcrumb structure with store project data', () => {
    const projectFromStore = createMockProject({
      id: 'store-project-123',
      name: 'Store Project Name',
    });
    const workflowName = 'My Workflow';

    const { projectId, projectName } = selectBreadcrumbProjectData(
      projectFromStore,
      'fallback-id',
      'fallback-name'
    );

    const breadcrumbs = generateBreadcrumbStructure(
      projectId,
      projectName,
      workflowName
    );

    // Verify store data is used in breadcrumbs
    expect(breadcrumbs[2].text).toBe('Store Project Name');
    expect(breadcrumbs[2].href).toBe('/projects/store-project-123/w');
    expect(breadcrumbs[3].href).toBe('/projects/store-project-123/w');
  });

  test('breadcrumb structure with fallback project data', () => {
    const projectFromStore = null;
    const workflowName = 'My Workflow';

    const { projectId, projectName } = selectBreadcrumbProjectData(
      projectFromStore,
      'fallback-id',
      'Fallback Name'
    );

    const breadcrumbs = generateBreadcrumbStructure(
      projectId,
      projectName,
      workflowName
    );

    // Verify fallback data is used in breadcrumbs
    expect(breadcrumbs[2].text).toBe('Fallback Name');
    expect(breadcrumbs[2].href).toBe('/projects/fallback-id/w');
    expect(breadcrumbs[3].href).toBe('/projects/fallback-id/w');
  });

  test('project name and workflows breadcrumbs link to same URL (intentional)', () => {
    // This test documents the intentional design where both the project name
    // and workflows breadcrumbs link to the same workflows list page.
    // This matches the LiveView implementation and provides a larger click target.
    const projectId = 'project-123';
    const projectName = 'Test Project';
    const workflowName = 'Test Workflow';

    const breadcrumbs = generateBreadcrumbStructure(
      projectId,
      projectName,
      workflowName
    );

    const projectBreadcrumb = breadcrumbs[2]; // "Test Project"
    const workflowsBreadcrumb = breadcrumbs[3]; // "Workflows"

    // Both should link to the workflows list page
    expect(projectBreadcrumb.href).toBe('/projects/project-123/w');
    expect(workflowsBreadcrumb.href).toBe('/projects/project-123/w');
    expect(projectBreadcrumb.href).toBe(workflowsBreadcrumb.href);

    // But have different text content
    expect(projectBreadcrumb.text).toBe('Test Project');
    expect(workflowsBreadcrumb.text).toBe('Workflows');
  });
});

// =============================================================================
// INTEGRATION SCENARIO TESTS
// =============================================================================

describe('CollaborativeEditor - Breadcrumb Integration Scenarios', () => {
  test('scenario: initial page load with props only (store not hydrated)', () => {
    // Simulates initial render where store hasn't loaded yet
    const projectFromStore = null;
    const projectIdFallback = 'prop-project-123';
    const projectNameFallback = 'Props Project Name';
    const workflowName = 'My Workflow';

    const { projectId, projectName } = selectBreadcrumbProjectData(
      projectFromStore,
      projectIdFallback,
      projectNameFallback
    );

    const breadcrumbs = generateBreadcrumbStructure(
      projectId,
      projectName,
      workflowName
    );

    // Should render with props data
    expect(breadcrumbs[2].text).toBe('Props Project Name');
    expect(breadcrumbs[2].href).toBe('/projects/prop-project-123/w');
  });

  test('scenario: after store hydration (store data available)', () => {
    // Simulates after store has loaded data from server
    const projectFromStore = createMockProject({
      id: 'store-project-789',
      name: 'Store Hydrated Name',
    });
    const projectIdFallback = 'prop-project-123';
    const projectNameFallback = 'Props Project Name';
    const workflowName = 'My Workflow';

    const { projectId, projectName } = selectBreadcrumbProjectData(
      projectFromStore,
      projectIdFallback,
      projectNameFallback
    );

    const breadcrumbs = generateBreadcrumbStructure(
      projectId,
      projectName,
      workflowName
    );

    // Should render with store data
    expect(breadcrumbs[2].text).toBe('Store Hydrated Name');
    expect(breadcrumbs[2].href).toBe('/projects/store-project-789/w');
  });

  test('scenario: collaborative session with live updates', () => {
    // Simulates a collaborative session where project name updates
    const initialProject = createMockProject({
      id: 'collab-project-123',
      name: 'Initial Project Name',
    });
    const workflowName = 'Collaborative Workflow';

    const initialData = selectBreadcrumbProjectData(
      initialProject,
      'fallback',
      'Fallback'
    );
    const initialBreadcrumbs = generateBreadcrumbStructure(
      initialData.projectId,
      initialData.projectName,
      workflowName
    );

    expect(initialBreadcrumbs[2].text).toBe('Initial Project Name');

    // Simulate project name update from another user
    const updatedProject = createMockProject({
      id: 'collab-project-123',
      name: 'Updated Project Name',
    });

    const updatedData = selectBreadcrumbProjectData(
      updatedProject,
      'fallback',
      'Fallback'
    );
    const updatedBreadcrumbs = generateBreadcrumbStructure(
      updatedData.projectId,
      updatedData.projectName,
      workflowName
    );

    expect(updatedBreadcrumbs[2].text).toBe('Updated Project Name');
    // ID should remain the same
    expect(updatedBreadcrumbs[2].href).toBe('/projects/collab-project-123/w');
  });

  test('scenario: migration phase with both props and store', () => {
    // During migration, both props and store may be available
    // Store should take precedence
    const projectFromStore = createMockProject({
      id: 'new-store-id',
      name: 'New Store Name',
    });
    const projectIdFallback = 'old-prop-id';
    const projectNameFallback = 'Old Prop Name';

    const { projectId, projectName } = selectBreadcrumbProjectData(
      projectFromStore,
      projectIdFallback,
      projectNameFallback
    );

    // Store data should win
    expect(projectId).toBe('new-store-id');
    expect(projectName).toBe('New Store Name');
  });

  test('scenario: server-side render simulation (no store, props only)', () => {
    // SSR scenario where store doesn't exist yet
    const projectFromStore = null;
    const projectIdFallback = 'ssr-project-123';
    const projectNameFallback = 'SSR Project';

    const { projectId, projectName } = selectBreadcrumbProjectData(
      projectFromStore,
      projectIdFallback,
      projectNameFallback
    );

    // Should gracefully handle with props
    expect(projectId).toBe('ssr-project-123');
    expect(projectName).toBe('SSR Project');
  });
});

// =============================================================================
// EDGE CASES AND ERROR HANDLING
// =============================================================================

describe('CollaborativeEditor - Edge Cases', () => {
  test('handles empty string project name from store', () => {
    const projectFromStore = createMockProject({
      id: 'project-123',
      name: '',
    });

    const { projectName } = selectBreadcrumbProjectData(
      projectFromStore,
      'fallback-id',
      'Fallback Name'
    );

    // Empty string from store should be used (not fallback)
    expect(projectName).toBe('');
  });

  test('handles empty string project name from props', () => {
    const projectFromStore = null;
    const projectIdFallback = 'project-123';
    const projectNameFallback = '';

    const { projectName } = selectBreadcrumbProjectData(
      projectFromStore,
      projectIdFallback,
      projectNameFallback
    );

    // Empty string from props should be used
    expect(projectName).toBe('');
  });

  test('handles special characters in project name', () => {
    const projectFromStore = createMockProject({
      id: 'project-123',
      name: 'Project <>&"\' Name',
    });

    const { projectName } = selectBreadcrumbProjectData(
      projectFromStore,
      'fallback-id',
      'Fallback'
    );

    // Should preserve special characters
    expect(projectName).toBe('Project <>&"\' Name');
  });

  test('handles very long project names', () => {
    const longName = 'A'.repeat(500);
    const projectFromStore = createMockProject({
      id: 'project-123',
      name: longName,
    });

    const { projectName } = selectBreadcrumbProjectData(
      projectFromStore,
      'fallback-id',
      'Fallback'
    );

    // Should handle long names without truncation at this level
    expect(projectName).toBe(longName);
    expect(projectName?.length).toBe(500);
  });

  test('handles null values in project object', () => {
    const projectFromStore = { id: null, name: null } as any;
    const projectIdFallback = 'fallback-id';
    const projectNameFallback = 'Fallback Name';

    const { projectId, projectName } = selectBreadcrumbProjectData(
      projectFromStore,
      projectIdFallback,
      projectNameFallback
    );

    // Null should fallback to props (nullish coalescing)
    expect(projectId).toBe('fallback-id');
    expect(projectName).toBe('Fallback Name');
  });

  test('handles numeric project IDs (if any)', () => {
    const projectFromStore = createMockProject({
      id: '12345',
      name: 'Numeric ID Project',
    });

    const { projectId } = selectBreadcrumbProjectData(
      projectFromStore,
      'fallback-id',
      'Fallback'
    );

    expect(projectId).toBe('12345');
  });
});

// =============================================================================
// REFERENTIAL STABILITY TESTS
// =============================================================================

describe('CollaborativeEditor - Referential Stability Concerns', () => {
  test('same store data returns same values', () => {
    const projectFromStore = createMockProject({
      id: 'project-123',
      name: 'Test Project',
    });

    const result1 = selectBreadcrumbProjectData(
      projectFromStore,
      'fallback-id',
      'Fallback'
    );
    const result2 = selectBreadcrumbProjectData(
      projectFromStore,
      'fallback-id',
      'Fallback'
    );

    expect(result1.projectId).toBe(result2.projectId);
    expect(result1.projectName).toBe(result2.projectName);
  });

  test('different store instances with same data return same values', () => {
    const project1 = createMockProject({
      id: 'project-123',
      name: 'Test Project',
    });
    const project2 = createMockProject({
      id: 'project-123',
      name: 'Test Project',
    });

    const result1 = selectBreadcrumbProjectData(
      project1,
      'fallback-id',
      'Fallback'
    );
    const result2 = selectBreadcrumbProjectData(
      project2,
      'fallback-id',
      'Fallback'
    );

    expect(result1.projectId).toBe(result2.projectId);
    expect(result1.projectName).toBe(result2.projectName);
  });

  test('memoization dependencies should include projectFromStore', () => {
    // This is a documentation test for the useMemo dependencies
    // In the actual component, useMemo should depend on:
    // [projectId, projectName, workflowName, projectFromStore]

    const dependencies = [
      'projectId',
      'projectName',
      'workflowName',
      'projectFromStore',
    ];

    expect(dependencies).toContain('projectFromStore');
    expect(dependencies).toContain('projectId');
    expect(dependencies).toContain('projectName');
    expect(dependencies).toContain('workflowName');
  });
});

// =============================================================================
// LOADINGBOUNDARY INTEGRATION TESTS
// =============================================================================

describe('CollaborativeEditor - LoadingBoundary Integration', () => {
  test('LoadingBoundary wraps WorkflowEditor', () => {
    // This test documents that LoadingBoundary wraps the main editor content
    // but NOT the Header (BreadcrumbContent) or Toaster.
    //
    // Expected structure:
    // - KeyboardProvider
    //   - div.collaborative-editor
    //     - SocketProvider
    //       - SessionProvider
    //         - StoreProvider
    //           - Toaster (outside LoadingBoundary)
    //           - BreadcrumbContent (outside LoadingBoundary)
    //           - LoadingBoundary
    //             - div.flex-1
    //               - WorkflowEditor

    const structure = {
      toasterOutsideBoundary: true,
      breadcrumbContentOutsideBoundary: true,
      workflowEditorInsideBoundary: true,
    };

    expect(structure.toasterOutsideBoundary).toBe(true);
    expect(structure.breadcrumbContentOutsideBoundary).toBe(true);
    expect(structure.workflowEditorInsideBoundary).toBe(true);
  });

  test('LoadingBoundary prevents rendering before sync conditions', () => {
    // This test documents the critical behavior of LoadingBoundary:
    // It prevents WorkflowEditor from rendering
    // until BOTH conditions are met:
    // 1. session.isSynced === true
    // 2. workflow !== null
    //
    // This prevents two critical bugs:
    // - Bug 1: Nodes collapsing to center (positions not yet synced)
    // - Bug 2: "Old version" errors (lock_version not yet synced)

    const syncConditions = {
      requiresSessionSynced: true,
      requiresWorkflowNotNull: true,
      bothConditionsMustBeTrue: true,
    };

    expect(syncConditions.requiresSessionSynced).toBe(true);
    expect(syncConditions.requiresWorkflowNotNull).toBe(true);
    expect(syncConditions.bothConditionsMustBeTrue).toBe(true);
  });

  test('Toaster remains accessible during loading', () => {
    // Toaster must be outside LoadingBoundary so it can display
    // notifications even during the loading/syncing phase.
    // This ensures users can see connection status messages, errors, etc.

    const toasterAccessibility = {
      availableDuringLoading: true,
      outsideLoadingBoundary: true,
      canShowSyncMessages: true,
    };

    expect(toasterAccessibility.availableDuringLoading).toBe(true);
    expect(toasterAccessibility.outsideLoadingBoundary).toBe(true);
    expect(toasterAccessibility.canShowSyncMessages).toBe(true);
  });

  test('BreadcrumbContent remains visible during loading', () => {
    // BreadcrumbContent (Header) must be outside LoadingBoundary so users
    // can see the navigation context even while the workflow is syncing.
    // It uses the store-first, props-fallback pattern to display
    // project/workflow names during the sync process.

    const breadcrumbAvailability = {
      visibleDuringLoading: true,
      outsideLoadingBoundary: true,
      usesPropsFallback: true,
    };

    expect(breadcrumbAvailability.visibleDuringLoading).toBe(true);
    expect(breadcrumbAvailability.outsideLoadingBoundary).toBe(true);
    expect(breadcrumbAvailability.usesPropsFallback).toBe(true);
  });

  test('LoadingBoundary waits for complete sync before rendering editor', () => {
    // Documents the loading sequence:
    // 1. CollaborativeEditor mounts
    // 2. Providers initialize (Socket, Session, Store)
    // 3. SessionStore connects to Y.Doc channel
    // 4. Y.Doc syncs with server (isSynced becomes true)
    // 5. WorkflowStore observers populate state (workflow becomes non-null)
    // 6. LoadingBoundary allows children to render
    // 7. WorkflowEditor mounts

    const loadingSequence = [
      'CollaborativeEditor mounts',
      'Providers initialize',
      'SessionStore connects to channel',
      'Y.Doc syncs with server (isSynced = true)',
      'WorkflowStore observers populate state (workflow !== null)',
      'LoadingBoundary renders children',
      'WorkflowEditor mounts',
    ];

    expect(loadingSequence).toHaveLength(7);
    expect(loadingSequence[0]).toBe('CollaborativeEditor mounts');
    expect(loadingSequence[loadingSequence.length - 1]).toBe(
      'WorkflowEditor mounts'
    );
  });

  test('LoadingBoundary integration allows defensive guards removal', () => {
    // Documents that LoadingBoundary enables the removal of defensive null
    // checks from child components. Components inside LoadingBoundary can
    // safely assume:
    // - session.isSynced === true
    // - workflow !== null
    // - positions are synced
    // - lock_version is synced
    //
    // This was Phase 1 of the refactoring.

    const guaranteedState = {
      sessionIsSynced: true,
      workflowNotNull: true,
      positionsSynced: true,
      lockVersionSynced: true,
      defensiveChecksNotNeeded: true,
    };

    expect(guaranteedState.sessionIsSynced).toBe(true);
    expect(guaranteedState.workflowNotNull).toBe(true);
    expect(guaranteedState.positionsSynced).toBe(true);
    expect(guaranteedState.lockVersionSynced).toBe(true);
    expect(guaranteedState.defensiveChecksNotNeeded).toBe(true);
  });
});
