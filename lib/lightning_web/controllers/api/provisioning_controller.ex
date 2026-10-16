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
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Projects.Provisioner
  alias Lightning.Scope
  alias Lightning.Workflows
  alias Lightning.WorkflowVersions
  alias LightningWeb.API.Errors
  alias LightningWeb.API.Problem

  action_fallback(LightningWeb.API.FallbackController)

  plug LightningWeb.Plugs.AuthorizeAction,
       {:provisioning, :provision_project,
        fallback: LightningWeb.API.FallbackController}
       when action == :create

  plug LightningWeb.Plugs.AuthorizeAction,
       {:provisioning, :describe_project,
        fallback: LightningWeb.API.FallbackController}
       when action in [:show, :show_yaml]

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
  - `404 Not Found` if the body names a project the caller has no standing on
  - `403 Forbidden` if the caller lacks the role or grant to provision it, or
    to create a project
  - `409 Conflict` to a caller who may provision the project, if it is
    scheduled for deletion, or if a value that must be unique is taken
  - `422 Unprocessable Content` when the document is not valid
  - `402 Payment Required` when a plan limit is reached
  - `503 Service Unavailable` while the adaptor catalogue is still loading

  Every error is a problem document (error-format spec §2).

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
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t() | term()
  def create(conn, params) do
    with {:ok, project} <- provision_target(conn.assigns.scope, params["id"]),
         {:ok, project} <-
           Provisioner.import_document(
             project,
             conn.assigns.current_resource,
             params
           ) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/provision/#{project.id}")
      |> render("create.json", project: project)
    end
  end

  # The project the body names is the target, as if it were in the path: an
  # id taken by a project the caller has no standing on is 404, a free one is
  # created by a caller who may create projects (spec §4, plan D14).
  defp provision_target(scope, nil), do: create_target(scope)

  defp provision_target(scope, id) do
    with {:ok, id} <- cast_id(id) do
      case Scope.fetch(scope, id) do
        {:ok, project_scope} ->
          with :ok <-
                 Permissions.permit(
                   :provisioning,
                   :provision_project,
                   project_scope,
                   project_scope.project
                 ),
               do: {:ok, project_scope.project}

        # Also a repo connection's answer for a project other than its own,
        # which must not be mistaken for a free id.
        {:error, :no_such_project} ->
          if Projects.get_project(id),
            do: {:error, :not_found},
            else: create_target(scope)
      end
    end
  end

  defp cast_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :not_found}
    end
  end

  defp create_target(scope) do
    with :ok <- Permissions.permit(:provisioning, :create_project, scope, nil),
         do: {:ok, %Project{}}
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
  - `404 Not Found` if the project doesn't exist or the caller has no standing
    on it
  - `403 Forbidden` if the caller lacks the grant, or hasn't met the
    project's MFA requirement
  - `409 Conflict` to a caller who may see the project, if it is scheduled
    for deletion

  ## Examples

      # Get project state
      GET /api/provision/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d

      # Get project state with snapshots
      GET /api/provision/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d?snapshots=true
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | term()
  def show(conn, %{"id" => id} = params) do
    with {:ok, project} <- describe_target(conn.assigns.scope, id) do
      ensure_workflows_have_versions(project)

      conn
      |> put_status(:ok)
      |> render("create.json",
        project: Provisioner.preload_dependencies(project, params["snapshots"])
      )
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
  - `400 Bad Request` without an `id`
  - `404 Not Found` if the project doesn't exist or the caller has no standing
    on it
  - `403 Forbidden` if the caller lacks the grant, or hasn't met the
    project's MFA requirement
  - `409 Conflict` to a caller who may see the project, if it is scheduled
    for deletion

  ## Examples

      # Get project state as YAML
      GET /api/provision/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d.yaml

      # Get project state as YAML with snapshots
      GET /api/provision/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d.yaml?snapshots=true
  """
  @spec show_yaml(Plug.Conn.t(), map()) :: Plug.Conn.t() | term()
  def show_yaml(conn, %{"id" => id} = params) do
    with {:ok, project} <- describe_target(conn.assigns.scope, id),
         {:ok, yaml} <-
           Projects.export_project(:yaml, project.id, params["snapshots"], :v1) do
      conn
      |> put_resp_content_type("text/yaml")
      |> put_root_layout(false)
      |> send_resp(200, yaml)
    end
  end

  def show_yaml(_conn, _params) do
    {:error,
     Problem.new(:invalid_parameter,
       errors: [
         Errors.entry(
           {:parameter, "id"},
           {"can't be blank", validation: :required}
         )
       ]
     )}
  end

  defp describe_target(scope, id) do
    with {:ok, project_scope} <- Scope.fetch(scope, id),
         :ok <-
           Permissions.permit(
             :provisioning,
             :describe_project,
             project_scope,
             project_scope.project
           ),
         do: {:ok, project_scope.project}
  end
end
