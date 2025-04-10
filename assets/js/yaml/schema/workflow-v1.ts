// import { JSONSchemaType } from 'ajv';
// import type { WorkflowSpec } from '../types';
const workflowV1Schema = {
  $schema: 'http://json-schema.org/draft-07/schema#',
  title: 'WorkflowSpec',
  type: 'object',
  properties: {
    version: {
      type: 'string',
      enum: ['1.0.0'],
    },
    name: {
      type: 'string',
    },
    jobs: {
      type: 'object',
      patternProperties: {
        '^.*$': {
          type: 'object',
          properties: {
            name: { type: 'string' },
            adaptor: { type: 'string' },
            body: { type: 'string' },
          },
          required: ['name', 'adaptor', 'body'],
          additionalProperties: false,
        },
      },
      additionalProperties: false,
    },
    triggers: {
      type: 'object',
      patternProperties: {
        '^.*$': {
          type: 'object',
          properties: {
            type: {
              type: 'string',
              enum: ['cron', 'webhook', 'kafka'],
            },
            enabled: {
              type: 'boolean',
            },
            cron_expression: {
              type: 'string',
            },
          },
          required: ['type', 'enabled'],
          additionalProperties: false,
          oneOf: [
            {
              properties: {
                type: { const: 'cron' },
                cron_expression: { type: 'string' },
              },
              required: ['cron_expression'],
            },
            {
              properties: { type: { const: 'webhook' } },
            },
            {
              properties: { type: { const: 'kafka' } },
            },
          ],
        },
      },
      additionalProperties: false,
    },
    edges: {
      type: 'object',
      patternProperties: {
        '^.*$': {
          type: 'object',
          properties: {
            source_trigger: { type: 'string' },
            source_job: { type: 'string' },
            target_job: { type: 'string' },
            condition_type: { type: 'string' },
            condition_label: { type: 'string' },
            condition_expression: { type: ['string', 'null'] },
            enabled: { type: 'boolean' },
          },
          required: ['target_job', 'condition_type', 'enabled'],
          additionalProperties: false,
        },
      },
      additionalProperties: false,
    },
  },
  required: ['name', 'jobs', 'triggers', 'edges'],
  additionalProperties: false,
};

export default workflowV1Schema;
