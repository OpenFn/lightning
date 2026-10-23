import {
  type CurrentProject,
  type ProjectMetrics,
  type WorkflowRow,
  WorkflowsIndexPage as DesignSystemWorkflowsIndexPage,
} from '@openfn/ui';
import { useEffect, useRef, useState } from 'react';

import { designSystemPage } from '../page';

/** What WorkflowLive.Index puts in `data-props`. */
export interface Props {
  project: CurrentProject;
  projectLabel: string;
  period: string;
  stats: WorkflowRow[];
  metrics: ProjectMetrics;
  pendingHref: string;
  failedHref: string;
  searchTerm: string;
  sortKey: string;
  sortDirection: 'asc' | 'desc';
  canCreateWorkflow: boolean;
  canDeleteWorkflow: boolean;
  lifecycle: boolean;
}

const SEARCH_DEBOUNCE = 300;

/** The design system's workflows page, fed by WorkflowLive.Index. */
export const WorkflowsIndexPage = designSystemPage(
  'WorkflowsIndexPage',
  DesignSystemWorkflowsIndexPage,
  ['/projects/:project_id/w'],
  ({ searchTerm, sortKey, sortDirection, ...props }: Props, { send }) => {
    // What's typed stays while the LiveView answers. The box follows the
    // URL's term only when nothing is being typed and every search has been
    // answered, so a slow reply to an older search never overwrites it.
    const [draft, setDraft] = useState(searchTerm);
    const inFlight = useRef(0);
    const timer = useRef<number | null>(null);
    useEffect(() => {
      if (inFlight.current === 0 && timer.current === null)
        setDraft(searchTerm);
    }, [searchTerm]);

    // A refused or lost search leaves the list as it was, as a dropped
    // keyup did; the next keystroke asks again.
    const search = (event: string, payload?: Record<string, unknown>) => {
      inFlight.current += 1;
      void send(event, payload)
        .catch(() => undefined)
        .finally(() => {
          inFlight.current -= 1;
        });
    };
    const base = `/projects/${props.project.id}/w`;
    const query = (sort: string, dir: string) =>
      `${base}?sort=${sort}&dir=${dir}${searchTerm ? `&q=${encodeURIComponent(searchTerm)}` : ''}`;

    return {
      ...props,
      searchTerm: draft,
      sort: {
        key: sortKey,
        direction: sortDirection,
        // The server flips the direction for the current column and starts
        // another ascending; the href says where a left click will go.
        hrefFor: (key: string) =>
          query(
            key,
            key === sortKey && sortDirection === 'asc' ? 'desc' : 'asc'
          ),
        onSort: (key: string) => void send('sort', { by: key }),
      },
      onSearch: (term: string) => {
        setDraft(term);
        if (timer.current) window.clearTimeout(timer.current);
        timer.current = window.setTimeout(() => {
          timer.current = null;
          search('search_workflows', { value: term });
        }, SEARCH_DEBOUNCE);
      },
      onClear: () => {
        if (timer.current) window.clearTimeout(timer.current);
        timer.current = null;
        setDraft('');
        search('clear_search');
      },
      // The server answers each of these with a flash and a fresh list; a
      // refusal rejects, and the page says so.
      onToggle: (workflowId: string, enabled: boolean) =>
        send('toggle_workflow_state', {
          workflow_state: String(enabled),
          value_key: workflowId,
        }),
      onDelete: (workflowId: string) =>
        send('delete_workflow', { id: workflowId }),
    };
  }
);
