import { useState, useEffect, useMemo } from 'react';
import { describePackage, PackageDescription } from '@openfn/describe-package';

// Describe package is slow right now even if data is available
// This in-mamory cache will help when switching tabs etc
const cache: Record<string, PackageDescription | null | false> = {}

const useDocs = (specifier: string) => {
  const [docs, setDocs] = useState<PackageDescription | null | false>(null);

  useEffect(() => {
    if (cache.hasOwnProperty(specifier)) {
      // TODO if the cache is null, it's loading docs
      // To avoid loading twice, we need to register a callback
      setDocs(cache[specifier]);
    } else {
      cache[specifier] = null;
      describePackage(specifier, {}).then((result) => {
        cache[specifier] = result;
        setDocs(result);
      }).catch((err) => {
        cache[specifier] = false;
        setDocs(false)
      });  
    }
  }, [specifier])

  return docs;
};

export default useDocs;