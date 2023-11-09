import React, { useState, useEffect } from 'react';

export type AdaptorIconData = {
  [adaptor: string]: {
    rectangle: string;
    square: string;
  };
};

// This is a shared promise to load the adaptor data
let deffered: Promise<AdaptorIconData>;

const useAdaptorIcons = (): AdaptorIconData => {
  const [data, setData] = useState<AdaptorIconData>({});

  useEffect(() => {
    if (!deffered) {
      // The first request to adaptor data will initiate the fetch
      // and read the data
      deffered = fetch('/images/adaptors/adaptor_icons.json')
        .then(response => response.json())
        .catch(err => {
          console.error('Error fetching Adaptor Icons manifest:', err);
        });
    }

    // Subsequent calls will chain the fetch promise and instantly resolve once
    // the data is down
    deffered.then(d => {
      setData(d);
    });
  }, []);

  return data;
};

export default useAdaptorIcons;
