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
    with :ok <- authorize_write(conn, project_id),
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

  defp save_workflow(%{triggers: triggers} = workflow, params, user) do
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
    with :ok <- check_limit(activate?, project_id),
         :ok <- validate_workflow(params_or_changeset) do
      Workflows.save_workflow(params_or_changeset, user)
    end
  end

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
    nodes_from_edges =
      edges
      |> Enum.reduce(Graph.new(), fn
        %Edge{} = edge, graph ->
          Graph.add_edge(graph, edge)

        edge, graph ->
          edge
          |> Map.take(["source_trigger_id", "source_job_id", "target_job_id"])
          |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)
          |> then(&Graph.add_edge(graph, &1))
      end)
      |> Graph.nodes(as: MapSet.new())

    triggers_ids =
      Enum.map(triggers, &(Map.get(&1, :id) || Map.get(&1, "id")))

    jobs
    |> MapSet.new(&(Map.get(&1, :id) || Map.get(&1, "id")))
    |> MapSet.symmetric_difference(nodes_from_edges)
    |> Enum.reject(&(&1 in triggers_ids))
    |> Enum.reject(&is_nil/1)
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

  defp maybe_handle_error(conn, result, workflow_id \\ nil) do
    case result do
      {:error, :conflict, name} ->
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

      {:error, :invalid_jobs_ids, job_ids} ->
        reply_422(
          conn,
          workflow_id,
          :jobs,
          "These jobs #{inspect(job_ids)} should be in the jobs and also be present in an edge."
        )

      {:error, :cannot_replace_trigger} ->
        reply_422(
          conn,
          workflow_id,
          :trigger_id,
          "Cannot be replaced, only edited or added."
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

      {:error, :too_many_active_triggers} ->
        reply_422(
          conn,
          workflow_id,
          :trigger_id,
          "A workflow can have only one trigger enabled at a time."
        )

      result ->
        result
    end
  end

  defp reply_422(conn, workflow_id, field, msg) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{id: workflow_id, errors: %{field => [msg]}})
  end
end
