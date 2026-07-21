import { describe, it, expect } from 'vitest';

import {
  deriveVersionTiers,
  extractPackageName,
  extractAdaptorName,
  extractAdaptorDisplayName,
  interleaveVersionRanges,
  isVersionRange,
  latestMajorRange,
  resolveVersionRange,
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

  describe('isVersionRange', () => {
    it('identifies range tokens and rejects non-ranges', () => {
      // Ranges
      expect(isVersionRange('6.x')).toBe(true);
      expect(isVersionRange('6.4.x')).toBe(true);
      expect(isVersionRange('^6.4.2')).toBe(true);
      expect(isVersionRange('~6.4.2')).toBe(true);

      // Non-ranges
      expect(isVersionRange('6.4.2')).toBe(false);
      expect(isVersionRange('latest')).toBe(false);
      expect(isVersionRange('')).toBe(false);
      expect(isVersionRange('x')).toBe(false);
      expect(isVersionRange('6')).toBe(false);
    });
  });

  describe('resolveVersionRange', () => {
    const versions = ['6.4.2', '6.4.1', '6.3.0', '6.4.10', '5.9.9', '5.10.0'];

    it('resolves major ranges (N.x) to the highest matching version', () => {
      expect(resolveVersionRange('6.x', versions)).toBe('6.4.10');
      expect(resolveVersionRange('5.x', versions)).toBe('5.10.0');
    });

    it('resolves minor ranges (N.M.x) to the highest matching version', () => {
      expect(resolveVersionRange('6.4.x', versions)).toBe('6.4.10');
      expect(resolveVersionRange('6.3.x', versions)).toBe('6.3.0');
      expect(resolveVersionRange('5.9.x', versions)).toBe('5.9.9');
    });

    it('resolves caret ranges with npm semantics', () => {
      expect(resolveVersionRange('^6.3.0', versions)).toBe('6.4.10');
      expect(resolveVersionRange('^6.4.5', versions)).toBe('6.4.10');
      expect(resolveVersionRange('^5.9.9', versions)).toBe('5.10.0');

      // ^0.M.P locks to the minor for 0.x majors
      const zeroMajor = ['0.2.3', '0.2.9', '0.3.0'];
      expect(resolveVersionRange('^0.2.3', zeroMajor)).toBe('0.2.9');
    });

    it('resolves tilde ranges to the highest patch of the same minor', () => {
      expect(resolveVersionRange('~6.4.1', versions)).toBe('6.4.10');
      expect(resolveVersionRange('~5.9.0', versions)).toBe('5.9.9');
      // Lower bound respected: no 6.3.* version >= 6.3.5
      expect(resolveVersionRange('~6.3.5', versions)).toBeNull();
    });

    it('compares numerically, not lexicographically', () => {
      // '6.4.10' > '6.4.9' even though '10' < '9' as strings
      expect(resolveVersionRange('6.4.x', ['6.4.9', '6.4.10'])).toBe('6.4.10');
    });

    it('passes exact versions through and resolves latest to the highest', () => {
      expect(resolveVersionRange('6.4.1', versions)).toBe('6.4.1');
      // Exact versions pass through even when absent from the list
      expect(resolveVersionRange('9.9.9', versions)).toBe('9.9.9');
      expect(resolveVersionRange('latest', versions)).toBe('6.4.10');
    });

    it('returns null when nothing matches or input is unrecognized', () => {
      expect(resolveVersionRange('7.x', versions)).toBeNull();
      expect(resolveVersionRange('6.5.x', versions)).toBeNull();
      expect(resolveVersionRange('banana', versions)).toBeNull();
      expect(resolveVersionRange('6.x', [])).toBeNull();
      expect(resolveVersionRange('latest', [])).toBeNull();
    });

    it('skips unparseable entries in the versions list', () => {
      const messy = ['not-a-version', '6.1.0-beta.1', '6.1.0', '6.2.0'];
      expect(resolveVersionRange('6.x', messy)).toBe('6.2.0');
      expect(resolveVersionRange('6.x', ['beta', 'v6.1.0'])).toBeNull();
    });
  });

  describe('deriveVersionTiers', () => {
    const versions = ['6.4.2', '6.4.1', '6.3.0', '5.2.1', '5.1.0'];

    it('anchors tiers on an exact current version and resolves hints', () => {
      expect(deriveVersionTiers('6.4.1', versions)).toEqual({
        major: { token: '6.x', resolved: '6.4.2' },
        minor: { token: '6.4.x', resolved: '6.4.2' },
        newerMajor: null,
      });
    });

    it('anchors on the CURRENT major, not the newest, and offers an upsell', () => {
      // Job sits on 5.2.1 while v6 exists: tiers stay in the 5.* family
      expect(deriveVersionTiers('5.2.1', versions)).toEqual({
        major: { token: '5.x', resolved: '5.2.1' },
        minor: { token: '5.2.x', resolved: '5.2.1' },
        newerMajor: { token: '6.x', resolved: '6.4.2' },
      });
    });

    it('uses the latest known minor when current is a major range', () => {
      expect(deriveVersionTiers('5.x', versions)).toEqual({
        major: { token: '5.x', resolved: '5.2.1' },
        minor: { token: '5.2.x', resolved: '5.2.1' },
        newerMajor: { token: '6.x', resolved: '6.4.2' },
      });
    });

    it('keeps the minor anchor from a minor range', () => {
      expect(deriveVersionTiers('6.3.x', versions)).toEqual({
        major: { token: '6.x', resolved: '6.4.2' },
        minor: { token: '6.3.x', resolved: '6.3.0' },
        newerMajor: null,
      });
    });

    it('derives from the newest version when current is latest', () => {
      expect(deriveVersionTiers('latest', versions)).toEqual({
        major: { token: '6.x', resolved: '6.4.2' },
        minor: { token: '6.4.x', resolved: '6.4.2' },
        newerMajor: null,
      });
    });

    it('treats caret like a major lock and tilde like a minor lock', () => {
      expect(deriveVersionTiers('^5.1.0', versions).major).toEqual({
        token: '5.x',
        resolved: '5.2.1',
      });
      expect(deriveVersionTiers('~6.3.0', versions).minor).toEqual({
        token: '6.3.x',
        resolved: '6.3.0',
      });
    });

    it('still derives tiers from an exact version absent from the list', () => {
      expect(deriveVersionTiers('9.1.2', versions)).toEqual({
        major: { token: '9.x', resolved: null },
        minor: { token: '9.1.x', resolved: null },
        newerMajor: null,
      });
    });

    it('returns null tiers when no anchor can be determined', () => {
      expect(deriveVersionTiers('latest', [])).toEqual({
        major: null,
        minor: null,
        newerMajor: null,
      });
      expect(deriveVersionTiers('banana', versions)).toEqual({
        // Unrecognized input falls back to the newest known version
        major: { token: '6.x', resolved: '6.4.2' },
        minor: { token: '6.4.x', resolved: '6.4.2' },
        newerMajor: null,
      });
    });
  });

  describe('latestMajorRange', () => {
    it('returns the major-lock range of the newest version', () => {
      expect(latestMajorRange(['1.9.0', '2.1.0', '2.0.0'])).toBe('2.x');
      expect(latestMajorRange(['10.0.0', '9.9.9'])).toBe('10.x');
    });

    it('ignores unparseable entries and returns null when nothing parses', () => {
      expect(latestMajorRange(['latest', 'beta', '1.0.0'])).toBe('1.x');
      expect(latestMajorRange([])).toBeNull();
      expect(latestMajorRange(['latest', 'not-a-version'])).toBeNull();
    });
  });

  describe('interleaveVersionRanges', () => {
    it('interleaves major and minor range entries above the versions they cover', () => {
      expect(
        interleaveVersionRanges(['6.4.2', '6.4.1', '6.3.0', '5.1.0'])
      ).toEqual([
        '6.x',
        '6.4.x',
        '6.4.2',
        '6.4.1',
        '6.3.x',
        '6.3.0',
        '5.x',
        '5.1.x',
        '5.1.0',
      ]);
    });

    it('sorts unsorted input descending, numerically', () => {
      expect(interleaveVersionRanges(['1.9.0', '10.0.0', '1.10.0'])).toEqual([
        '10.x',
        '10.0.x',
        '10.0.0',
        '1.x',
        '1.10.x',
        '1.10.0',
        '1.9.x',
        '1.9.0',
      ]);
    });

    it('appends unparseable versions at the end without range entries', () => {
      expect(interleaveVersionRanges(['2.0.0', '1.0.0-beta.1'])).toEqual([
        '2.x',
        '2.0.x',
        '2.0.0',
        '1.0.0-beta.1',
      ]);
    });

    it('excludes latest and handles an empty list', () => {
      expect(interleaveVersionRanges([])).toEqual([]);
      expect(interleaveVersionRanges(['latest', '1.0.0'])).toEqual([
        '1.x',
        '1.0.x',
        '1.0.0',
      ]);
    });
  });
});
