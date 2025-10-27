/**
 * Test fixtures for adaptor data
 *
 * Provides consistent test data that matches the Zod schemas
 * for testing adaptor store functionality.
 */

import type {
  Adaptor,
  AdaptorVersion,
  AdaptorsList,
} from '../../../js/collaborative-editor/types/adaptor';

/**
 * Sample adaptor versions for testing
 */
export const mockAdaptorVersions: AdaptorVersion[] = [
  { version: '2.1.0' },
  { version: '2.0.5' },
  { version: '2.0.0' },
  { version: '1.9.5' },
];

/**
 * Sample single adaptor for testing
 */
export const mockAdaptor: Adaptor = {
  name: '@openfn/language-http',
  versions: mockAdaptorVersions,
  repo: 'https://github.com/OpenFn/adaptors/tree/main/packages/http',
  latest: '2.1.0',
};

/**
 * Additional adaptors for comprehensive testing
 */
export const mockAdaptorDhis2: Adaptor = {
  name: '@openfn/language-dhis2',
  versions: [{ version: '4.2.1' }, { version: '4.2.0' }, { version: '4.1.3' }],
  repo: 'https://github.com/OpenFn/adaptors/tree/main/packages/dhis2',
  latest: '4.2.1',
};

export const mockAdaptorSalesforce: Adaptor = {
  name: '@openfn/language-salesforce',
  versions: [
    { version: '3.5.2' },
    { version: '3.5.1' },
    { version: '3.5.0' },
    { version: '3.4.9' },
  ],
  repo: 'https://github.com/OpenFn/adaptors/tree/main/packages/salesforce',
  latest: '3.5.2',
};

/**
 * Complete adaptors list for testing
 */
export const mockAdaptorsList: AdaptorsList = [
  mockAdaptor,
  mockAdaptorDhis2,
  mockAdaptorSalesforce,
];

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
    repo: 'https://github.com/test',
    latest: '1.0.0',
  },

  invalidVersions: {
    name: '@openfn/language-test',
    versions: 'invalid', // should be array
    repo: 'https://github.com/test',
    latest: '1.0.0',
  },

  missingLatest: {
    name: '@openfn/language-test',
    versions: mockAdaptorVersions,
    repo: 'https://github.com/test',
    // latest missing
  },

  invalidVersionStructure: {
    name: '@openfn/language-test',
    versions: [
      { version: '1.0.0' },
      { invalidField: 'invalid' }, // wrong structure
    ],
    repo: 'https://github.com/test',
    latest: '1.0.0',
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
/* eslint-disable @typescript-eslint/restrict-template-expressions */
export function createMockAdaptorsList(count: number): AdaptorsList {
  return Array.from({ length: count }, (_, i) => ({
    name: `@openfn/language-test-${i}`,
    versions: [{ version: `${i}.1.0` }, { version: `${i}.0.0` }],
    repo: `https://github.com/test/adaptor-${i}`,
    latest: `${i}.1.0`,
  }));
}
/* eslint-enable @typescript-eslint/restrict-template-expressions */
