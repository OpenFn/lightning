defmodule LightningWeb.API.WorkflowsController do
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

  def index(conn, %{"project_id" => project_id}) do
    with :ok <- authorize_read(conn, project_id) do
      list =
        Workflows.list_project_workflows(project_id,
          include: [:edges, :jobs, :triggers]
        )

      json(conn, %{workflows: list, errors: []})
    end
  end

  def create(conn, %{"project_id" => project_id} = params) do
    with :ok <- validate_project_id(conn.body_params, project_id),
         :ok <- authorize_write(conn, project_id),
         {:ok, %{id: workflow_id}} <-
           save_workflow(params, conn.assigns.current_resource) do
      conn
      |> put_status(:created)
      |> json(%{id: workflow_id, errors: []})
    end
    |> then(&maybe_handle_error(conn, &1))
  end

  def show(conn, %{"project_id" => project_id, "id" => workflow_id}) do
    with :ok <- validate_uuid(project_id),
         :ok <- validate_uuid(workflow_id),
         :ok <- authorize_read(conn, project_id),
         {:ok, workflow} <- get_workflow(workflow_id, project_id) do
      json(conn, %{workflow: workflow, errors: []})
    end
    |> then(&maybe_handle_error(conn, &1))
  end

  def update(conn, %{"project_id" => project_id, "id" => workflow_id} = params) do
    with :ok <- validate_project_id(conn.body_params, project_id),
         :ok <- validate_workflow_id(conn.body_params, workflow_id),
         :ok <- authorize_write(conn, project_id),
         {:ok, workflow} <- get_workflow(workflow_id, project_id),
         :ok <- authorize_write(conn, workflow),
         {:ok, %{id: workflow_id}} <-
           save_workflow(workflow, params, conn.assigns.current_resource) do
      json(conn, %{id: workflow_id, errors: []})
    end
    |> then(&maybe_handle_error(conn, &1, workflow_id))
  end

  defp count_enabled_triggers(params),
    do: params |> Map.get("triggers", []) |> Enum.count(& &1["enabled"])

  defp save_workflow(%{"project_id" => project_id} = params, user) do
    active_triggers_count = count_enabled_triggers(params)

    cond do
      active_triggers_count > 1 ->
        {:error, :too_many_active_triggers}

      :else ->
        save_workflow(params, active_triggers_count > 0, project_id, user)
    end
  end

  defp save_workflow(
         %{id: workflow_id, triggers: triggers} = workflow,
         params,
         user
       ) do
    changes_triggers? = Map.has_key?(params, "triggers")

    triggers_ids =
      params
      |> Map.get("triggers", [])
      |> Enum.map(& &1["id"])

    active_triggers_count = count_enabled_triggers(params)

    IO.inspect(workflow_id)
    has_external_reference? = has_external_reference?(params, workflow_id)

    IO.inspect(has_external_reference?,
      label: :has_external_reference?
    )

    cond do
      changes_triggers? and Enum.any?(triggers, &(&1.id not in triggers_ids)) ->
        {:error, :cannot_replace_trigger}

      active_triggers_count > 1 ->
        {:error, :too_many_active_triggers}

      # has_external_reference? ->
      #   {:error, :invalid_workflow_id}

      :else ->
        IO.inspect params
        workflow
        |> Workflows.change_workflow(params)
        |> save_workflow(active_triggers_count > 0, workflow.project_id, user)
    end
  end

  defp save_workflow(params_or_changeset, activate?, project_id, user) do
    IO.inspect params_or_changeset.changes
    with :ok <- limit_workflow_activation(activate?, project_id),
         :ok <- validate_workflow(params_or_changeset),
         {:error, %{changes: changes} = _changeset} <-
           Workflows.save_workflow(params_or_changeset, user) do
      triggers_with_errors = map_errors_to_ids(changes[:triggers])
      jobs_with_errors = map_errors_to_ids(changes[:jobs])
      edges_with_errors = map_errors_to_ids(changes[:edges])

      # duplicated_ids =
      #   [triggers_with_errors, jobs_with_errors, edges_with_errors]
      #   |> Enum.concat()
      #   |> Enum.filter(fn {_id, errors} -> Map.has_key?(errors, :id) end)

      cond do
        # Enum.any?(duplicated_ids) ->
        #   {:error, {:duplicated_ids, Enum.map(duplicated_ids, &elem(&1, 0))}}

        Enum.any?(triggers_with_errors) ->
          {:error, {:invalid_triggers, triggers_with_errors}}

        Enum.any?(jobs_with_errors) ->
          {:error, {:invalid_jobs, jobs_with_errors}}

        Enum.any?(edges_with_errors) ->
          {:error, {:invalid_edges, edges_with_errors}}

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

  defp has_external_reference?(params, workflow_id) when is_map(params) do
    has_external_reference?(params["edges"], workflow_id) or
      has_external_reference?(params["jobs"], workflow_id) or
      has_external_reference?(params["triggers"], workflow_id)
  end

  defp has_external_reference?(list, workflow_id) when is_list(list) do
    Enum.any?(list, &(&1["workflow_id"] && &1["workflow_id"] != workflow_id))
  end

  defp has_external_reference?(_other, _workflow_id), do: false

  defp validate_workflow(%Changeset{} = changeset) do
    edges = Changeset.get_field(changeset, :edges)
    jobs = Changeset.get_field(changeset, :jobs)
    triggers = Changeset.get_field(changeset, :triggers)

    validate_workflow(edges, jobs, triggers)
  end

  defp validate_workflow(%{
         "edges" => edges,
         "jobs" => jobs,
         "triggers" => triggers
       }),
       do: validate_workflow(edges, jobs, triggers)

  defp validate_workflow(edges, jobs, triggers) do
    # {:ok, _ids} <- validate_ids(edges),
    with {:ok, triggers_ids} <- validate_ids(triggers),
         {:ok, _ids} <- validate_ids(jobs),
         {:ok, source_trigger_id} <- get_initial_node(edges, triggers_ids),
         graph <- make_graph(edges) do
        #  :ok <- validate_jobs(graph, jobs, triggers_ids) do
      Graph.traverse(graph, source_trigger_id)
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

  defp get_initial_node(edges, triggers_ids) do
    edges
    |> Enum.map(
      &(Map.get(&1, :source_trigger_id) || Map.get(&1, "source_trigger_id"))
    )
    |> Enum.filter(&(&1 in triggers_ids))
    |> case do
      [] -> {:error, :edges_misses_a_trigger}
      [source_trigger_id] -> {:ok, source_trigger_id}
      list -> {:error, :edges_has_many_triggers, list}
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

  # defp validate_jobs(graph, jobs, triggers_ids) do
  #   jobs
  #   |> MapSet.new(&(Map.get(&1, :id) || Map.get(&1, "id")))
  #   |> MapSet.symmetric_difference(Graph.nodes(graph, as: MapSet.new()))
  #   |> Enum.reject(&(&1 in triggers_ids or is_nil(&1)))
  #   |> case do
  #     [] -> :ok
  #     invalid_jobs_ids -> {:error, :invalid_jobs_ids, invalid_jobs_ids}
  #   end
  # end

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

  defp maybe_handle_error(conn, {:error, :invalid_workflow_id}, workflow_id),
    do:
      reply_422(
        conn,
        workflow_id,
        :workflow,
        "Edges, jobs and triggers cannot reference another workflow!"
      )

  defp maybe_handle_error(conn, {:error, :missing_id}, workflow_id),
    do:
      reply_422(
        conn,
        workflow_id,
        :workflow,
        "All jobs and triggers should have an id (UUID)."
      )

  defp maybe_handle_error(conn, {:error, {:duplicated_ids, ids}}, workflow_id),
    do:
      reply_422(
        conn,
        workflow_id,
        :workflow,
        "The ids #{inspect(ids)} should be unique for all workflows."
      )

  @reason_entity_field %{
    invalid_triggers: {"Trigger", :triggers},
    invalid_jobs: {"Job", :jobs},
    invalid_edges: {"Edge", :edges}
  }
  defp maybe_handle_error(
         conn,
         {:error, {reason, id_to_errors_map}},
         workflow_id
       )
       when reason in [:invalid_triggers, :invalid_jobs, :invalid_edges] do
    {entity, workflow_field} = Map.get(@reason_entity_field, reason)

    error_msgs =
      id_to_errors_map
      |> Enum.map(fn {id, errors} ->
        errors =
          Enum.map(errors, fn
            {field, [error]} -> "#{field} #{error}"
            {field, errors} -> "#{field} #{inspect(errors)}"
          end)

        "#{entity} #{id} has the errors: [#{errors}]"
      end)

    reply_422(
      conn,
      workflow_id,
      workflow_field,
      error_msgs
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

      {:error, :multiple_targets_for_trigger, trigger_id} ->
        reply_422(
          conn,
          workflow_id,
          :edges,
          "Has multiple targets for trigger #{trigger_id}."
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

      {:error, :too_many_workflows, %Message{text: error_msg}} ->
        reply_422(
          conn,
          workflow_id,
          :project_id,
          error_msg
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
end
