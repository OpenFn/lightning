defmodule LightningWeb.API.WorkflowsController do
  use LightningWeb, :controller

  alias Ecto.Changeset

  alias Lightning.Extensions.Message
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Graph
  alias Lightning.Policies.Permissions
  alias Lightning.Projects.Project
  alias Lightning.Repo
  alias Lightning.Services.UsageLimiter
  alias Lightning.Workflows
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Presence
  alias Lightning.Workflows.Workflow

  action_fallback LightningWeb.FallbackController

  require Logger

  def index(conn, %{"project_id" => project_id}) do
    with :ok <- authorize_read(conn, project_id) do
      list =
        Workflows.list_project_workflows(project_id,
          include: [:edges, :jobs, :triggers]
        )

      json(conn, %{workflows: list, error: nil})
    end
  end

  def create(conn, %{"project_id" => project_id} = params) do
    with :ok <- validate_project_id(conn.body_params, project_id),
         :ok <- authorize_write(conn, project_id),
         {:ok, %{id: workflow_id}} <-
           save_workflow(params, conn.assigns.current_resource) do
      json(conn, %{id: workflow_id, error: nil})
    end
    |> then(&maybe_handle_error(conn, &1))
  end

  def show(conn, %{"project_id" => project_id, "id" => workflow_id}) do
    with :ok <- authorize_read(conn, project_id),
         {:ok, workflow} <- get_workflow(workflow_id, project_id) do
      json(conn, %{workflow: workflow, error: nil})
    end
  end

  def update(conn, %{"project_id" => project_id, "id" => workflow_id} = params) do
    with :ok <- validate_project_id(conn.body_params, project_id),
         :ok <- authorize_write(conn, project_id),
         {:ok, workflow} <- get_workflow(workflow_id, project_id),
         :ok <- authorize_write(conn, workflow),
         {:ok, %{id: workflow_id}} <-
           save_workflow(workflow, params, conn.assigns.current_resource) do
      json(conn, %{id: workflow_id, error: nil})
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

    has_external_reference? = has_external_reference?(params, workflow_id)

    cond do
      changes_triggers? and Enum.any?(triggers, &(&1.id not in triggers_ids)) ->
        {:error, :cannot_replace_trigger}

      active_triggers_count > 1 ->
        {:error, :too_many_active_triggers}

      has_external_reference? ->
        {:error, :invalid_workflow_id}

      :else ->
        workflow
        |> Workflows.change_workflow(params)
        |> save_workflow(active_triggers_count > 0, workflow.project_id, user)
    end
  end

  defp save_workflow(params_or_changeset, activate?, project_id, user) do
    with :ok <- check_limit(activate?, project_id),
         :ok <- validate_workflow(params_or_changeset),
         {:error, %{changes: changes} = _changeset} <-
           Workflows.save_workflow(params_or_changeset, user) do
      triggers_with_errors = Enum.filter(changes.triggers, &(&1.errors != []))
      jobs_with_errors = Enum.filter(changes.jobs, &(&1.errors != []))
      edges_with_errors = Enum.filter(changes.edges, &(&1.errors != []))

      duplicated_ids =
        [triggers_with_errors, jobs_with_errors, edges_with_errors]
        |> Enum.concat()
        |> Enum.filter(fn %{errors: errors} ->
          Enum.any?(errors, fn {field, _value} -> field == :id end)
        end)
        |> Enum.map(&Ecto.Changeset.fetch_field!(&1, :id))

      cond do
        Enum.any?(duplicated_ids) ->
          {:error, {:duplicated_ids, duplicated_ids}}

        Enum.any?(triggers_with_errors) ->
          ids =
            Enum.map(triggers_with_errors, &Ecto.Changeset.fetch_field!(&1, :id))

          {:error, {:invalid_triggers, ids}}

        Enum.any?(jobs_with_errors) ->
          ids = Enum.map(jobs_with_errors, &Ecto.Changeset.fetch_field!(&1, :id))
          {:error, {:invalid_jobs, ids}}

        Enum.any?(edges_with_errors) ->
          ids =
            Enum.map(edges_with_errors, &Ecto.Changeset.fetch_field!(&1, :id))

          {:error, {:invalid_edges, ids}}

        :else ->
          {:error, :invalid_workflow}
      end
    end
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

  defp check_limit(false = _activate?, _project_id), do: :ok

  defp check_limit(true = _activate?, project_id),
    do:
      UsageLimiter.limit_action(
        %Action{type: :activate_workflow},
        %Context{project_id: project_id}
      )

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
         graph <- make_graph(edges),
         :ok <- validate_jobs(graph, jobs, triggers_ids) do
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

  defp validate_jobs(graph, jobs, triggers_ids) do
    jobs
    |> MapSet.new(&(Map.get(&1, :id) || Map.get(&1, "id")))
    |> MapSet.symmetric_difference(Graph.nodes(graph, as: MapSet.new()))
    |> Enum.reject(&(&1 in triggers_ids or is_nil(&1)))
    |> case do
      [] -> :ok
      invalid_jobs_ids -> {:error, :invalid_jobs_ids, invalid_jobs_ids}
    end
  end

  defp get_workflow(workflow_id, project_id) do
    case Workflows.get_workflow(workflow_id, include: [:edges, :jobs, :triggers]) do
      nil -> {:error, :not_found}
      %{project_id: ^project_id} = workflow -> {:ok, workflow}
      _project_mismatch -> {:error, :bad_request}
    end
  end

  defp validate_project_id(%{"project_id" => project_id}, project_id), do: :ok

  defp validate_project_id(%{"project_id" => _project_id1}, _project_id2),
    do: {:error, :invalid_project_id}

  defp validate_project_id(_patch, _project_id), do: :ok

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

  defp maybe_handle_error(_conn, result, _workflow_id) when is_map(result),
    do: result

  defp maybe_handle_error(conn, {:error, :conflict, name}, workflow_id),
    do:
      conn
      |> put_status(:conflict)
      |> json(%{
        id: workflow_id,
        errors: %{
          id: [
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
        "These ids #{inspect(ids)} should be unique for all workflows."
      )

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

      # TBD
      # {:error, :multiple_targets_for_trigger, trigger_id} ->
      #   reply_422(
      #     conn,
      #     workflow_id,
      #     :edges,
      #     "Has multiple targets for trigger #{trigger_id}."
      #   )

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
          :trigger_id,
          "Cannot be replaced, only edited or added."
        )

      {:error, :too_many_active_triggers} ->
        reply_422(
          conn,
          workflow_id,
          :trigger_id,
          "A workflow can have only one trigger enabled at a time."
        )

      {:error, :invalid_project_id} ->
        reply_422(
          conn,
          workflow_id,
          :project_id,
          "The project_id of the body does not match one one the path."
        )

      {:error, :too_many_workflows, %Message{text: error_msg}} ->
        reply_422(
          conn,
          workflow_id,
          :project_id,
          error_msg
        )
    end
  end

  defp reply_422(conn, workflow_id, field, msg) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{id: workflow_id, errors: %{field => [msg]}})
  end
end
