/**
 * Test fixtures for adaptor data
 *
 * Provides consistent test data that matches the Zod schemas
 * for testing adaptor store functionality.
 */

import { sortAdaptors } from '#/collaborative-editor/stores/createAdaptorStore';

import type {
  Adaptor,
  AdaptorsList,
} from '../../../js/collaborative-editor/types/adaptor';

/**
 * Sample adaptor versions for testing
 */
export const mockAdaptorVersions: string[] = [
  '2.1.0',
  '2.0.5',
  '2.0.0',
  '1.9.5',
];

/**
 * Sample single adaptor for testing
 */
export const mockAdaptor: Adaptor = {
  name: '@openfn/language-http',
  versions: mockAdaptorVersions,
  repository: 'https://github.com/OpenFn/adaptors/tree/main/packages/http',
  latest_version: '2.1.0',
  icon_urls: { square: null, rectangle: null },
};

/**
 * Additional adaptors for comprehensive testing
 */
export const mockAdaptorDhis2: Adaptor = {
  name: '@openfn/language-dhis2',
  versions: ['4.2.1', '4.2.0', '4.1.3'],
  repository: 'https://github.com/OpenFn/adaptors/tree/main/packages/dhis2',
  latest_version: '4.2.1',
  icon_urls: { square: null, rectangle: null },
};

export const mockAdaptorSalesforce: Adaptor = {
  name: '@openfn/language-salesforce',
  versions: ['3.5.2', '3.5.1', '3.5.0', '3.4.9'],
  repository:
    'https://github.com/OpenFn/adaptors/tree/main/packages/salesforce',
  latest_version: '3.5.2',
  icon_urls: { square: null, rectangle: null },
};

export const mockAdaptorGmail: Adaptor = {
  name: '@openfn/language-gmail',
  versions: ['1.2.0', '1.1.0', '1.0.0'],
  repository: 'https://github.com/OpenFn/adaptors/tree/main/packages/gmail',
  latest_version: '1.2.0',
  icon_urls: { square: null, rectangle: null },
};

export const mockAdaptorCommon: Adaptor = {
  name: '@openfn/language-common',
  versions: ['2.0.0', '1.15.0', '1.14.0'],
  repository: 'https://github.com/OpenFn/adaptors/tree/main/packages/common',
  latest_version: '2.0.0',
  icon_urls: { square: null, rectangle: null },
};

/**
 * Complete adaptors list for testing
 */
export const mockAdaptorsList: AdaptorsList = sortAdaptors([
  mockAdaptor,
  mockAdaptorDhis2,
  mockAdaptorSalesforce,
]);

/**
 * Empty adaptors list for testing initial state
 */
export const emptyAdaptorsList: AdaptorsList = [];

/**
 * Invalid data samples for testing validation errors
 */
export const invalidAdaptorData = {
  missingName: {
    // name missing
    versions: mockAdaptorVersions,
    repository: 'https://github.com/test',
    latest_version: '1.0.0',
  },

  invalidVersions: {
    name: '@openfn/language-test',
    versions: 'invalid', // should be array
    repository: 'https://github.com/test',
    latest_version: '1.0.0',
  },

  missingLatest: {
    name: '@openfn/language-test',
    versions: mockAdaptorVersions,
    repository: 'https://github.com/test',
    // latest_version missing
  },

  invalidVersionStructure: {
    name: '@openfn/language-test',
    versions: ['1.0.0', { invalidField: 'invalid' }], // wrong structure
    repository: 'https://github.com/test',
    latest_version: '1.0.0',
  },
};

/**
 * Helper to create adaptor data with specific characteristics
 */
export function createMockAdaptor(overrides: Partial<Adaptor> = {}): Adaptor {
  return {
    ...mockAdaptor,
    ...overrides,
  };
}

/**
 * Helper to create adaptors list with specific number of items
 */
export function createMockAdaptorsList(count: number): AdaptorsList {
  return Array.from({ length: count }, (_, i) => ({
    name: `@openfn/language-test-${i}`,
    versions: [`${i}.1.0`, `${i}.0.0`],
    repository: `https://github.com/test/adaptor-${i}`,
    latest_version: `${i}.1.0`,
    icon_urls: { square: null, rectangle: null },
  }));
}
