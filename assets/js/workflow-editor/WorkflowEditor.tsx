import React from 'react';
import tippy, { type Placement } from 'tippy.js';

import type { WithActionProps } from '#/react/lib/with-props';

import WorkflowDiagram from '../workflow-diagram/WorkflowDiagram';
import { RUNS_TMP, useWorkflowStore } from '../workflow-store/store';

export const WorkflowEditor: WithActionProps<{
  selection: string;
  showAiAssistant?: boolean;
  aiAssistantId?: string;
  canEditWorkflow?: boolean;
  snapshotVersionTag?: string;
  aiAssistantEnabled?: boolean;
  liveAction?: string;
}> = props => {
  const { getItem, forceFit, updateRuns } = useWorkflowStore();

  React.useEffect(() => {
    const globalMouseEnterHandler = (e: MouseEvent<HTMLElement>) => {
      const target = e.target as HTMLElement;
      const content = target.dataset['tooltip'];
      const placement: Placement =
        target.dataset['tooltipPlacement'] || 'right';
      if (content) {
        let tp: ReturnType<typeof tippy>[number] | undefined = target._tippy;
        if (tp) {
          tp.setContent(content);
          tp.setProps({ placement });
        } else {
          tp = tippy(target, {
            content: content,
            placement,
            animation: false,
            allowHTML: false,
          });
        }
      }
    };
    window.addEventListener('mouseover', globalMouseEnterHandler);
    return () => {
      window.removeEventListener('mouseover', globalMouseEnterHandler);
    };
  }, []);

  const onSelectionChange = (id?: string) => {
    console.debug('onSelectionChange', id);

    const currentUrl = new URL(window.location.href);
    const nextUrl = new URL(currentUrl);

    const idExists = getItem(id);
    if (!idExists) {
      nextUrl.searchParams.delete('s');
      nextUrl.searchParams.delete('m');
      nextUrl.searchParams.set('placeholder', 'true');
    } else {
      nextUrl.searchParams.delete('placeholder');
      if (!id) {
        console.debug('Unselecting');

        nextUrl.searchParams.delete('s');
        nextUrl.searchParams.delete('m');
      } else {
        console.debug('Selecting', id);

        nextUrl.searchParams.set('s', id);
      }
    }

    if (
      currentUrl.searchParams.toString() !== nextUrl.searchParams.toString()
    ) {
      props.navigate(nextUrl.toString());
    }
  };

  const onRunChangeHandler = (id: string, version: number) => {
    const currentUrl = new URL(window.location.href);
    const nextUrl = new URL(currentUrl);
    nextUrl.searchParams.set('a', id);
    nextUrl.searchParams.set('v', version.toString());
    nextUrl.searchParams.set('m', 'history');
    props.navigate(nextUrl.toString());
  };

  const onCollapseHistory = () => {
    // remove run steps from the store
    updateRuns(RUNS_TMP, null);

    // update the url query.
    const currentUrl = new URL(window.location.href);
    const nextUrl = new URL(currentUrl);
    nextUrl.searchParams.delete('a');
    nextUrl.searchParams.delete('v');
    nextUrl.searchParams.delete('m');
    props.navigate(nextUrl.toString());
  };

  return (
    <WorkflowDiagram
      el={props.el}
      containerEl={props.containerEl}
      selection={props.selection}
      onSelectionChange={onSelectionChange}
      onRunChange={onRunChangeHandler}
      onCollapseHistory={onCollapseHistory}
      forceFit={forceFit}
      showAiAssistant={props.showAiAssistant}
      aiAssistantId={props.aiAssistantId}
      canEditWorkflow={props.canEditWorkflow}
      snapshotVersionTag={props.snapshotVersionTag}
      aiAssistantEnabled={props.aiAssistantEnabled}
      liveAction={props.liveAction}
    />
  );
};
