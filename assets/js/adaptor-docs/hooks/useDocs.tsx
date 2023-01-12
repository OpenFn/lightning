import { useState, useEffect } from 'react';
import { describePackage, PackageDescription } from '@openfn/describe-package';

const useDocs = (specifier: string) => {
  // null if loading, false  if failed
  const [docs, setDocs] = useState<PackageDescription | null | false>(null);

  useEffect(() => {
    setDocs(null); // Reset docs when the specifier changes
    describePackage(specifier, {}).then((result) => {
      setDocs(result);
    }).catch((err) => {
      console.error(err)
      setDocs(false)
    });
  }, [specifier])

  return docs;
};

export default useDocs;