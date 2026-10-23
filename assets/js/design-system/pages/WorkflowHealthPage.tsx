import {
  WorkflowHealthPage as DesignSystemWorkflowHealthPage,
  type WorkflowHealthPageProps,
} from '@openfn/ui';
import { useState } from 'react';

import type { RunVolume } from '../../health/charts/VolumeBars';
import { DEFAULT_DAYS } from '../../health/RangePicker';
import type { ErrorSignatures, Outcomes } from '../../health/types';
import { healthBase, useHealthQuery } from '../../health/useHealthQuery';
import { designSystemPage } from '../page';

/** What WorkflowLive.Health puts in `data-props`: the page minus the range and the replies. */
export type Props = Omit<
  WorkflowHealthPageProps,
  'days' | 'onDaysChange' | 'outcomes' | 'failures' | 'runs'
>;

/**
 * The design system's health page, fed by WorkflowLive.Health. The island
 * keeps the range and asks the health endpoints itself, as the old page did:
 * each panel polls every 30 seconds and keeps its last numbers through a
 * failed poll.
 */
export const WorkflowHealthPage = designSystemPage(
  'WorkflowHealthPage',
  DesignSystemWorkflowHealthPage,
  ['/projects/:project_id/w/:id/health'],
  (props: Props) => {
    const [days, setDays] =
      useState<WorkflowHealthPageProps['days']>(DEFAULT_DAYS);
    const base = healthBase(props.project.id, props.workflow.id);

    return {
      ...props,
      days,
      onDaysChange: setDays,
      outcomes: useHealthQuery<Outcomes>(`${base}/outcomes?days=${days}`),
      failures: useHealthQuery<ErrorSignatures>(
        `${base}/failures?days=${days}`
      ),
      runs: useHealthQuery<RunVolume>(`${base}/runs?days=${days}`),
    };
  }
);
