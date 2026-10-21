import DesignSystemWorkflowsIndexPage from '@openfn/ui/pages/projects/WorkflowsIndexPage.tsx';
import type { Project } from '@openfn/ui/types/projects.ts';
import type {
  ProjectMetrics,
  WorkflowRow,
} from '@openfn/ui/types/workflows.ts';
import { useEffect, useRef, useState } from 'react';

import { designSystemPage } from '../page';

/** What WorkflowLive.Index puts in `data-props`. */
interface Props {
  project: Pick<Project, 'id' | 'parentId' | 'color'>;
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
    // What's typed stays while the LiveView answers a search, so a round
    // trip never eats keystrokes; the box follows the URL otherwise.
    const [draft, setDraft] = useState(searchTerm);
    const sent = useRef(searchTerm);
    const timer = useRef<number | null>(null);
    useEffect(() => {
      if (searchTerm !== sent.current) {
        sent.current = searchTerm;
        setDraft(searchTerm);
      }
    }, [searchTerm]);

    const search = (term: string) => {
      sent.current = term;
      void send('search_workflows', { value: term });
    };
    const base = `/projects/${props.project.id}/w`;
    const query = (sort: string, dir: string) =>
      `${base}?sort=${sort}&dir=${dir}${draft ? `&q=${encodeURIComponent(draft)}` : ''}`;

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
        timer.current = window.setTimeout(() => search(term), SEARCH_DEBOUNCE);
      },
      onClear: () => {
        if (timer.current) window.clearTimeout(timer.current);
        setDraft('');
        sent.current = '';
        void send('clear_search');
      },
      // The server answers each of these with a flash and a fresh list.
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
