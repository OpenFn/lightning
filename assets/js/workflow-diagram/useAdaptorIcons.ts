import { useState, useEffect } from 'react';

export type AdaptorIconData = {
  [adaptor: string]:
    | {
        rectangle: string;
        square: string;
      }
    | undefined;
};

// This is a shared promise to load the adaptor data
let deffered: Promise<AdaptorIconData> | undefined;

const useAdaptorIcons = (): AdaptorIconData | null => {
  const [data, setData] = useState<AdaptorIconData | null>(null);

  useEffect(() => {
    if (!deffered) {
      // The first request to adaptor data will initiate the fetch
      // and read the data
      deffered = fetch('/images/adaptors/adaptor_icons.json')
        .then(response => response.json() as Promise<AdaptorIconData>)
        .catch(err => {
          console.error('Error fetching Adaptor Icons manifest:', err);
          return {} as AdaptorIconData;
        });
    }

    // Subsequent calls will chain the fetch promise and instantly resolve once
    // the data is down
    void deffered.then(d => {
      setData(d);
      return d;
    });
  }, []);

  return data;
};

export default useAdaptorIcons;
