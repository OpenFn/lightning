import { describe, it, expect } from 'vitest';

import {
  extractPackageName,
  extractAdaptorName,
  extractAdaptorDisplayName,
} from '#/collaborative-editor/utils/adaptorUtils';

describe('adaptorUtils', () => {
  describe('extractPackageName', () => {
    it('extracts package name from scoped package with version', () => {
      expect(extractPackageName('@openfn/language-salesforce@latest')).toBe(
        '@openfn/language-salesforce'
      );
      expect(extractPackageName('@openfn/language-http@1.2.3')).toBe(
        '@openfn/language-http'
      );
      expect(extractPackageName('@openfn/language-dhis-2@2.0.0')).toBe(
        '@openfn/language-dhis-2'
      );
    });

    it('returns scoped package name as-is when no version', () => {
      expect(extractPackageName('@openfn/language-http')).toBe(
        '@openfn/language-http'
      );
      expect(extractPackageName('@openfn/language-salesforce')).toBe(
        '@openfn/language-salesforce'
      );
    });

    it('extracts package name from unscoped package with version', () => {
      expect(extractPackageName('language-common@latest')).toBe(
        'language-common'
      );
      expect(extractPackageName('language-common@1.4.3')).toBe(
        'language-common'
      );
    });

    it('returns unscoped package name as-is when no version', () => {
      expect(extractPackageName('language-common')).toBe('language-common');
      expect(extractPackageName('some-package')).toBe('some-package');
    });

    it('handles edge cases', () => {
      // Only scope prefix
      expect(extractPackageName('@openfn')).toBe('@openfn');

      // Empty string
      expect(extractPackageName('')).toBe('');
    });
  });

  describe('extractAdaptorName', () => {
    it('extracts adaptor name from full package string', () => {
      expect(extractAdaptorName('@openfn/language-salesforce@latest')).toBe(
        'salesforce'
      );
      expect(extractAdaptorName('@openfn/language-http')).toBe('http');
      expect(extractAdaptorName('@openfn/language-dhis-2')).toBe('dhis-2');
      expect(extractAdaptorName('@openfn/language-common@1.4.3')).toBe(
        'common'
      );
    });

    it('returns null for invalid package strings', () => {
      expect(extractAdaptorName('invalid-package')).toBeNull();
      expect(extractAdaptorName('@openfn/something-else')).toBeNull();
      expect(extractAdaptorName('')).toBeNull();
    });
  });

  describe('extractAdaptorDisplayName', () => {
    it('extracts and formats display name from package string', () => {
      expect(
        extractAdaptorDisplayName('@openfn/language-salesforce@latest')
      ).toBe('Salesforce');
      expect(extractAdaptorDisplayName('@openfn/language-http@1.0.0')).toBe(
        'Http'
      );
      expect(extractAdaptorDisplayName('@openfn/language-dhis-2')).toBe(
        'Dhis 2'
      );
      expect(extractAdaptorDisplayName('@openfn/language-common')).toBe(
        'Common'
      );
    });

    it('returns original string for invalid packages', () => {
      expect(extractAdaptorDisplayName('invalid-package')).toBe(
        'invalid-package'
      );
      expect(extractAdaptorDisplayName('')).toBe('');
    });
  });
});
