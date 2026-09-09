/**
 * AdaptorDisplay credential-values tests
 *
 * A project reads a credential's values only through the grant on its share, so
 * a credential can be attached to a job and still have nothing to give. The run
 * fails at the moment it asks, which is a poor way to find out, so the badge
 * says it where the credential is shown.
 */

import { render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, test, vi } from 'vitest';

import { AdaptorDisplay } from '../../../js/collaborative-editor/components/AdaptorDisplay';

type StoreCredential = {
  id: string;
  project_credential_id: string;
  name: string;
  external_id: string | null;
  schema: string;
  owner: { id: string; name: string; email: string } | null;
  oauth_client_name: string | null;
  has_values: boolean;
  inserted_at: string;
  updated_at: string;
};

let found: StoreCredential | null = null;
let foundType: 'project' | 'keychain' = 'project';

vi.mock('../../../js/collaborative-editor/hooks/useCredentials', () => ({
  useCredentialQueries: () => ({
    findCredentialById: () => (found ? { ...found, type: foundType } : null),
    credentialExists: () => found !== null,
    getCredentialId: () => found?.id ?? null,
  }),
}));

function credential(overrides: Partial<StoreCredential> = {}): StoreCredential {
  return {
    id: 'cred-1',
    project_credential_id: 'share-1',
    name: 'Production DHIS2',
    external_id: null,
    schema: 'raw',
    owner: { id: 'u1', name: 'Ada', email: 'ada@example.com' },
    oauth_client_name: null,
    has_values: true,
    inserted_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    ...overrides,
  };
}

describe('AdaptorDisplay credential values', () => {
  beforeEach(() => {
    found = null;
    foundType = 'project';
  });

  test('says so when the project was given no values', () => {
    found = credential({ has_values: false });

    render(
      <AdaptorDisplay
        adaptor="@openfn/language-http@1.0.0"
        credentialId="cred-1"
      />
    );

    expect(screen.getByTestId('credential-no-values')).toBeInTheDocument();
  });

  test('shows the ordinary badge when the project has values', () => {
    found = credential({ has_values: true });

    render(
      <AdaptorDisplay
        adaptor="@openfn/language-http@1.0.0"
        credentialId="cred-1"
      />
    );

    expect(
      screen.queryByTestId('credential-no-values')
    ).not.toBeInTheDocument();

    expect(
      screen.getByLabelText('Credential connected: Production DHIS2')
    ).toBeInTheDocument();
  });

  test('says nothing about values for a keychain credential', () => {
    // A keychain picks its credential from the run's own data, so there is no
    // single set of values to have been granted and no answer to give here.
    foundType = 'keychain';
    found = credential();
    delete (found as Partial<StoreCredential>).has_values;

    render(
      <AdaptorDisplay
        adaptor="@openfn/language-http@1.0.0"
        credentialId="cred-1"
      />
    );

    expect(
      screen.queryByTestId('credential-no-values')
    ).not.toBeInTheDocument();
  });

  test('is not confused with a credential that cannot be found', () => {
    found = null;

    render(
      <AdaptorDisplay
        adaptor="@openfn/language-http@1.0.0"
        credentialId="cred-1"
      />
    );

    // A deleted credential and one with no values are different problems with
    // different remedies.
    expect(
      screen.queryByTestId('credential-no-values')
    ).not.toBeInTheDocument();

    expect(screen.getByLabelText('Credential not found')).toBeInTheDocument();
  });
});
