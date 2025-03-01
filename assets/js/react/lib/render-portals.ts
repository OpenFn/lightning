import ReactDOM from 'react-dom';

import type { Portals } from '#/react/types';

export const renderPortals = (portals: Portals): null | React.ReactPortal[] =>
  portals.size > 0
    ? Array.from(portals.entries()).map(([key, [container, children]]) =>
        ReactDOM.createPortal(children, container, key)
      )
    : null;
