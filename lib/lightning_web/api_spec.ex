defmodule LightningWeb.ApiSpec do
  @moduledoc """
  OpenAPI specification for the Lightning API.

  This module defines the OpenAPI 3.0 specification for Lightning's REST API.
  The spec is used to generate API documentation and can be served as JSON/YAML.

  ## Generating the Spec

  To generate the OpenAPI spec file:

      mix openapi.spec.yaml --spec LightningWeb.ApiSpec --output docs/static/openapi.yaml

  Or use the convenience alias:

      mix api.docs

  ## Serving the Spec

  The spec is served at `/api/openapi` in JSON format.
  """
  alias OpenApiSpex.{Info, OpenApi, Server, SecurityScheme, Components}
  alias LightningWeb.{Endpoint, Router}

  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      info: %Info{
        title: "Lightning API",
        version: "1.0.0",
        description: """
        Lightning is an open source workflow platform for governments and non-profits
        to move health and survey data between systems.

        ## Authentication

        All API endpoints require authentication using Bearer tokens. Include your API
        token in the Authorization header:

        ```
        Authorization: Bearer YOUR_API_TOKEN
        ```

        API tokens can be generated from your user profile in the Lightning application.

        ## Rate Limiting

        API requests are subject to rate limiting. Check response headers for rate
        limit information.

        ## Pagination

        List endpoints support pagination with `page` and `page_size` query parameters:
        - `page`: Page number (default: 1)
        - `page_size`: Number of items per page (default: 10, max: 100)
        """,
        contact: %{
          name: "OpenFn",
          url: "https://www.openfn.org"
        },
        license: %{
          name: "AGPL-3.0",
          url: "https://www.gnu.org/licenses/agpl-3.0.en.html"
        }
      },
      servers: [
        %Server{
          url: "https://app.openfn.org",
          description: "Production server"
        },
        %Server{
          url: "http://localhost:4000",
          description: "Local development server"
        }
      ],
      paths: OpenApiSpex.Paths.from_router(Router),
      components: %Components{
        securitySchemes: %{
          "BearerAuth" => %SecurityScheme{
            type: "http",
            scheme: "bearer",
            bearerFormat: "JWT",
            description: """
            API authentication using Bearer tokens. Generate a token from your user
            profile in the Lightning application.
            """
          }
        }
      },
      security: [%{"BearerAuth" => []}],
      tags: [
        %{
          name: "Projects",
          description: "Project management operations"
        },
        %{
          name: "Workflows",
          description: "Workflow CRUD operations and DAG management"
        },
        %{
          name: "Jobs",
          description: "Job management within workflows"
        },
        %{
          name: "Credentials",
          description:
            "Credential management for external service authentication"
        },
        %{
          name: "Work Orders",
          description: "Work order tracking and management"
        },
        %{
          name: "Runs",
          description: "Workflow execution history and details"
        },
        %{
          name: "Log Lines",
          description: "Log retrieval for workflow runs"
        },
        %{
          name: "Provisioning",
          description: "Project provisioning operations"
        },
        %{
          name: "Registration",
          description: "User registration"
        }
      ]
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
