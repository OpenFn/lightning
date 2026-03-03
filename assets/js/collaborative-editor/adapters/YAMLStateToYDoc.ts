import * as Y from 'yjs';

import type {
  WorkflowState as YAMLWorkflowState,
  StateJob as YAMLStateJob,
  StateTrigger as YAMLStateTrigger,
  StateEdge as YAMLStateEdge,
} from '../../yaml/types';
import type { Session } from '../types/session';

/**
 * YAMLStateToYDoc
 *
 * Transforms YAML WorkflowState into Y.Doc collaborative data structures.
 *
 * Key transformations:
 * 1. Jobs: string body → Y.Text, add default enabled=true
 * 2. Triggers: union types → always include cron_expression (default "")
 * 3. Edges: optional fields → required strings (default "")
 * 4. Workflow metadata: flat structure → separate workflow Map
 * 5. Positions: Record → Y.Map individual entries
 */

export class YAMLStateToYDoc {
  /**
   * Transform StateJob to Y.Doc Job Map
   */
  static transformJob(job: YAMLStateJob): Y.Map<unknown> {
    const jobMap = new Y.Map();

    jobMap.set('id', job.id);
    jobMap.set('name', job.name);
    jobMap.set('adaptor', job.adaptor);

    // Transform string body to Y.Text
    const bodyText = new Y.Text(job.body);
    jobMap.set('body', bodyText);

    // Add default enabled field (required by Session.Job but not in YAML)
    jobMap.set('enabled', true);

    // Add credentials (needed because we don't send them to the ai chat)
    if (job.project_credential_id) {
      jobMap.set('project_credential_id', job.project_credential_id);
    }
    if (job.keychain_credential_id) {
      jobMap.set('keychain_credential_id', job.keychain_credential_id);
    }

    return jobMap;
  }

  /**
   * Transform StateTrigger to Y.Doc Trigger Map
   *
   * Handles union type transformation:
   * - CronTrigger: has cron_expression
   * - WebhookTrigger/KafkaTrigger: must default cron_expression to ""
   */
  static transformTrigger(trigger: YAMLStateTrigger): Y.Map<unknown> {
    const triggerMap = new Y.Map();

    triggerMap.set('id', trigger.id);
    triggerMap.set('type', trigger.type); // Required for diagram icon rendering
    triggerMap.set('enabled', trigger.enabled);

    // Session.Trigger always requires cron_expression
    // Default to null for non-cron triggers
    const cronExpression =
      trigger.type === 'cron' ? trigger.cron_expression : null;
    triggerMap.set('cron_expression', cronExpression);

    return triggerMap;
  }

  /**
   * Transform StateEdge to Y.Doc Edge Map
   *
   * All optional fields in YAML become required strings in Y.Doc
   */
  static transformEdge(edge: YAMLStateEdge): Y.Map<unknown> {
    const edgeMap = new Y.Map();

    edgeMap.set('id', edge.id);

    edgeMap.set('source_job_id', edge.source_job_id || null);
    edgeMap.set('source_trigger_id', edge.source_trigger_id || null);
    edgeMap.set('target_job_id', edge.target_job_id);
    edgeMap.set('condition_type', edge.condition_type);
    edgeMap.set('condition_label', edge.condition_label || null);
    edgeMap.set('condition_expression', edge.condition_expression || null);
    edgeMap.set('enabled', edge.enabled);

    return edgeMap;
  }

  /**
   * Apply WorkflowState to Y.Doc in a single transaction
   *
   * This uses Pattern 1 (Y.Doc → Observer → Immer):
   * - Single ydoc.transact() for atomic bulk updates
   * - Observers automatically sync Immer state
   * - No manual notify() calls needed
   */
  static applyToYDoc(
    ydoc: Session.WorkflowDoc,
    workflowState: YAMLWorkflowState
  ): void {
    ydoc.transact(() => {
      // 1. Set workflow metadata (separate Map)
      const workflowMap = ydoc.getMap('workflow');
      workflowMap.set('name', workflowState.name);

      // 2. Clear and populate jobs array
      const jobsArray = ydoc.getArray('jobs');
      jobsArray.delete(0, jobsArray.length);
      const transformedJobs = workflowState.jobs.map(job =>
        this.transformJob(job)
      );
      jobsArray.push(transformedJobs);

      // 3. Clear and populate triggers array
      const triggersArray = ydoc.getArray('triggers');
      triggersArray.delete(0, triggersArray.length);
      const transformedTriggers = workflowState.triggers.map(trigger =>
        this.transformTrigger(trigger)
      );
      triggersArray.push(transformedTriggers);

      // 4. Clear and populate edges array
      const edgesArray = ydoc.getArray('edges');
      edgesArray.delete(0, edgesArray.length);
      const transformedEdges = workflowState.edges.map(edge =>
        this.transformEdge(edge)
      );
      edgesArray.push(transformedEdges);

      // 5. Set positions (individual entries)
      const positionsMap = ydoc.getMap('positions');
      positionsMap.clear();
      if (workflowState.positions) {
        Object.entries(workflowState.positions).forEach(([id, pos]) => {
          positionsMap.set(id, pos);
        });
      }
    });
  }
}
