defmodule LightningWeb.API.ProjectControllerSpec do
  @moduledoc """
  OpenAPI specifications for ProjectController endpoints.

  This module provides a reference implementation showing how to annotate
  API controllers with OpenApiSpex specifications.

  ## Usage

  To enable OpenAPI specs for a controller:

  1. Add `use OpenApiSpex.ControllerSpecs` to your controller
  2. Add `tags ["TagName"]` to specify the API tag
  3. Add `operation :function_name, ...` before each action

  ## Example Integration

  ```elixir
  defmodule LightningWeb.API.ProjectController do
    use LightningWeb, :controller
    use OpenApiSpex.ControllerSpecs

    alias LightningWeb.Schemas
    alias LightningWeb.API.ProjectControllerSpec

    tags ["Projects"]

    operation :index,
      summary: ProjectControllerSpec.index_operation().summary,
      parameters: ProjectControllerSpec.index_operation().parameters,
      responses: ProjectControllerSpec.index_operation().responses

    def index(conn, params) do
      # existing implementation
    end
  end
  ```

  ## Note

  This is a separate spec module to avoid modifying the existing controller
  during initial setup. Once you're ready, you can move these specs directly
  into the controller modules.
  """

  alias OpenApiSpex.{Operation, Parameter, Response, Schema}
  alias LightningWeb.Schemas

  @doc """
  OpenAPI spec for listing projects.
  """
  def index_operation do
    %Operation{
      summary: "List all accessible projects",
      description: """
      Returns a paginated list of projects that the current user or API token
      has access to.
      """,
      operationId: "ProjectController.index",
      tags: ["Projects"],
      parameters: [
        %Parameter{
          name: :page,
          in: :query,
          description: "Page number for pagination",
          schema: %Schema{type: :integer, default: 1, minimum: 1}
        },
        %Parameter{
          name: :page_size,
          in: :query,
          description: "Number of items per page",
          schema: %Schema{type: :integer, default: 10, minimum: 1, maximum: 100}
        }
      ],
      responses: %{
        200 => %Response{
          description: "Successful response",
          content: %{
            "application/json" => %OpenApiSpex.MediaType{
              schema: %Schema{
                type: :object,
                properties: %{
                  data: %Schema{
                    type: :array,
                    items: Schemas.Project
                  },
                  page_number: %Schema{type: :integer},
                  page_size: %Schema{type: :integer},
                  total_entries: %Schema{type: :integer},
                  total_pages: %Schema{type: :integer}
                }
              }
            }
          }
        },
        401 => %Response{
          description: "Authentication required",
          content: %{
            "application/json" => %OpenApiSpex.MediaType{
              schema: Schemas.ErrorResponse
            }
          }
        },
        429 => %Response{
          description: "Rate limit exceeded",
          content: %{
            "application/json" => %OpenApiSpex.MediaType{
              schema: Schemas.ErrorResponse
            }
          }
        }
      },
      security: [%{"BearerAuth" => []}]
    }
  end

  @doc """
  OpenAPI spec for getting a project by ID.
  """
  def show_operation do
    %Operation{
      summary: "Get project by ID",
      description: """
      Returns detailed information about a single project if the authenticated
      user has access to it.
      """,
      operationId: "ProjectController.show",
      tags: ["Projects"],
      parameters: [
        %Parameter{
          name: :id,
          in: :path,
          required: true,
          description: "Project UUID",
          schema: %Schema{type: :string, format: :uuid}
        }
      ],
      responses: %{
        200 => %Response{
          description: "Successful response",
          content: %{
            "application/json" => %OpenApiSpex.MediaType{
              schema: %Schema{
                type: :object,
                properties: %{
                  data: Schemas.Project
                }
              }
            }
          }
        },
        403 => %Response{
          description: "Insufficient permissions",
          content: %{
            "application/json" => %OpenApiSpex.MediaType{
              schema: Schemas.ErrorResponse
            }
          }
        },
        404 => %Response{
          description: "Resource not found",
          content: %{
            "application/json" => %OpenApiSpex.MediaType{
              schema: Schemas.ErrorResponse
            }
          }
        }
      },
      security: [%{"BearerAuth" => []}]
    }
  end
end
