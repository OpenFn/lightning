import type { WithActionProps } from '#/react/lib/with-props';
import WorkflowDiagram from '../workflow-diagram/WorkflowDiagram';
import { useWorkflowStore } from '../workflow-store/store';

export const WorkflowEditor: WithActionProps<{
  selection: string;
  showAiAssistant?: boolean;
  aiAssistantId?: string;
}> = props => {
  const { getItem, forceFit, showAiAssistant, aiAssistantId } =
    useWorkflowStore();

const onSelectionChange = (id?: string) => {
  console.debug('onSelectionChange', id);

  const currentUrl = new URL(window.location.href);
  const nextUrl = new URL(currentUrl);

  const idExists = getItem(id);
  if (!idExists) {
    nextUrl.searchParams.delete('s');
    // Don't delete 'm' here - let the mode be managed separately
    nextUrl.searchParams.set('placeholder', 'true');
  } else {
    nextUrl.searchParams.delete('placeholder');
    if (!id) {
      console.debug('Unselecting');
      nextUrl.searchParams.delete('s');
      // Don't delete 'm' here - selection and mode are independent concerns
    } else {
      console.debug('Selecting', id);
      nextUrl.searchParams.set('s', id);
      // When selecting something, check if we're in settings or code mode
      // If so, remove the mode (since they can't coexist)
      const currentMode = nextUrl.searchParams.get('m');
      if (currentMode === 'settings' || currentMode === 'code') {
        nextUrl.searchParams.delete('m');
      }
    }
  }

  if (
    currentUrl.searchParams.toString() !== nextUrl.searchParams.toString()
  ) {
    props.navigate(nextUrl.toString());
  }
};

  return (
    <WorkflowDiagram
      el={props.el}
      containerEl={props.containerEl}
      selection={props.selection}
      onSelectionChange={onSelectionChange}
      forceFit={forceFit}
      showAiAssistant={showAiAssistant}
      aiAssistantId={aiAssistantId}
    />
  );
};
