import type { ReactFlowInstance } from '@xyflow/react';
import React from 'react';

import { FIT_DURATION } from '../../../workflow-diagram/constants';

type SupportedEvents = 'fit-view';

const flowEvents = {
  dispatch(event: SupportedEvents) {
    window.dispatchEvent(new CustomEvent(event));
  },
  register(event: SupportedEvents, handler: () => void) {
    window.addEventListener(event, handler);
    return () => window.removeEventListener(event, handler);
  },
};

export const useFlowEvents = (flow?: ReactFlowInstance) => {
  React.useEffect(() => {
    // fitview code
    return flowEvents.register('fit-view', () => {
      void flow?.fitView({ duration: FIT_DURATION });
    });
  }, []);
};

export default flowEvents;
