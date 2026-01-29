defmodule LightningWeb.API.WorkflowsController do
  @moduledoc """
  API controller for workflow management.

  Handles CRUD operations for workflows, including their jobs, triggers, and edges.
  Workflows are directed acyclic graphs (DAGs) that define data processing pipelines.

  ## Workflow Structure

  A workflow consists of:
  - Jobs: JavaScript execution units with adaptors
  - Triggers: Initiation methods (Webhook, Cron, Kafka)
  - Edges: Connections between triggers/jobs with conditions

  ## Validation Rules

  - Workflows must be valid DAGs (no cycles)
  - Only one trigger can be enabled at a time
  - All jobs and triggers must have valid UUIDs
  - Edges must reference existing jobs/triggers
  - Cannot modify workflows with active presence (being edited in UI)

  ## Examples

      GET /api/workflows
      GET /api/workflows?project_id=a1b2c3d4-...
      GET /api/workflows/a1b2c3d4-...
      POST /api/workflows
      PATCH /api/workflows/a1b2c3d4-...
  """
  @moduledoc docout: true

  use LightningWeb, :controller

  import Lightning.Workflows.WorkflowUsageLimiter,
    only: [limit_workflow_activation: 2]

  alias Ecto.Changeset

  alias Lightning.Extensions.Message
  alias Lightning.Graph
  alias Lightning.Policies.Permissions
  alias Lightning.Projects.Project
  alias Lightning.Repo
  alias Lightning.Workflows
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Presence
  alias Lightning.Workflows.Workflow
  alias LightningWeb.ChangesetJSON

  action_fallback LightningWeb.FallbackController

  require Logger

  @doc """
  Lists workflows with optional project filtering.

  This function has two variants:
  - With `project_id`: Returns workflows for a specific project
  - Without `project_id`: Returns workflows across all accessible projects

  Returns all workflows including their jobs, triggers, and edges.

  ## Parameters

  - `conn` - The Plug connection struct with the current resource assigned
  - `params` - Map containing:
    - `project_id` - Project UUID (optional, filters to specific project)

  ## Returns

  - `200 OK` with workflows list and empty errors map
  - `404 Not Found` if project doesn't exist (when project_id provided)
  - `403 Forbidden` if user lacks project access (when project_id provided)

  ## Examples

      # All workflows accessible to user
      GET /api/workflows

      # Workflows for specific project
      GET /api/workflows?project_id=a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, %{"project_id" => project_id}) do
    with :ok <- validate_project_id(%{"project_id" => project_id}, project_id),
         :ok <- authorize_read(conn, project_id) do
      list =
        Workflows.list_project_workflows(project_id,
          include: [:edges, :jobs, :triggers]
        )

      json(conn, %{workflows: list, errors: %{}})
    end
    |> then(&maybe_handle_error(conn, &1))
  end

  def index(conn, _params) do
    list =
      Workflows.workflows_for_user_query(conn.assigns.current_resource)
      |> Repo.all()
      |> Repo.preload([:edges, :jobs, :triggers])

    json(conn, %{workflows: list, errors: %{}})
  end

  @doc """
  Creates a new workflow in a project.

  Creates a workflow with jobs, triggers, and edges. Validates the workflow
  structure and ensures it forms a valid DAG with no cycles.

  ## Parameters

  - `conn` - The Plug connection struct with the current resource assigned
  - `params` - Map containing:
    - `project_id` - Project UUID (required)
    - `name` - Workflow name (required)
    - `jobs` - List of job definitions with UUIDs (required)
    - `triggers` - List of trigger definitions with UUIDs (required)
    - `edges` - List of edge definitions connecting jobs/triggers (required)

  ## Returns

  - `201 Created` with workflow JSON on success
  - `422 Unprocessable Entity` with validation errors
  - `403 Forbidden` if user lacks write access

  ## Examples

      POST /api/workflows
      {
        "project_id": "a1b2c3d4-...",
        "name": "Data Processing Pipeline",
        "jobs": [
          {
            "id": "job-uuid-1",
            "name": "Extract Data",
            "body": "fn(state => state)"
          }
        ],
        "triggers": [
          {
            "id": "trigger-uuid-1",
            "type": "webhook",
            "enabled": true
          }
        ],
        "edges": [
          {
            "source_trigger_id": "trigger-uuid-1",
            "target_job_id": "job-uuid-1",
            "condition": "always"
          }
        ]
      }
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"project_id" => project_id} = params) do
    with :ok <- validate_project_id(conn.body_params, project_id),
         :ok <- authorize_write(conn, project_id),
         {:ok, workflow} <- save_workflow(params, conn.assigns.current_resource) do
      conn
      |> put_status(:created)
      |> json(%{workflow: workflow, errors: %{}})
    end
    |> then(&maybe_handle_error(conn, &1))
  end

  @doc """
  Retrieves a workflow by ID.

  This function has two variants:
  - With `project_id`: Validates workflow belongs to specified project
  - Without `project_id`: Determines project access from workflow association

  Returns a workflow with all its jobs, triggers, and edges.

  ## Parameters

  - `conn` - The Plug connection struct with the current resource assigned
  - `params` - Map containing:
    - `id` - Workflow UUID (required)
    - `project_id` - Project UUID (optional, for validation)

  ## Returns

  - `200 OK` with workflow JSON on success
  - `404 Not Found` if workflow doesn't exist
  - `400 Bad Request` if workflow exists but project_id mismatch
  - `403 Forbidden` if user lacks project access

  ## Examples

      # Get workflow by ID only
      GET /api/workflows/a1b2c3d4-5e6f-7a8b-9c0d-1e2f3a4b5c6d

      # Get workflow with project validation
      GET /api/workflows/workflow-uuid-1?project_id=a1b2c3d4-...
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def show(conn, %{"project_id" => project_id, "id" => workflow_id}) do
    with :ok <- validate_uuid(project_id),
         :ok <- validate_uuid(workflow_id),
         :ok <- authorize_read(conn, project_id),
         {:ok, workflow} <- get_workflow(workflow_id, project_id) do
      json(conn, %{workflow: workflow, errors: %{}})
    end
    |> then(&maybe_handle_error(conn, &1))
  end

  def show(conn, %{"id" => workflow_id}) do
    with :ok <- validate_uuid(workflow_id),
         workflow when not is_nil(workflow) <-
           Workflows.get_workflow(workflow_id,
             include: [:edges, :jobs, :triggers]
           ),
         :ok <- authorize_read_workflow(conn, workflow) do
      json(conn, %{workflow: workflow, errors: %{}})
    else
      nil -> {:error, :not_found}
      error -> error
    end
    |> then(&maybe_handle_error(conn, &1, workflow_id))
  end

  @doc """
  Updates an existing workflow.

  Modifies a workflow's structure, including its jobs, triggers, and edges.
  Validates the updated workflow forms a valid DAG. Prevents updates while
  workflow is being edited in the UI (active presence).

  ## Parameters

  - `conn` - The Plug connection struct with the current resource assigned
  - `params` - Map containing:
    - `project_id` - Project UUID (required, must match workflow's project)
    - `id` - Workflow UUID (required)
    - `name` - Updated workflow name (optional)
    - `jobs` - Updated jobs list (optional)
    - `triggers` - Updated triggers list (optional, cannot replace existing)
    - `edges` - Updated edges list (optional)

  ## Returns

  - `200 OK` with updated workflow JSON on success
  - `422 Unprocessable Entity` with validation errors
  - `409 Conflict` if workflow has active presence
  - `403 Forbidden` if user lacks write access
  - `404 Not Found` if workflow doesn't exist

  ## Examples

      PATCH /api/workflows/workflow-uuid-1?project_id=a1b2c3d4-...
      {
        "name": "Updated Pipeline Name",
        "jobs": [...]
      }
  """
  @spec update(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def update(conn, %{"project_id" => project_id, "id" => workflow_id} = params) do
    with :ok <- validate_project_id(conn.body_params, project_id),
         :ok <- validate_workflow_id(conn.body_params, workflow_id),
         :ok <- authorize_write(conn, project_id),
         {:ok, workflow} <- get_workflow(workflow_id, project_id),
         :ok <- authorize_write(conn, workflow),
         {:ok, workflow} <-
           save_workflow(workflow, params, conn.assigns.current_resource) do
      json(conn, %{workflow: workflow, errors: %{}})
    end
    |> then(&maybe_handle_error(conn, &1, workflow_id))
  end

  defp count_enabled_triggers(params),
    do: params |> Map.get("triggers", []) |> Enum.count(& &1["enabled"])

  defp save_workflow(%{"project_id" => project_id} = params, user) do
    active_triggers_count = count_enabled_triggers(params)

    if active_triggers_count > 1 do
      {:error, :too_many_active_triggers}
    else
      save_workflow(params, active_triggers_count > 0, project_id, user)
    end
  end

  defp save_workflow(
         %{triggers: triggers} = workflow,
         params,
         user
       ) do
    changes_triggers? = Map.has_key?(params, "triggers")

    triggers_ids =
      params
      |> Map.get("triggers", [])
      |> Enum.map(& &1["id"])

    active_triggers_count = count_enabled_triggers(params)

    cond do
      changes_triggers? and Enum.any?(triggers, &(&1.id not in triggers_ids)) ->
        {:error, :cannot_replace_trigger}

      active_triggers_count > 1 ->
        {:error, :too_many_active_triggers}

      :else ->
        workflow
        |> Workflows.change_workflow(params)
        |> save_workflow(active_triggers_count > 0, workflow.project_id, user)
    end
  end

  defp save_workflow(params_or_changeset, activate?, project_id, user) do
    with :ok <- limit_workflow_activation(activate?, project_id),
         {params_or_changeset, ids_map} <-
           remap_arbitrary_ids(params_or_changeset),
         :ok <- validate_workflow(params_or_changeset, ids_map),
         {:error, %{changes: changes} = _changeset} <-
           Workflows.save_workflow(params_or_changeset, user) do
      triggers_with_errors = map_errors_to_ids(changes[:triggers])
      jobs_with_errors = map_errors_to_ids(changes[:jobs])
      edges_with_errors = map_errors_to_ids(changes[:edges])

      cond do
        Enum.any?(triggers_with_errors) ->
          {:error, {:invalid_triggers, triggers_with_errors, ids_map}}

        Enum.any?(jobs_with_errors) ->
          {:error, {:invalid_jobs, jobs_with_errors, ids_map}}

        Enum.any?(edges_with_errors) ->
          {:error, {:invalid_edges, edges_with_errors, ids_map}}

        :else ->
          {:error, :invalid_workflow}
      end
    end
  end

  # list of edges, jobs or triggers
  defp map_errors_to_ids(nil), do: Map.new()

  defp map_errors_to_ids(list) do
    list
    |> Enum.filter(&Enum.any?(&1.errors))
    |> Map.new(&{Ecto.Changeset.fetch_field!(&1, :id), ChangesetJSON.errors(&1)})
  end

  defp validate_workflow(%Changeset{} = changeset, ids_map) do
    edges = Changeset.get_field(changeset, :edges)
    jobs = Changeset.get_field(changeset, :jobs)
    triggers = Changeset.get_field(changeset, :triggers)

    validate_workflow(edges, jobs, triggers, ids_map)
  end

  defp validate_workflow(
         %{
           "edges" => edges,
           "jobs" => jobs,
           "triggers" => triggers
         },
         ids_map
       ),
       do: validate_workflow(edges, jobs, triggers, ids_map)

  defp validate_workflow(edges, jobs, triggers, ids_map) do
    # {:ok, _ids} <- validate_ids(edges),
    with {:ok, triggers_ids} <- validate_ids(triggers),
         {:ok, _ids} <- validate_ids(jobs),
         {:ok, source_trigger_id} <- get_initial_node(edges, triggers_ids) do
      edges
      |> make_graph()
      |> Graph.traverse(source_trigger_id)
      |> case do
        {:error, :graph_has_a_cycle, node_id} ->
          client_id =
            Enum.find_value(ids_map, fn {client_id, id} ->
              if id == node_id, do: client_id
            end)

          {:error, :graph_has_a_cycle, client_id}

        result ->
          result
      end
    end
  end

  defp validate_ids(list) do
    Enum.reduce_while(list, [], fn item, acc ->
      case Map.get(item, :id) || Map.get(item, "id") do
        nil ->
          {:halt, {:error, :missing_id}}

        id ->
          case Ecto.UUID.dump(id) do
            {:ok, _bin} -> {:cont, [id | acc]}
            :error -> {:halt, {:error, :invalid_id, id}}
          end
      end
    end)
    |> then(fn result ->
      with ids_list when is_list(ids_list) <- result, do: {:ok, ids_list}
    end)
  end

  defp get_initial_node(edges, triggers_ids, all_enabled \\ false) do
    edges
    |> Enum.map(
      &(Map.get(&1, :source_trigger_id) || Map.get(&1, "source_trigger_id"))
    )
    |> Enum.filter(&(&1 in triggers_ids))
    |> case do
      [] ->
        {:error, :edges_misses_a_trigger}

      [source_trigger_id] ->
        {:ok, source_trigger_id}

      _list ->
        if all_enabled do
          {:error, :edges_has_many_triggers}
        else
          edges
          |> Enum.filter(&(Map.get(&1, :enabled) || Map.get(&1, "enabled")))
          |> get_initial_node(triggers_ids, true)
        end
    end
  end

  defp make_graph(edges) do
    Enum.reduce(edges, Graph.new(), fn
      %Edge{} = edge, graph ->
        Graph.add_edge(graph, edge)

      edge, graph ->
        edge
        |> Map.take(["source_trigger_id", "source_job_id", "target_job_id"])
        |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)
        |> then(&Graph.add_edge(graph, struct(Edge, &1)))
    end)
  end

  defp get_workflow(workflow_id, project_id) do
    case Workflows.get_workflow(workflow_id, include: [:edges, :jobs, :triggers]) do
      nil -> {:error, :not_found}
      %{project_id: ^project_id} = workflow -> {:ok, workflow}
      _project_mismatch -> {:error, :bad_request}
    end
  end

  defp validate_uuid(project_id) do
    case Ecto.UUID.dump(to_string(project_id)) do
      {:ok, _bin} -> :ok
      :error -> {:error, :invalid_id, project_id}
    end
  end

  defp validate_workflow_id(%{"id" => workflow_id}, workflow_id),
    do: validate_uuid(workflow_id)

  defp validate_workflow_id(%{"id" => _workflow_id1}, _workflow_id2),
    do: {:error, :invalid_path_workflow_id}

  defp validate_workflow_id(_no_body_id, _workflow_id2), do: :ok

  defp validate_project_id(%{"project_id" => project_id}, project_id),
    do: validate_uuid(project_id)

  defp validate_project_id(%{"project_id" => _project_id1}, _project_id2),
    do: {:error, :invalid_project_id}

  defp validate_project_id(_patch, project_id),
    do: validate_uuid(project_id)

  defp authorize_write(_conn, %Workflow{name: name} = workflow) do
    if Presence.has_any_presence?(workflow) do
      {:error, :conflict, name}
    else
      :ok
    end
  end

  defp authorize_write(conn, project_id) do
    authorize_for_project(conn, project_id, :access_write)
  end

  defp authorize_read(conn, project_id) do
    authorize_for_project(conn, project_id, :access_read)
  end

  defp authorize_read_workflow(conn, %Workflow{project_id: project_id}) do
    authorize_read(conn, project_id)
  end

  defp authorize_for_project(conn, project_id, access) do
    project = Repo.get(Project, project_id)

    Permissions.can(
      Lightning.Policies.Workflows,
      access,
      conn.assigns.current_resource,
      project
    )
  end

  defp maybe_handle_error(conn, result, workflow_id \\ nil)

  defp maybe_handle_error(conn, {:error, :not_found}, workflow_id) do
    conn
    |> put_status(:not_found)
    |> json(%{id: workflow_id, errors: ["Not Found"]})
  end

  defp maybe_handle_error(_conn, result, _workflow_id) when is_map(result),
    do: result

  defp maybe_handle_error(conn, {:error, :conflict, name}, workflow_id),
    do:
      conn
      |> put_status(:conflict)
      |> json(%{
        id: workflow_id,
        errors: %{
          workflow: [
            "Cannot save a workflow (#{name}) while it is being edited on the App UI"
          ]
        }
      })

  defp maybe_handle_error(conn, {:error, :invalid_id, id}, workflow_id),
    do:
      reply_422(
        conn,
        workflow_id,
        :workflow,
        "Id #{id} should be a UUID."
      )

  defp maybe_handle_error(
         conn,
         {:error, :invalid_path_workflow_id},
         workflow_id
       ),
       do:
         reply_422(
           conn,
           workflow_id,
           :id,
           "Workflow ID doesn't match with the one on the path."
         )

  defp maybe_handle_error(conn, {:error, :missing_id}, workflow_id),
    do:
      reply_422(
        conn,
        workflow_id,
        :workflow,
        "All jobs and triggers should have an id (UUID)."
      )

  @reason_entity_field %{
    invalid_triggers: {"Trigger", :triggers},
    invalid_jobs: {"Job", :jobs},
    invalid_edges: {"Edge", :edges}
  }
  defp maybe_handle_error(
         conn,
         {:error, {reason, id_to_errors_map, ids_map}},
         workflow_id
       )
       when reason in [:invalid_triggers, :invalid_jobs, :invalid_edges] do
    {entity, workflow_field} = Map.get(@reason_entity_field, reason)

    client_ids = Map.new(ids_map, fn {k, v} -> {v, k} end)

    error_msgs =
      id_to_errors_map
      |> Enum.map(fn {id, errors} ->
        errors =
          Enum.map(errors, fn
            {field, [error]} -> "#{field}: #{error}"
            {field, errors} -> "#{field}: #{inspect(errors)}"
          end)

        "#{entity} #{Map.get(client_ids, id, id)} has the errors: [#{errors}]"
      end)

    reply_422(
      conn,
      workflow_id,
      workflow_field,
      error_msgs
    )
  end

  defp maybe_handle_error(
         conn,
         {:error, :too_many_workflows, %Message{text: error_msg}},
         workflow_id
       ) do
    reply_422(
      conn,
      workflow_id,
      :project_id,
      error_msg
    )
  end

  defp maybe_handle_error(conn, {:error, reason}, workflow_id)
       when reason in [:invalid_project_id, :invalid_project_id_format] do
    case reason do
      :invalid_project_id ->
        "The project_id of the body does not match the one the path."

      :invalid_project_id_format ->
        "The project_id is not a UUID."
    end
    |> then(
      &reply_422(
        conn,
        workflow_id,
        :project_id,
        &1
      )
    )
  end

  defp maybe_handle_error(conn, result, workflow_id)
       when is_tuple(result) do
    case result do
      {:error, :invalid_jobs_ids, job_ids} ->
        reply_422(
          conn,
          workflow_id,
          :jobs,
          "The jobs #{inspect(job_ids)} should be present both in the jobs and on an edge."
        )

      {:error, :edges_misses_a_trigger} ->
        reply_422(
          conn,
          workflow_id,
          :edges,
          "Missing edge with source_trigger_id."
        )

      {:error, :multiple_targets_for_trigger} ->
        reply_422(
          conn,
          workflow_id,
          :edges,
          "source_trigger_id must have a single target."
        )

      {:error, :edges_has_many_triggers} ->
        reply_422(
          conn,
          workflow_id,
          :edges,
          "There should be only one enabled edge with source_trigger_id."
        )

      {:error, :graph_has_a_cycle, node_id} ->
        reply_422(
          conn,
          workflow_id,
          :edges,
          "Cycle detected on job #{node_id}."
        )

      {:error, :cannot_replace_trigger} ->
        reply_422(
          conn,
          workflow_id,
          :triggers,
          "A trigger cannot be replaced, only edited or added."
        )

      {:error, :too_many_active_triggers} ->
        reply_422(
          conn,
          workflow_id,
          :triggers,
          "A workflow can have only one trigger enabled at a time."
        )

      result ->
        result
    end
  end

  defp reply_422(conn, workflow_id, field, msgs) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{id: workflow_id, errors: %{field => List.wrap(msgs)}})
  end

  defp remap_arbitrary_ids(
         %{"jobs" => jobs, "edges" => edges, "triggers" => triggers} = workflow
       ) do
    {jobs, ids_map} =
      Enum.map_reduce(jobs, Map.new(), fn %{"id" => client_id} = job, ids ->
        insert_uuid = Ecto.UUID.generate()
        {Map.put(job, "id", insert_uuid), Map.put(ids, client_id, insert_uuid)}
      end)

    {triggers, ids_map} =
      Enum.map_reduce(triggers, ids_map, fn %{"id" => client_id} = trigger,
                                            ids ->
        insert_uuid = Ecto.UUID.generate()

        {Map.put(trigger, "id", insert_uuid),
         Map.put(ids, client_id, insert_uuid)}
      end)

    edges =
      Enum.map(edges, fn edge ->
        edge
        |> Map.update("source_job_id", nil, &Map.get(ids_map, &1))
        |> Map.update("source_trigger_id", nil, &Map.get(ids_map, &1))
        |> Map.update("target_job_id", nil, &Map.get(ids_map, &1))
      end)

    {
      Map.merge(workflow, %{
        "jobs" => jobs,
        "edges" => edges,
        "triggers" => triggers
      }),
      ids_map
    }
  end

  defp remap_arbitrary_ids(changeset) do
    {changeset, Map.new()}
  end
end
