// workflow-errors.ts

export enum WorkflowErrorCode {
  // YAML Parsing Errors
  YAML_SYNTAX_ERROR = 'YAML_SYNTAX_ERROR',

  // Schema Validation Errors
  SCHEMA_MISSING_PROPERTY = 'SCHEMA_MISSING_PROPERTY',
  SCHEMA_INVALID_PROPERTY = 'SCHEMA_INVALID_PROPERTY',
  SCHEMA_INVALID_VALUE = 'SCHEMA_INVALID_VALUE',
  SCHEMA_TYPE_ERROR = 'SCHEMA_TYPE_ERROR',

  // Reference Errors
  JOB_NOT_FOUND = 'JOB_NOT_FOUND',
  TRIGGER_NOT_FOUND = 'TRIGGER_NOT_FOUND',

  // Logical Errors
  DUPLICATE_JOB_NAME = 'DUPLICATE_JOB_NAME',
  INVALID_EDGE_KEY = 'INVALID_EDGE_KEY',

  // Unknown
  UNKNOWN_ERROR = 'UNKNOWN_ERROR',
}

export interface WorkflowErrorDetails {
  code: WorkflowErrorCode;
  message: string;
  path?: string;
  reference?: string;
  edgeKey?: string;
  jobKey?: string;
  triggerKey?: string;
  allowedValues?: string[];
  duplicateName?: string;
  rawError?: any;
}

export class WorkflowError extends Error {
  public readonly code: WorkflowErrorCode;
  public readonly details: WorkflowErrorDetails;

  constructor(details: WorkflowErrorDetails) {
    super(details.message);
    this.name = 'WorkflowError';
    this.code = details.code;
    this.details = details;

    // Maintains proper stack trace for where our error was thrown (only available on V8)
    if (Error.captureStackTrace) {
      Error.captureStackTrace(this, WorkflowError);
    }
  }

  toJSON(): WorkflowErrorDetails {
    return this.details;
  }
}

// Specific error classes for better type safety
export class YamlSyntaxError extends WorkflowError {
  constructor(message: string, rawError?: any) {
    super({
      code: WorkflowErrorCode.YAML_SYNTAX_ERROR,
      message,
      rawError,
    });
    this.name = 'YamlSyntaxError';
  }
}

export class JobNotFoundError extends WorkflowError {
  constructor(jobReference: string, edgeKey: string, isSource: boolean = true) {
    super({
      code: WorkflowErrorCode.JOB_NOT_FOUND,
      message: `${isSource ? 'Source job' : 'Target job'} '${jobReference}' specified by edge '${edgeKey}' not found in spec`,
      reference: jobReference,
      edgeKey,
    });
    this.name = 'JobNotFoundError';
  }
}

export class TriggerNotFoundError extends WorkflowError {
  constructor(triggerReference: string, edgeKey: string) {
    super({
      code: WorkflowErrorCode.TRIGGER_NOT_FOUND,
      message: `Source trigger '${triggerReference}' specified by edge '${edgeKey}' not found in spec`,
      reference: triggerReference,
      edgeKey,
    });
    this.name = 'TriggerNotFoundError';
  }
}

export class DuplicateJobNameError extends WorkflowError {
  constructor(jobName: string, jobKey: string) {
    super({
      code: WorkflowErrorCode.DUPLICATE_JOB_NAME,
      message: `Duplicate job name '${jobName}' found at 'jobs/${jobKey}'`,
      duplicateName: jobName,
      jobKey,
      path: `jobs/${jobKey}`,
    });
    this.name = 'DuplicateJobNameError';
  }
}

