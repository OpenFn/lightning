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

  alias Ecto.Changeset
  alias Lightning.Extensions.Message
  alias Lightning.Projects
  alias Lightning.Projects.Provisioner
  alias Lightning.Workflows
  alias Lightning.WorkflowVersions
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Problem
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target

  action_fallback(FallbackController)

  plug LightningWeb.Plugs.AuthorizeAction,
       {:provisioning, :provision_project}
       when action == :create

  plug LightningWeb.Plugs.AuthorizeAction,
       {:provisioning, :describe_project}
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
  - `403 Forbidden` if the body names a project the caller has no standing on,
    or the caller lacks the role or grant to provision it, or to create a
    project. The service account always hears `forbidden`, or, without
    `projects:write`, `insufficient_scope` naming it
  - `409 Conflict` to a caller who may provision the project, if it is
    scheduled for deletion, or if another request changed what it writes
  - `400 Bad Request` if the body is not a JSON object
  - `422 Unprocessable Content` when the document is not valid, including one
    without an `id`, a value that must be unique and is taken, or, to a caller
    who may create projects, a body `id` that isn't a UUID. The `id` is read
    from the body only, never the query.
  - `402 Payment Required` when an otherwise valid document would exceed a
    plan limit
  - `503 Service Unavailable` while the adaptor catalogue is still loading

  Every error is a problem document.

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
  @spec create(Plug.Conn.t(), map()) ::
          Plug.Conn.t() | {:error, term()} | {:error, term(), Message.t()}
  def create(conn, _params) do
    body = conn.body_params

    with {:ok, project} <-
           Target.project_or_new(
             conn.assigns.scope,
             {[:id], body["id"]},
             {:provisioning, :provision_project},
             {:provisioning, :provision_new_project}
           ),
         :ok <- Request.check_object(body),
         {:ok, project} <-
           Provisioner.import_document(
             project,
             conn.assigns.current_resource,
             body
           ) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/provision/#{project.id}")
      |> render("create.json", project: project)
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
    - `snapshots` - A list of snapshot ids, each a UUID, to return in place
      of the workflows' current state (optional)

  ## Returns

  - `200 OK` with project JSON on success
  - `400 Bad Request` if `snapshots` isn't a list of UUIDs, or to a superuser
    or the service account if `id` isn't a UUID
  - `403 Forbidden` if the caller has no standing on the project, lacks the
    grant, or hasn't met the project's MFA requirement
  - `404 Not Found` to a superuser or the service account, if the project
    doesn't exist
  - `409 Conflict` to a caller who may see the project, if it is scheduled
    for deletion

  ## Examples

      # Get project state
      GET /api/provision/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d

      # Get project state with snapshots
      GET /api/provision/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d?snapshots[]=6f1e2d3c-4b5a-4968-8776-5a4b3c2d1e0f
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def show(conn, params) do
    with {:ok, project} <- describe_target(conn),
         {:ok, snapshot_ids} <- fetch_snapshot_ids(params) do
      ensure_workflows_have_versions(project)

      conn
      |> put_status(:ok)
      |> render("create.json",
        project: Provisioner.preload_dependencies(project, snapshot_ids)
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
    - `snapshots` - A list of snapshot ids, each a UUID, to return in place
      of the workflows' current state (optional)

  ## Returns

  - `200 OK` with YAML content on success
  - `400 Bad Request` without an `id`
  - `400 Bad Request` if `snapshots` isn't a list of UUIDs, or to a superuser
    or the service account if `id` isn't a UUID
  - `403 Forbidden` if the caller has no standing on the project, lacks the
    grant, or hasn't met the project's MFA requirement
  - `404 Not Found` to a superuser or the service account, if the project
    doesn't exist
  - `409 Conflict` to a caller who may see the project, if it is scheduled
    for deletion

  ## Examples

      # Get project state as YAML
      GET /api/provision/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d.yaml

      # Get project state as YAML with snapshots
      GET /api/provision/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d.yaml?snapshots[]=6f1e2d3c-4b5a-4968-8776-5a4b3c2d1e0f
  """
  @spec show_yaml(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def show_yaml(conn, %{"id" => _} = params) do
    with {:ok, project} <- describe_target(conn),
         {:ok, snapshot_ids} <- fetch_snapshot_ids(params),
         {:ok, yaml} <-
           Projects.export_project(:yaml, project.id, snapshot_ids, :v1) do
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

  defp fetch_snapshot_ids(params) do
    with {:ok, filters} <-
           {%{}, %{snapshots: {:array, Ecto.UUID}}}
           |> Changeset.cast(params, [:snapshots])
           |> Changeset.apply_action(:validate)
           |> Errors.refuse_parameters() do
      {:ok, filters[:snapshots]}
    end
  end

  defp describe_target(conn) do
    Target.project(
      conn.assigns.scope,
      Request.param(conn, "id"),
      {:provisioning, :describe_project}
    )
  end
end
