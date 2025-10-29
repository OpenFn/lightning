---
sidebar_position: 1
---

# Lightning API Documentation

Welcome to the Lightning API documentation. Lightning is an open source workflow
platform for governments and non-profits to move health and survey data between
systems.

## What is Lightning?

Lightning is a workflow automation platform built on Elixir/Phoenix that
enables:

- **Workflow Management**: Create directed acyclic graphs (DAGs) with jobs,
  triggers, and edges
- **Real-time Collaboration**: Multiple users can edit workflows simultaneously
- **Secure Credential Management**: Store and manage authentication credentials
  for external services
- **Flexible Execution**: Support for webhook, cron, and Kafka-based triggers
- **Comprehensive Monitoring**: Track workflow execution with detailed run
  history and logs

## API Overview

The Lightning API provides programmatic access to:

- **Projects**: Organizational units containing workflows
- **Workflows**: Directed acyclic graphs defining data processing pipelines
- **Jobs**: JavaScript execution units with NPM adaptors
- **Credentials**: Secure authentication for external services
- **Work Orders**: Workflow execution requests
- **Runs**: Individual job execution records
- **Log Lines**: Detailed execution logs

## Authentication

All API endpoints require authentication using Bearer tokens. Include your API
token in the Authorization header:

```bash
curl -H "Authorization: Bearer YOUR_API_TOKEN" \
  https://app.openfn.org/api/projects
```

### Getting Your API Token

1. Log in to your Lightning instance
2. Navigate to your user profile
3. Go to "Profile Tokens" section
4. Generate a new API token

## Quick Start

Here's a simple example to get you started:

### List Your Projects

```bash
curl -H "Authorization: Bearer YOUR_API_TOKEN" \
  https://app.openfn.org/api/projects
```

### Get a Specific Workflow

```bash
curl -H "Authorization: Bearer YOUR_API_TOKEN" \
  https://app.openfn.org/api/workflows/WORKFLOW_ID
```

### Create a Workflow

```bash
curl -X POST \
  -H "Authorization: Bearer YOUR_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "project_id": "PROJECT_ID",
    "name": "My Workflow",
    "jobs": [{
      "id": "job-uuid-1",
      "name": "Extract Data",
      "body": "fn(state => state)"
    }],
    "triggers": [{
      "id": "trigger-uuid-1",
      "type": "webhook",
      "enabled": true
    }],
    "edges": [{
      "source_trigger_id": "trigger-uuid-1",
      "target_job_id": "job-uuid-1",
      "condition": "always"
    }]
  }' \
  https://app.openfn.org/api/workflows
```

## API Reference

For detailed endpoint documentation, see the [API Reference](/docs/api) section.

## Key Concepts

### Workflows

Workflows are directed acyclic graphs (DAGs) that consist of:

- **Jobs**: JavaScript code blocks that process data using NPM adaptors
- **Triggers**: Entry points (webhook, cron, or Kafka) that initiate workflows
- **Edges**: Connections between triggers and jobs with conditional logic

### Jobs

Jobs are the building blocks of workflows. Each job:

- Executes JavaScript code in an isolated environment
- Can use NPM adaptors for external service integration
- Receives input state and produces output state
- Can be connected to other jobs via edges

### Triggers

Triggers determine how workflows are initiated:

- **Webhook**: HTTP endpoint that accepts JSON payloads
- **Cron**: Time-based scheduling using cron expressions
- **Kafka**: Event-driven triggers from Kafka topics

### Credentials

Credentials store authentication details for external services:

- Encrypted at rest using strong encryption
- Can be shared across multiple projects
- Bodies are never returned in API responses (except on creation)

## Rate Limiting

API requests are subject to rate limiting. Check response headers for rate limit
information:

- `X-RateLimit-Limit`: Maximum requests per window
- `X-RateLimit-Remaining`: Remaining requests in current window
- `X-RateLimit-Reset`: Time when the rate limit resets

## Pagination

List endpoints support pagination with query parameters:

- `page`: Page number (default: 1)
- `page_size`: Number of items per page (default: 10, max: 100)

Example:

```bash
curl -H "Authorization: Bearer YOUR_API_TOKEN" \
  "https://app.openfn.org/api/projects?page=2&page_size=20"
```

## Error Handling

The API uses standard HTTP status codes:

- `200`: Success
- `201`: Created
- `204`: No Content (successful deletion)
- `400`: Bad Request
- `401`: Unauthorized
- `403`: Forbidden
- `404`: Not Found
- `409`: Conflict
- `422`: Unprocessable Entity (validation error)
- `429`: Too Many Requests (rate limited)
- `500`: Internal Server Error

Error responses include details in the response body:

```json
{
  "errors": {
    "field_name": ["Error message"]
  }
}
```

## Support

- **Community Forum**: https://community.openfn.org
- **GitHub Issues**: https://github.com/OpenFn/Lightning/issues
- **GitHub Discussions**: https://github.com/OpenFn/Lightning/discussions

## License

Lightning is licensed under AGPL-3.0. See the
[LICENSE](https://github.com/OpenFn/Lightning/blob/main/LICENSE) file for
details.
