defmodule LightningWeb.API.ProvisioningController do
  @moduledoc """
  API controller for project provisioning and deployment.

  Handles creation, updates, and retrieval of project state for idempotent
  deployments via the CLI. Supports both JSON and YAML formats.

  ## Endpoints

  - `POST /api/provision` - Create or update a project
  - `GET /api/provision/:id` - Get project state as JSON
  - `GET /api/provision/:id.yaml` - Get project state as YAML
  """
  use LightningWeb, :controller

  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Provisioning
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Projects.Provisioner
  alias Lightning.Workflows
  alias Lightning.WorkflowVersions

  action_fallback(LightningWeb.FallbackController)

  @doc """
  Creates or updates a project based on a JSON payload.

  Performs idempotent project provisioning by accepting UUIDs for existing
  resources. If a project ID is provided and exists, the project will be
  updated; otherwise, a new project is created.

  ## Parameters

  - `conn` - The Plug connection struct with the current resource assigned
  - `params` - Map containing project configuration (workflows, jobs, triggers, etc.)

  ## Returns

  - `201 Created` with project JSON on success
  - `422 Unprocessable Entity` with changeset errors on validation failure
  - `403 Forbidden` if user lacks provisioning permissions

  ## Examples

      # Create new project
      POST /api/provision
      {
        "name": "My Project",
        "workflows": [...]
      }

      # Update existing project
      POST /api/provision
      {
        "id": "a1b2c3d4-...",
        "name": "Updated Project",
        "workflows": [...]
      }
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    with project <- get_or_build_project(params),
         :ok <-
           Permissions.can(
             Provisioning,
             :provision_project,
             conn.assigns.current_resource,
             project
           ) do
      case Provisioner.import_document(
             project,
             conn.assigns.current_resource,
             params
           ) do
        {:ok, project} ->
          conn
          |> put_status(:created)
          |> put_resp_header("location", ~p"/api/provision/#{project.id}")
          |> render("create.json", project: project)

        {:error, %Ecto.Changeset{} = changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> render("error.json", changeset: changeset)

        {:error, error} ->
          conn
          |> put_status(:forbidden)
          |> put_view(LightningWeb.ErrorView)
          |> render(:"403",
            error:
              case error do
                %Lightning.Extensions.Message{text: text} -> text
                _ -> error
              end
          )
      end
    end
  end

  @doc """
  Returns a project state as JSON with UUIDs for idempotent deployments.

  Retrieves the complete project configuration including workflows, jobs,
  triggers, edges, and credentials. UUIDs are included to enable updates
  to existing projects via the CLI.

  ## Parameters

  - `conn` - The Plug connection struct with the current resource assigned
  - `params` - Map containing:
    - `id` - Project UUID (required)
    - `snapshots` - Whether to include workflow snapshots (optional)

  ## Returns

  - `200 OK` with project JSON on success
  - `404 Not Found` if project doesn't exist
  - `403 Forbidden` if user lacks describe permissions

  ## Examples

      # Get project state
      GET /api/provision/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d

      # Get project state with snapshots
      GET /api/provision/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d?snapshots=true
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, params) do
    with project = %Project{} <-
           Projects.get_project(params["id"]) || {:error, :not_found},
         :ok <-
           Permissions.can(
             Provisioning,
             :describe_project,
             conn.assigns.current_resource,
             project
           ),
         :ok <- ensure_workflows_have_versions(project),
         project <-
           Provisioner.preload_dependencies(project, params["snapshots"]) do
      conn
      |> put_status(:ok)
      |> render("create.json", project: project)
    end
  end

  defp ensure_workflows_have_versions(project) do
    workflows =
      Workflows.list_project_workflows(project.id,
        include: [:jobs, :edges, :triggers]
      )

    Enum.each(workflows, &WorkflowVersions.ensure_version_recorded/1)
  end

  @doc """
  Returns a project state as YAML for CLI deployments.

  Exports the complete project configuration in YAML format, equivalent to
  the "Export to YAML" feature in the UI. Useful for version control and
  CLI-based workflows.

  ## Parameters

  - `conn` - The Plug connection struct with the current resource assigned
  - `params` - Map containing:
    - `id` - Project UUID (required)
    - `snapshots` - Whether to include workflow snapshots (optional)

  ## Returns

  - `200 OK` with YAML content on success
  - `404 Not Found` if project doesn't exist
  - `403 Forbidden` if user lacks describe permissions

  ## Examples

      # Get project state as YAML
      GET /api/provision/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d.yaml

      # Get project state as YAML with snapshots
      GET /api/provision/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d.yaml?snapshots=true
  """
  @spec show_yaml(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show_yaml(conn, %{"id" => id} = params) do
    with %Projects.Project{} = project <-
           Projects.get_project(id) || {:error, :not_found},
         :ok <-
           Permissions.can(
             Provisioning,
             :describe_project,
             conn.assigns.current_resource,
             project
           ) do
      {:ok, yaml} = Projects.export_project(:yaml, id, params["snapshots"])

      conn
      |> put_resp_content_type("text/yaml")
      |> put_root_layout(false)
      |> send_resp(200, yaml)
    end
  end

  defp get_or_build_project(params) do
    params
    |> case do
      %{"id" => id} -> Projects.get_project(id) || %Project{}
      _ -> %Project{}
    end
  end
end
