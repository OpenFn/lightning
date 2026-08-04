/**
 * Props for the workflow health screen.
 *
 * These arrive from `LightningWeb.WorkflowLive.Health` as JSON, so keys are
 * underscore_cased and timestamps are ISO 8601 strings.
 */

export type Blame = 'user' | 'remote' | 'limit' | 'platform';

export interface Outcomes {
  total: number;
  pending: number;
  success: number;
  failed: number;
  success_rate: number;
  failure_rate: number;
}

export interface FailureReason {
  /** A run state — "failed", "crashed", "killed", "lost". */
  state: string;
  count: number;
  percentage: number;
}

export interface FailureBreakdown {
  total: number;
  reasons: FailureReason[];
}

export interface StepFailure {
  /** Null when no step ran, or when the job has since been deleted. */
  job: string | null;
  count: number;
  /**
   * False for failures that happened before any step ran. The server sends
   * this rather than a display string, so the wording lives here.
   */
  attributed: boolean;
}

export interface StepsWithFailures {
  total: number;
  unattributed: number;
  steps: StepFailure[];
}

export interface VolumeBucket {
  started_at: string;
  runs: number;
  failed: number;
}

export interface VolumeOverTime {
  bucket_seconds: number;
  buckets: VolumeBucket[];
}

export interface HistogramBucket {
  label: string;
  runs: number;
}

export interface ResponseTime {
  p50: number | null;
  p95: number | null;
  max: number | null;
  sampled: number;
  histogram: HistogramBucket[];
}

export interface TriageSignature {
  exit_reason: string;
  error_type: string | null;
  job: string | null;
  adaptor: string | null;
  runs: number;
  blame: Blame;
  /**
   * Always null for now. The worker sends an error message, but `Step` has no
   * column to keep it in, so the message half of a real error signature is not
   * available to group on. The text does survive in the run logs.
   */
  message: string | null;
}

export interface WorkflowHealthProps {
  outcomes: Outcomes;
  failure_breakdown: FailureBreakdown;
  steps_with_failures: StepsWithFailures;
  volume_over_time: VolumeOverTime;
  response_time: ResponseTime;
  triage: TriageSignature[];
}
