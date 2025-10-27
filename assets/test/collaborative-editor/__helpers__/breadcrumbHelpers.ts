/**
 * Breadcrumb Test Helpers
 *
 * Utilities for testing breadcrumb rendering logic, particularly the store-first
 * with props-fallback pattern used in CollaborativeEditor's BreadcrumbContent.
 *
 * These helpers were extracted from CollaborativeEditor.test.tsx to provide
 * reusable test utilities for breadcrumb-related functionality.
 *
 * Usage:
 *   const project = createMockProject({ name: "My Project" });
 *   const breadcrumbs = generateBreadcrumbStructure(projectId, projectName, workflowName);
 */

import type { ProjectContext } from '../../../js/collaborative-editor/types/sessionContext';

/**
 * Breadcrumb item type definition
 */
export interface BreadcrumbItem {
  type: 'link' | 'text';
  href?: string;
  text: string;
  icon?: string;
}

/**
 * Creates a mock ProjectContext for testing
 *
 * @param overrides - Optional overrides for default project values
 * @returns Mock project context
 *
 * @example
 * const project = createMockProject({
 *   id: "project-123",
 *   name: "Test Project"
 * });
 */
export function createMockProject(
  overrides: Partial<ProjectContext> = {}
): ProjectContext {
  return {
    id: 'project-123',
    name: 'Test Project',
    ...overrides,
  };
}

/**
 * Simulates the BreadcrumbContent component's data selection logic
 *
 * Returns the project data that would be used for rendering breadcrumbs,
 * following the store-first, props-fallback pattern.
 *
 * @param projectFromStore - Project data from session context store (or null)
 * @param projectIdFallback - Fallback project ID from props
 * @param projectNameFallback - Fallback project name from props
 * @returns Selected project ID and name for breadcrumbs
 *
 * @example
 * const { projectId, projectName } = selectBreadcrumbProjectData(
 *   storeProject,
 *   propsProjectId,
 *   propsProjectName
 * );
 */
export function selectBreadcrumbProjectData(
  projectFromStore: ProjectContext | null,
  projectIdFallback?: string,
  projectNameFallback?: string
): { projectId: string | undefined; projectName: string | undefined } {
  // This matches the logic from BreadcrumbContent:
  // const projectId = projectFromStore?.id ?? projectIdFallback;
  // const projectName = projectFromStore?.name ?? projectNameFallback;

  const projectId = projectFromStore?.id ?? projectIdFallback;
  const projectName = projectFromStore?.name ?? projectNameFallback;

  return { projectId, projectName };
}

/**
 * Generates breadcrumb URLs from a project ID
 *
 * @param projectId - The project ID
 * @returns Object containing project and workflows URLs
 *
 * @example
 * const urls = generateBreadcrumbUrls("project-123");
 * expect(urls.projectUrl).toBe("/projects/project-123/w");
 */
export function generateBreadcrumbUrls(projectId: string | undefined): {
  projectUrl: string;
  workflowsUrl: string;
} {
  return {
    projectUrl: `/projects/${projectId}/w`,
    workflowsUrl: `/projects/${projectId}/w`,
  };
}

/**
 * Generates the complete breadcrumb structure
 *
 * Creates the array of breadcrumb items that would be rendered in the UI,
 * matching the structure used by CollaborativeEditor's BreadcrumbContent.
 *
 * @param projectId - Project ID for URL generation
 * @param projectName - Project name for display
 * @param workflowName - Workflow name for display
 * @returns Array of breadcrumb items
 *
 * @example
 * const breadcrumbs = generateBreadcrumbStructure(
 *   "project-123",
 *   "My Project",
 *   "My Workflow"
 * );
 *
 * expect(breadcrumbs).toHaveLength(5);
 * expect(breadcrumbs[0].text).toBe("Home");
 */
export function generateBreadcrumbStructure(
  projectId: string | undefined,
  projectName: string | undefined,
  workflowName: string
): BreadcrumbItem[] {
  return [
    {
      type: 'link',
      href: '/',
      text: 'Home',
      icon: 'hero-home-mini',
    },
    {
      type: 'link',
      href: '/projects',
      text: 'Projects',
    },
    {
      type: 'link',
      href: `/projects/${projectId}/w`,
      text: projectName ?? '',
    },
    {
      type: 'link',
      href: `/projects/${projectId}/w`,
      text: 'Workflows',
    },
    {
      type: 'text',
      text: workflowName,
    },
  ];
}

/**
 * Tests the store-first, props-fallback pattern
 *
 * Helper function that encapsulates the common test pattern of verifying
 * that store data is preferred over props when both are available.
 *
 * @param projectFromStore - Project from store
 * @param projectIdFallback - Fallback project ID
 * @param projectNameFallback - Fallback project name
 * @returns Test result with assertions
 *
 * @example
 * testStoreFirstPattern(
 *   createMockProject({ id: "store-123", name: "Store Project" }),
 *   "fallback-456",
 *   "Fallback Project"
 * );
 */
