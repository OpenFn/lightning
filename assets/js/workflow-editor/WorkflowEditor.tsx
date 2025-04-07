
import type { WithActionProps } from '#/react/lib/with-props';
import WorkflowDiagram from '../workflow-diagram/WorkflowDiagram';
import { useWorkflowStore } from '../workflow-store/store';

export const WorkflowEditor: WithActionProps<{ selection: string }> = (props) => {
  const { getItem, selection } = useWorkflowStore();

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
  }

  return <WorkflowDiagram
    el={props.el}
    containerEl={props.containerEl}
    selection={selection}
    onSelectionChange={onSelectionChange}
  />
}