export class SchemaValidationError extends WorkflowError {
  constructor(details: {
    keyword: string;
    instancePath: string;
    params: any;
    message?: string;
  }) {
    let code: WorkflowErrorCode;
    let message: string;
    const errorDetails: Partial<WorkflowErrorDetails> = {
      path: details.instancePath,
    };

    switch (details.keyword) {
      case 'required':
        code = WorkflowErrorCode.SCHEMA_MISSING_PROPERTY;
        message = `Missing required property '${details.params.missingProperty}' at ${details.instancePath}`;
        break;

      case 'additionalProperties':
        code = WorkflowErrorCode.SCHEMA_INVALID_PROPERTY;
        message = `Unknown property '${details.params.additionalProperty}' at ${details.instancePath}`;
        break;

      case 'enum':
        code = WorkflowErrorCode.SCHEMA_INVALID_VALUE;
        message = `Invalid value at ${details.instancePath}. Allowed values are: ${details.params.allowedValues.join(', ')}`;
        errorDetails.allowedValues = details.params.allowedValues;
        break;

      case 'type':
        code = WorkflowErrorCode.SCHEMA_TYPE_ERROR;
        message = `Type error at ${details.instancePath}: expected ${details.params.type}`;
        break;

      default:
        code = WorkflowErrorCode.SCHEMA_INVALID_VALUE;
        message =
          details.message || `Validation error at ${details.instancePath}`;
    }

    super({
      code,
      message,
      ...errorDetails,
    });
    this.name = 'SchemaValidationError';
  }
}

// Error factory for creating errors from unknown sources
export function createWorkflowError(error: unknown): WorkflowError {
  // If it's already a WorkflowError, return it
  if (error instanceof WorkflowError) {
    return error;
  }

  // If it's an Error with a message, try to parse it
  if (error instanceof Error) {
    const message = error.message;

    // Check for reference errors
    const jobRefMatch = message.match(
      /(?:SourceJob|TargetJob):\s*'([^']+)'\s*specified by edge\s*'([^']+)'/
    );
    if (jobRefMatch) {
      const isSource = message.includes('SourceJob:');
      return new JobNotFoundError(jobRefMatch[1], jobRefMatch[2], isSource);
    }

    const triggerRefMatch = message.match(
      /SourceTrigger:\s*'([^']+)'\s*specified by edge\s*'([^']+)'/
    );
    if (triggerRefMatch) {
      return new TriggerNotFoundError(triggerRefMatch[1], triggerRefMatch[2]);
    }

    // Check for duplicate job name
    const duplicateMatch = message.match(
      /Duplicate job name\s*'([^']+)'\s*found at\s*'jobs\/([^']+)'/
    );
    if (duplicateMatch) {
      return new DuplicateJobNameError(duplicateMatch[1], duplicateMatch[2]);
    }

    // Check for YAML syntax errors
    if (
      message.includes('YAML') ||
      message.includes('expected') ||
      message.includes('unexpected')
    ) {
      return new YamlSyntaxError(message, error);
    }

    // Default to unknown error with original message
    return new WorkflowError({
      code: WorkflowErrorCode.UNKNOWN_ERROR,
      message: message,
      rawError: error,
    });
  }

  // For non-Error objects
  return new WorkflowError({
    code: WorkflowErrorCode.UNKNOWN_ERROR,
    message: String(error),
    rawError: error,
  });
}

// Helper function to format errors for display
export function formatWorkflowError(error: WorkflowError): string {
  switch (error.code) {
    case WorkflowErrorCode.JOB_NOT_FOUND:
      return `Job reference error: The job '${error.details.reference}' referenced in edge '${error.details.edgeKey}' does not exist. Please check that all job names are correctly spelled and hyphenated.`;

    case WorkflowErrorCode.TRIGGER_NOT_FOUND:
      return `Trigger reference error: The trigger '${error.details.reference}' referenced in edge '${error.details.edgeKey}' does not exist.`;

    case WorkflowErrorCode.DUPLICATE_JOB_NAME:
      return `Duplicate job name: Multiple jobs have the name '${error.details.duplicateName}'. Each job must have a unique name.`;

    case WorkflowErrorCode.YAML_SYNTAX_ERROR:
      return `YAML syntax error: ${error.message}. Please check your YAML formatting.`;

    case WorkflowErrorCode.SCHEMA_MISSING_PROPERTY:
      return `Missing required field: ${error.message}`;

    case WorkflowErrorCode.SCHEMA_INVALID_PROPERTY:
      return `Invalid property: ${error.message}`;

    case WorkflowErrorCode.SCHEMA_INVALID_VALUE:
      return error.details.allowedValues
        ? `Invalid value at ${error.details.path}. Must be one of: ${error.details.allowedValues.join(', ')}`
        : error.message;

    default:
      return error.message;
  }
}
