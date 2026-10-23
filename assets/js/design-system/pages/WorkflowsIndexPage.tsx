import {
  WorkflowsIndexPage as DesignSystemWorkflowsIndexPage,
  type WorkflowsIndexPageProps,
} from '@openfn/ui';
import { useEffect, useRef, useState } from 'react';

import { designSystemPage } from '../page';

/**
 * What WorkflowLive.Index puts in `data-props`: the page's data, without its
 * callbacks. Lightning always sends the History links and the lifecycle flag,
 * so its schema requires them where the page doesn't.
 */
export type Props = Omit<
  WorkflowsIndexPageProps,
  | 'pendingHref'
  | 'failedHref'
  | 'lifecycle'
  | 'onSearch'
  | 'onClear'
  | 'onToggle'
  | 'onDelete'
> & {
  pendingHref: string;
  failedHref: string;
  lifecycle: boolean;
};

const SEARCH_DEBOUNCE = 300;

/** The design system's workflows page, fed by WorkflowLive.Index. Sorting is a URL patch. */
export const WorkflowsIndexPage = designSystemPage(
  'WorkflowsIndexPage',
  DesignSystemWorkflowsIndexPage,
  ['/projects/:project_id/w'],
  ({ searchTerm, ...props }: Props, { send }) => {
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

    return {
      ...props,
      searchTerm: draft,
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
