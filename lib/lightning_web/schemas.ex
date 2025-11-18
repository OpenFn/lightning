defmodule LightningWeb.Schemas do
  @moduledoc """
  OpenAPI schema definitions for Lightning API.

  This module contains schema definitions used in the OpenAPI specification.
  Each schema corresponds to a request or response structure in the API.
  """
  alias OpenApiSpex.Schema

  defmodule Project do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Project",
      description: "A Lightning project containing workflows",
      type: :object,
      properties: %{
        id: %Schema{
          type: :string,
          format: :uuid,
          description: "Unique project identifier"
        },
        name: %Schema{type: :string, description: "Project name"},
        description: %Schema{
          type: :string,
          nullable: true,
          description: "Project description"
        },
        inserted_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "Project creation timestamp"
        },
        updated_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "Last update timestamp"
        }
      },
      required: [:id, :name],
      example: %{
        "id" => "a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d",
        "name" => "Health Data Integration",
        "description" => "Integrates DHIS2 with FHIR servers",
        "inserted_at" => "2024-01-15T10:30:00Z",
        "updated_at" => "2024-01-20T15:45:00Z"
      }
    })
  end

  defmodule Workflow do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Workflow",
      description:
        "A directed acyclic graph (DAG) defining a data processing pipeline",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string, description: "Workflow name"},
        project_id: %Schema{type: :string, format: :uuid},
        jobs: %Schema{
          type: :array,
          items: LightningWeb.Schemas.Job,
          description: "Jobs in the workflow"
        },
        triggers: %Schema{
          type: :array,
          items: LightningWeb.Schemas.Trigger,
          description: "Triggers that initiate the workflow"
        },
        edges: %Schema{
          type: :array,
          items: LightningWeb.Schemas.Edge,
          description: "Connections between triggers and jobs"
        },
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :name, :project_id],
      example: %{
        "id" => "workflow-uuid",
        "name" => "Data Sync Pipeline",
        "project_id" => "project-uuid",
        "jobs" => [],
        "triggers" => [],
        "edges" => [],
        "inserted_at" => "2024-01-15T10:30:00Z",
        "updated_at" => "2024-01-20T15:45:00Z"
      }
    })
  end

  defmodule Job do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Job",
      description: "A JavaScript execution unit within a workflow",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string, description: "Job name"},
        body: %Schema{
          type: :string,
          description: "JavaScript code to execute"
        },
        adaptor: %Schema{
          type: :string,
          nullable: true,
          description:
            "NPM adaptor package name (e.g., '@openfn/language-http@latest')"
        },
        credential_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "Associated credential ID"
        },
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :name, :body],
      example: %{
        "id" => "job-uuid",
        "name" => "Extract Data",
        "body" => "fn(state => state)",
        "adaptor" => "@openfn/language-http@latest",
        "credential_id" => nil
      }
    })
  end

  defmodule Trigger do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Trigger",
      description: "Entry point that initiates a workflow",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        type: %Schema{
          type: :string,
          enum: ["webhook", "cron", "kafka"],
          description: "Trigger type"
        },
        enabled: %Schema{
          type: :boolean,
          description: "Whether trigger is active"
        },
        cron_expression: %Schema{
          type: :string,
          nullable: true,
          description: "Cron expression for scheduled triggers"
        },
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :type],
      example: %{
        "id" => "trigger-uuid",
        "type" => "webhook",
        "enabled" => true,
        "cron_expression" => nil
      }
    })
  end

  defmodule Edge do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Edge",
      description: "Connection between triggers and jobs in a workflow",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        source_trigger_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "Source trigger (mutually exclusive with source_job_id)"
        },
        source_job_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "Source job (mutually exclusive with source_trigger_id)"
        },
        target_job_id: %Schema{
          type: :string,
          format: :uuid,
          description: "Target job"
        },
        condition: %Schema{
          type: :string,
          enum: ["always", "on_job_success", "on_job_failure", "js_expression"],
          description: "Edge execution condition"
        },
        enabled: %Schema{type: :boolean, default: true}
      },
      required: [:target_job_id],
      example: %{
        "id" => "edge-uuid",
        "source_trigger_id" => "trigger-uuid",
        "source_job_id" => nil,
        "target_job_id" => "job-uuid",
        "condition" => "always",
        "enabled" => true
      }
    })
  end

  defmodule Credential do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Credential",
      description: "Authentication credential for external services",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string, description: "Credential name"},
        user_id: %Schema{
          type: :string,
          format: :uuid,
          description: "Owner user ID"
        },
        schema: %Schema{
          type: :string,
          nullable: true,
          description: "JSON schema for credential validation"
        },
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :name],
      example: %{
        "id" => "cred-uuid",
        "name" => "DHIS2 Production",
        "user_id" => "user-uuid",
        "schema" => nil
      }
    })
  end

  defmodule ErrorResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ErrorResponse",
      description: "Standard error response",
      type: :object,
      properties: %{
        errors: %Schema{
          type: :object,
          description: "Error details by field",
          additionalProperties: %Schema{
            type: :array,
            items: %Schema{type: :string}
          }
        }
      },
      example: %{
        "errors" => %{
          "name" => ["can't be blank"],
          "project_id" => ["is invalid"]
        }
      }
    })
  end

  defmodule PaginationParams do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PaginationParams",
      description: "Pagination query parameters",
      type: :object,
      properties: %{
        page: %Schema{
          type: :integer,
          description: "Page number",
          default: 1,
          minimum: 1
        },
        page_size: %Schema{
          type: :integer,
          description: "Number of items per page",
          default: 10,
          minimum: 1,
          maximum: 100
        }
      }
    })
  end
end