export function testStoreFirstPattern(
  projectFromStore: ProjectContext | null,
  projectIdFallback: string,
  projectNameFallback: string
): void {
  const result = selectBreadcrumbProjectData(
    projectFromStore,
    projectIdFallback,
    projectNameFallback
  );

  if (projectFromStore) {
    // Store data should be used
    expect(result.projectId).toBe(projectFromStore.id);
    expect(result.projectName).toBe(projectFromStore.name);
    expect(result.projectId).not.toBe(projectIdFallback);
    expect(result.projectName).not.toBe(projectNameFallback);
  } else {
    // Fallback data should be used
    expect(result.projectId).toBe(projectIdFallback);
    expect(result.projectName).toBe(projectNameFallback);
  }
}

/**
 * Tests the props-fallback behavior when store is null
 *
 * @param projectIdFallback - Fallback project ID
 * @param projectNameFallback - Fallback project name
 *
 * @example
 * testPropsFallbackPattern("fallback-id", "Fallback Name");
 */
export function testPropsFallbackPattern(
  projectIdFallback?: string,
  projectNameFallback?: string
): void {
  const result = selectBreadcrumbProjectData(
    null,
    projectIdFallback,
    projectNameFallback
  );

  expect(result.projectId).toBe(projectIdFallback);
  expect(result.projectName).toBe(projectNameFallback);
}

/**
 * Verifies breadcrumb item properties
 *
 * Helper for asserting that a breadcrumb item has expected properties.
 *
 * @param breadcrumb - The breadcrumb item to verify
 * @param expected - Expected properties
 *
 * @example
 * const breadcrumbs = generateBreadcrumbStructure(...);
 * verifyBreadcrumbItem(breadcrumbs[0], {
 *   type: "link",
 *   href: "/",
 *   text: "Home",
 *   icon: "hero-home-mini"
 * });
 */
export function verifyBreadcrumbItem(
  breadcrumb: BreadcrumbItem,
  expected: Partial<BreadcrumbItem>
): void {
  if (expected.type !== undefined) {
    expect(breadcrumb.type).toBe(expected.type);
  }
  if (expected.href !== undefined) {
    expect(breadcrumb.href).toBe(expected.href);
  }
  if (expected.text !== undefined) {
    expect(breadcrumb.text).toBe(expected.text);
  }
  if (expected.icon !== undefined) {
    expect(breadcrumb.icon).toBe(expected.icon);
  }
}

/**
 * Verifies the complete breadcrumb structure
 *
 * Checks that all breadcrumb items are present and have expected properties.
 *
 * @param breadcrumbs - Array of breadcrumb items
 *
 * @example
 * const breadcrumbs = generateBreadcrumbStructure(
 *   "project-123",
 *   "My Project",
 *   "My Workflow"
 * );
 * verifyCompleteBreadcrumbStructure(breadcrumbs);
 */
export function verifyCompleteBreadcrumbStructure(
  breadcrumbs: BreadcrumbItem[]
): void {
  expect(breadcrumbs).toHaveLength(5);

  // Home
  verifyBreadcrumbItem(breadcrumbs[0], {
    type: 'link',
    href: '/',
    text: 'Home',
    icon: 'hero-home-mini',
  });

  // Projects
  verifyBreadcrumbItem(breadcrumbs[1], {
    type: 'link',
    href: '/projects',
    text: 'Projects',
  });

  // Project (should be a link)
  expect(breadcrumbs[2].type).toBe('link');
  expect(breadcrumbs[2].href).toContain('/projects/');

  // Workflows
  expect(breadcrumbs[3].type).toBe('link');
  expect(breadcrumbs[3].text).toBe('Workflows');

  // Workflow (should be text, not link)
  expect(breadcrumbs[4].type).toBe('text');
  expect(breadcrumbs[4].href).toBeUndefined();
}

/**
 * Creates a test scenario for breadcrumb rendering
 *
 * Factory function that creates common test scenarios for breadcrumb testing.
 *
 * @param scenario - The scenario type
 * @param customData - Optional custom data for the scenario
 * @returns Object with scenario data
 *
 * @example
 * const scenario = createBreadcrumbScenario("initial-load", {
 *   projectIdFallback: "prop-123",
 *   projectNameFallback: "Props Project"
 * });
 *
 * const { projectId, projectName } = selectBreadcrumbProjectData(
 *   scenario.projectFromStore,
 *   scenario.projectIdFallback,
 *   scenario.projectNameFallback
 * );
 */
