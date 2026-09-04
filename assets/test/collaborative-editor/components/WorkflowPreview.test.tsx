/**
 * WorkflowPreview - read-only workflow diagram
 *
 * The point of these tests is as much architectural as behavioural: the
 * component is rendered with NO StoreProvider, NO SessionProvider, NO Y.Doc and
 * NO Phoenix channel. If a future change couples the preview to the
 * collaborative editor's machinery, these tests stop compiling or start
 * throwing — which is exactly the guard we want.
 *
 * The preview takes a parsed state, so these build one the same way the real
 * callers do rather than hand-rolling a fixture that could drift from what the
 * YAML layer actually produces.
 */

import { render, screen, waitFor } from '@testing-library/react';
import { describe, expect, test } from 'vitest';

import { WorkflowPreview } from '#/collaborative-editor/components/WorkflowPreview';
import type { WorkflowState } from '#/yaml/types';
import { convertWorkflowSpecToState, parseWorkflowYAML } from '#/yaml/util';

function stateFrom(yaml: string): WorkflowState {
  return convertWorkflowSpecToState(parseWorkflowYAML(yaml));
}

const TWO_STEP_YAML = `name: "Two step workflow"
jobs:
  Fetch-data:
    name: Fetch data
    adaptor: "@openfn/language-http@latest"
    body: |
      get('https://example.com');
  Transform-data:
    name: Transform data
    adaptor: "@openfn/language-common@latest"
    body: |
      fn(state => state);
triggers:
  webhook:
    type: webhook
    enabled: true
edges:
  webhook->Fetch-data:
    source_trigger: webhook
    target_job: Fetch-data
    condition_type: always
    enabled: true
  Fetch-data->Transform-data:
    source_job: Fetch-data
    target_job: Transform-data
    condition_type: on_job_success
    enabled: true`;

/**
 * The same shape, but published by someone who had switched the canvas to
 * manual layout: every node carries a `pos`. This is what a real user's
 * template looks like once they have arranged it by hand.
 */
const POSITIONED_YAML = `name: "Positioned workflow"
jobs:
  Fetch-data:
    name: Fetch data
    adaptor: "@openfn/language-http@latest"
    body: |
      get('https://example.com');
    pos:
      x: 640
      y: 420
triggers:
  webhook:
    type: webhook
    enabled: true
    pos:
      x: 640
      y: 180
edges:
  webhook->Fetch-data:
    source_trigger: webhook
    target_job: Fetch-data
    condition_type: always
    enabled: true`;

describe('WorkflowPreview', () => {
  test('renders a node per job and trigger, with no editor providers present', async () => {
    render(<WorkflowPreview state={stateFrom(TWO_STEP_YAML)} />);

    // Layout is async, so the nodes appear on a later tick.
    await waitFor(() => {
      expect(screen.getByText('Fetch data')).toBeInTheDocument();
    });
    expect(screen.getByText('Transform data')).toBeInTheDocument();
    // Reusing the real Trigger node means we get its real labelling for free.
    expect(screen.getByText('Webhook trigger')).toBeInTheDocument();
  });

  test('draws no editing affordances on the nodes', async () => {
    const { container } = render(
      <WorkflowPreview state={stateFrom(TWO_STEP_YAML)} />
    );

    await waitFor(() => {
      expect(screen.getByText('Fetch data')).toBeInTheDocument();
    });

    // The preview asks `fromWorkflow` for a disabled workflow, which is what
    // suppresses the "+" connector on each job node. That request travels
    // through an `as unknown as Lightning.Workflow` cast, so if the diagram
    // ever renames or re-purposes the flag, TypeScript will NOT flag this file
    // and the preview silently becomes interactive. This is the assertion that
    // notices.
    expect(
      container.querySelector('[data-handleid="node-connector"]')
    ).toBeNull();
    expect(container.querySelector('.hero-plus')).toBeNull();
  });

  describe('authored positions', () => {
    /**
     * Creating a workflow from a state applies its positions verbatim, so the
     * preview has to draw those rather than a fresh auto-layout — otherwise it
     * shows one arrangement and the user lands on another. This is the
     * assertion that keeps the two honest.
     */
    test('draws nodes where the state says, not where Dagre would put them', async () => {
      const state = stateFrom(POSITIONED_YAML);
      const { container } = render(<WorkflowPreview state={state} />);

      await waitFor(() => {
        expect(screen.getByText('Fetch data')).toBeInTheDocument();
      });

      const job = state.jobs[0]!;
      const authored = state.positions![job.id]!;

      expect(container.querySelector(`[data-id="${job.id}"]`)).toHaveStyle({
        transform: `translate(${authored.x}px,${authored.y}px)`,
      });
    });

    test('lays out fresh when only some nodes carry a position', async () => {
      // A hand-edited or partially-migrated template. Every node needs a
      // position, so a partial set is ignored wholesale rather than leaving the
      // rest at an undefined coordinate.
      const state = stateFrom(POSITIONED_YAML);
      const trigger = state.triggers[0]!;
      delete state.positions![trigger.id];

      const { container } = render(<WorkflowPreview state={state} />);

      await waitFor(() => {
        expect(screen.getByText('Fetch data')).toBeInTheDocument();
      });

      const job = state.jobs[0]!;
      expect(container.querySelector(`[data-id="${job.id}"]`)).not.toHaveStyle({
        transform: 'translate(640px,420px)',
      });
    });
  });
});
