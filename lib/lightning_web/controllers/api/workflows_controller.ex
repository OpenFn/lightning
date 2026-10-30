defmodule LightningWeb.API.WorkflowsController do
  @moduledoc """
  API controller for workflow management.

  Handles CRUD operations for workflows, including their jobs, triggers, and edges.
  Workflows are directed acyclic graphs (DAGs) that define data processing pipelines.

  ## Workflow Structure

  A workflow consists of:
  - Jobs: JavaScript execution units with adaptors
  - Triggers: Initiation methods (Webhook, Cron)
  - Edges: Connections between triggers/jobs with conditions

  ## Validation Rules

  The rules in `Lightning.Workflows.GraphRules`: every job and trigger carries
  an id, the edges form no cycle, one enabled edge leaves the one enabled
  trigger, and an update removes no trigger. On create, the ids of jobs and
  triggers are the client's own and are replaced with new UUIDs. A workflow open
  in the editor can't be updated.

  Errors are problem documents (`LightningWeb.API.FallbackController`), checked
  in the order of error-format spec §4: the token's scope, the caller's standing
  and role, the workflow being open in the editor, the body, then the plan
  limit.

  ## Examples

      GET /api/workflows
      GET /api/workflows?project_id=a1b2c3d4-...
      GET /api/workflows/a1b2c3d4-...
      POST /api/projects/a1b2c3d4-.../workflows
      PATCH /api/projects/a1b2c3d4-.../workflows/e5f6a7b8-...

  ## Sample curl requests

  List all workflows:

  ```bash
  curl http://localhost:4000/api/workflows \\
    -H "Authorization: Bearer $TOKEN"
  ```

  Get a single workflow:

  ```bash
  curl http://localhost:4000/api/workflows/$WORKFLOW_ID \\
    -H "Authorization: Bearer $TOKEN"
  ```

  Filter by project:

  ```bash
  curl "http://localhost:4000/api/workflows?project_id=$PROJECT_ID" \\
    -H "Authorization: Bearer $TOKEN"
  ```

  Nested route — workflows for a specific project:

  ```bash
  curl http://localhost:4000/api/projects/$PROJECT_ID/workflows \\
    -H "Authorization: Bearer $TOKEN"
  ```

  Create a workflow:

  ```bash
  curl -X POST http://localhost:4000/api/projects/$PROJECT_ID/workflows \\
    -H "Authorization: Bearer $TOKEN" \\
    -H "Content-Type: application/json" \\
    -d '{"name":"My Workflow","jobs":[...],"triggers":[...],"edges":[...]}'
  ```

  Update a workflow:

  ```bash
  curl -X PATCH http://localhost:4000/api/projects/$PROJECT_ID/workflows/$WORKFLOW_ID \\
    -H "Authorization: Bearer $TOKEN" \\
    -H "Content-Type: application/json" \\
    -d '{"name":"Updated Name"}'
  ```
  """
  use LightningWeb, :controller

  alias Ecto.Changeset
  alias Lightning.Workflows
  alias Lightning.Workflows.GraphRules
  alias Lightning.Workflows.Presence
  alias Lightning.Workflows.Workflow
  alias Lightning.Workflows.WorkflowUsageLimiter
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target

  action_fallback FallbackController

  @access_project {:project_users, :access_project}

  plug LightningWeb.Plugs.AuthorizeAction,
       {:project_users, :access_project}

  @doc """
  Lists workflows, with their jobs, triggers and edges.

  With `project_id`, in the path or the query, lists that project's workflows; a
  project the caller can't see answers 403 `forbidden`. Without it, lists the
  workflows of every project the caller can access.

  ## Examples

      GET /api/workflows
      GET /api/workflows?project_id=a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d
      GET /api/projects/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d/workflows
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, %{"project_id" => _}) do
    with {:ok, project} <-
           Target.project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             @access_project
           ) do
      list =
        Workflows.list_project_workflows(project.id,
          include: [:edges, :jobs, :triggers]
        )

      json(conn, %{workflows: Enum.map(list, &public_workflow/1)})
    end
  end

  def index(conn, _params) do
    list =
      Workflows.list_workflows_for(conn.assigns.scope,
        include: [:edges, :jobs, :triggers]
      )

    json(conn, %{workflows: Enum.map(list, &public_workflow/1)})
  end

  @doc """
  Creates a workflow in the path's project, with its jobs, triggers and edges.

  Edges name jobs and triggers by the ids the request gives them, which are
  replaced with new UUIDs. A refused body answers one 422 with every error in
  it, and the plan limit on enabled triggers is checked only once the body is
  valid (402 `exceeds_limit`).

  ## Examples

      POST /api/projects/a1b2c3d4-.../workflows
      {
        "name": "Data Processing Pipeline",
        "jobs": [
          {"id": "extract", "name": "Extract Data", "body": "fn(state => state)"}
        ],
        "triggers": [{"id": "webhook", "type": "webhook", "enabled": true}],
        "edges": [
          {
            "source_trigger_id": "webhook",
            "target_job_id": "extract",
            "condition_type": "always"
          }
        ]
      }
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def create(conn, _params) do
    body = conn.body_params

    with {:ok, project} <-
           Target.project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             {:project_users, :create_workflow}
           ),
         :ok <- Request.check_object(body),
         {:ok, workflow} <-
           %Workflow{}
           |> Workflow.changeset(
             body
             |> remap_client_ids()
             |> Map.put("project_id", project.id)
           )
           |> Request.validate_matches_path(body, :project_id, project.id)
           |> save(conn.assigns.current_resource) do
      conn
      |> put_status(:created)
      |> json(%{workflow: public_workflow(workflow)})
    end
  end

  @doc """
  Shows a workflow, with its jobs, triggers and edges.

  On `/api/workflows/:id`, `LightningWeb.API.Target.in_project_of/5` decides
  who learns that an id names no workflow. On the nested route the path's
  project is checked first, and a workflow outside it is 404 `not_found`. A
  deleted workflow is 404 to a caller who can see its project.

  ## Examples

      GET /api/workflows/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d
      GET /api/projects/a1b2c3d4-.../workflows/a1b2c3d4-...
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def show(%{path_params: %{"project_id" => _}} = conn, _params) do
    with {:ok, workflow} <-
           Target.in_project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             @access_project,
             Request.param(conn, "id"),
             &Workflows.get_workflow_for_project(&1, &2,
               include: [:edges, :jobs, :triggers]
             )
           ) do
      json(conn, %{workflow: public_workflow(workflow)})
    end
  end

  def show(conn, _params) do
    with {:ok, workflow} <-
           Target.in_project_of(
             conn.assigns.scope,
             Request.param(conn, "id"),
             @access_project,
             &Workflows.get_project_id/1,
             &Workflows.get_workflow_for_project(&1, &2,
               include: [:edges, :jobs, :triggers]
             )
           ) do
      json(conn, %{workflow: public_workflow(workflow)})
    end
  end

  @doc """
  Updates a workflow's fields, jobs, triggers and edges.

  A list the body sends replaces the stored one; triggers may be edited or added
  but not removed. A workflow open in the editor answers 409 `being_edited`,
  before the body is read.

  ## Examples

      PATCH /api/projects/a1b2c3d4-.../workflows/a1b2c3d4-...
      {"name": "Updated Pipeline Name"}
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def update(conn, _params) do
    body = conn.body_params

    with {:ok, workflow} <-
           Target.in_project(
             conn.assigns.scope,
             Request.param(conn, "project_id"),
             {:project_users, :edit_workflow},
             Request.param(conn, "id"),
             &Workflows.get_workflow_for_project(&1, &2,
               include: [:edges, :jobs, :triggers]
             )
           ),
         :ok <- refuse_being_edited(workflow),
         :ok <- Request.check_object(body),
         {:ok, workflow} <-
           workflow
           |> Workflows.change_workflow(body)
           |> Request.validate_matches_path(
             body,
             :project_id,
             workflow.project_id
           )
           |> Request.validate_matches_path(body, :id, workflow.id)
           |> save(conn.assigns.current_resource) do
      json(conn, %{workflow: public_workflow(workflow)})
    end
  end

  defp refuse_being_edited(workflow) do
    if Presence.has_any_presence?(workflow),
      do: {:error, :being_edited},
      else: :ok
  end

  # Spec §4: the body is checked whole before the plan limit, so a 422 never
  # carries a limit and a 402 never carries a field error.
  defp save(changeset, user) do
    changeset = GraphRules.validate(changeset)

    with :ok <- refuse_invalid(changeset),
         :ok <- WorkflowUsageLimiter.limit_workflow_activation(changeset) do
      Workflows.save_workflow(changeset, user)
    end
  end

  defp refuse_invalid(%Changeset{valid?: true}), do: :ok
  defp refuse_invalid(changeset), do: {:error, changeset}

  defp public_workflow(workflow) do
    Map.take(workflow, Workflow.json_fields() -- [:state])
  end

  # On create, jobs and triggers carry ids of the client's choosing, which the
  # edges refer to. Each becomes a new UUID; an edge naming an id no job or
  # trigger carries keeps it, so the changeset reports it where it was sent.
  defp remap_client_ids(body) do
    {body, ids} = remap_ids(body, "jobs", %{})
    {body, ids} = remap_ids(body, "triggers", ids)

    case body do
      %{"edges" => edges} when is_list(edges) ->
        Map.put(body, "edges", Enum.map(edges, &remap_edge(&1, ids)))

      _no_edges ->
        body
    end
  end

  defp remap_ids(body, key, ids) do
    case body do
      %{^key => items} when is_list(items) ->
        {items, ids} = Enum.map_reduce(items, ids, &remap_id/2)
        {Map.put(body, key, items), ids}

      _no_list ->
        {body, ids}
    end
  end

  defp remap_id(%{"id" => client_id} = item, ids) when not is_nil(client_id) do
    id = Ecto.UUID.generate()
    {Map.put(item, "id", id), Map.put(ids, client_id, id)}
  end

  defp remap_id(item, ids), do: {item, ids}

  defp remap_edge(%{} = edge, ids) do
    Map.new(edge, fn
      {key, value}
      when key in ["source_job_id", "source_trigger_id", "target_job_id"] ->
        {key, Map.get(ids, value, value)}

      pair ->
        pair
    end)
  end

  defp remap_edge(edge, _ids), do: edge
end