export function createBreadcrumbScenario(
  scenario:
    | 'initial-load'
    | 'store-hydrated'
    | 'collaborative-update'
    | 'migration-phase'
    | 'ssr',
  customData?: {
    projectFromStore?: ProjectContext;
    projectIdFallback?: string;
    projectNameFallback?: string;
    workflowName?: string;
  }
): {
  projectFromStore: ProjectContext | null;
  projectIdFallback: string;
  projectNameFallback: string;
  workflowName: string;
  description: string;
} {
  const defaultWorkflowName = 'Test Workflow';

  switch (scenario) {
    case 'initial-load':
      // Simulates initial render where store hasn't loaded yet
      return {
        projectFromStore: null,
        projectIdFallback: customData?.projectIdFallback ?? 'prop-project-123',
        projectNameFallback:
          customData?.projectNameFallback ?? 'Props Project Name',
        workflowName: customData?.workflowName ?? defaultWorkflowName,
        description: 'Initial page load with props only (store not hydrated)',
      };

    case 'store-hydrated':
      // Simulates after store has loaded data from server
      return {
        projectFromStore:
          customData?.projectFromStore ??
          createMockProject({
            id: 'store-project-789',
            name: 'Store Hydrated Name',
          }),
        projectIdFallback: customData?.projectIdFallback ?? 'prop-project-123',
        projectNameFallback:
          customData?.projectNameFallback ?? 'Props Project Name',
        workflowName: customData?.workflowName ?? defaultWorkflowName,
        description: 'After store hydration (store data available)',
      };

    case 'collaborative-update':
      // Simulates a collaborative session where project name updates
      return {
        projectFromStore:
          customData?.projectFromStore ??
          createMockProject({
            id: 'collab-project-123',
            name: 'Initial Project Name',
          }),
        projectIdFallback: customData?.projectIdFallback ?? 'fallback',
        projectNameFallback: customData?.projectNameFallback ?? 'Fallback',
        workflowName: customData?.workflowName ?? 'Collaborative Workflow',
        description: 'Collaborative session with live updates',
      };

    case 'migration-phase':
      // During migration, both props and store may be available
      return {
        projectFromStore:
          customData?.projectFromStore ??
          createMockProject({
            id: 'new-store-id',
            name: 'New Store Name',
          }),
        projectIdFallback: customData?.projectIdFallback ?? 'old-prop-id',
        projectNameFallback: customData?.projectNameFallback ?? 'Old Prop Name',
        workflowName: customData?.workflowName ?? defaultWorkflowName,
        description: 'Migration phase with both props and store',
      };

    case 'ssr':
      // SSR scenario where store doesn't exist yet
      return {
        projectFromStore: null,
        projectIdFallback: customData?.projectIdFallback ?? 'ssr-project-123',
        projectNameFallback: customData?.projectNameFallback ?? 'SSR Project',
        workflowName: customData?.workflowName ?? defaultWorkflowName,
        description: 'Server-side render simulation (no store, props only)',
      };

    default:
      throw new Error(`Unknown scenario: ${scenario}`);
  }
}

/**
 * Tests edge cases for project data
 *
 * Helper for testing various edge cases like empty strings, special characters, etc.
 *
 * @param testCase - The edge case to test
 * @returns Test data for the edge case
 *
 * @example
 * const edgeCase = createEdgeCaseTestData("empty-string");
 * const result = selectBreadcrumbProjectData(
 *   edgeCase.projectFromStore,
 *   edgeCase.fallbackId,
 *   edgeCase.fallbackName
 * );
 */
export function createEdgeCaseTestData(
  testCase:
    | 'empty-string'
    | 'special-characters'
    | 'very-long-name'
    | 'null-values'
    | 'numeric-id'
): {
  projectFromStore: ProjectContext | null;
  fallbackId: string;
  fallbackName: string;
  expectedBehavior: string;
} {
  switch (testCase) {
    case 'empty-string':
      return {
        projectFromStore: createMockProject({
          id: 'project-123',
          name: '',
        }),
        fallbackId: 'fallback-id',
        fallbackName: 'Fallback Name',
        expectedBehavior:
          'Empty string from store should be used (not fallback)',
      };

    case 'special-characters':
      return {
        projectFromStore: createMockProject({
          id: 'project-123',
          name: 'Project <>&"\' Name',
        }),
        fallbackId: 'fallback-id',
        fallbackName: 'Fallback',
        expectedBehavior: 'Should preserve special characters',
      };

    case 'very-long-name':
      return {
        projectFromStore: createMockProject({
          id: 'project-123',
          name: 'A'.repeat(500),
        }),
        fallbackId: 'fallback-id',
        fallbackName: 'Fallback',
        expectedBehavior:
          'Should handle long names without truncation at this level',
      };

    case 'null-values':
      return {
        projectFromStore: { id: null as any, name: null as any },
        fallbackId: 'fallback-id',
        fallbackName: 'Fallback Name',
        expectedBehavior: 'Null should fallback to props (nullish coalescing)',
      };

    case 'numeric-id':
      return {
        projectFromStore: createMockProject({
          id: '12345',
          name: 'Numeric ID Project',
        }),
        fallbackId: 'fallback-id',
        fallbackName: 'Fallback',
        expectedBehavior: 'Should handle numeric string IDs',
      };

    default:
      throw new Error(`Unknown test case: ${testCase}`);
  }
}
