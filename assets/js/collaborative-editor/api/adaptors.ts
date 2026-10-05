/**
 * HTTP client for the adaptor catalogue endpoint (`GET /adaptors/catalogue`).
 *
 * Session-cookie authenticated like every other route in this app; no
 * project scoping, no CSRF header (plain GET). Zod validation of each
 * catalogue entry happens downstream in AdaptorStore, not here.
 */

export interface AdaptorCatalogueResponse {
  data: unknown[];
}

export async function getAdaptorCatalogue(): Promise<AdaptorCatalogueResponse> {
  const response = await fetch('/adaptors/catalogue', {
    credentials: 'same-origin',
  });

  if (!response.ok) {
    throw new Error(response.statusText);
  }

  return response.json() as Promise<AdaptorCatalogueResponse>;
}
