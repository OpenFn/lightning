defmodule Lightning.Workflows do
  @moduledoc """
  The Workflows context.
  """

  import Ecto.Query

  alias Lightning.Projects.Project
  alias Lightning.Repo
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Query
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow

  @doc """
  Returns the list of workflows.

  ## Examples

      iex> list_workflows()
      [%Workflow{}, ...]

  """
  def list_workflows do
    Repo.all(Workflow)
  end

  @doc """
  Gets a single workflow.

  Raises `Ecto.NoResultsError` if the Workflow does not exist.

  ## Examples

      iex> get_workflow!(123)
      %Workflow{}

      iex> get_workflow!(456)
      ** (Ecto.NoResultsError)

  """
  def get_workflow!(id), do: Repo.get!(Workflow, id)

  def get_workflow(id), do: Repo.get(Workflow, id)

  @doc """
  Creates a workflow.

  ## Examples

      iex> create_workflow(%{field: value})
      {:ok, %Workflow{}}

      iex> create_workflow(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_workflow(attrs \\ %{}) do
    %Workflow{}
    |> Workflow.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a workflow.

  ## Examples

      iex> update_workflow(workflow, %{field: new_value})
      {:ok, %Workflow{}}

      iex> update_workflow(workflow, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_workflow(%Workflow{} = workflow, attrs) do
    workflow
    |> maybe_preload([:jobs, :triggers, :edges], attrs)
    |> Workflow.changeset(attrs)
    |> Repo.update()
  end

  # Helper to preload associations only if they are present in the attributes
  defp maybe_preload(workflow, assoc, attrs) do
    List.wrap(assoc)
    |> Enum.filter(&Map.has_key?(attrs, &1))
    |> case do
      [] -> workflow
      assocs -> Repo.preload(workflow, assocs)
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking workflow changes.

  ## Examples

      iex> change_workflow(workflow)
      %Ecto.Changeset{data: %Workflow{}}

  """
  def change_workflow(%Workflow{} = workflow, attrs \\ %{}) do
    Workflow.changeset(workflow, attrs)
  end

  @doc """
  Retrieves a list of active Workflows with their jobs and triggers preloaded.
  """
  @spec get_workflows_for(Project.t()) :: [Workflow.t()]
  def get_workflows_for(%Project{} = project) do
    from(w in Workflow,
      preload: [:triggers, :edges, jobs: [:credential, :workflow]],
      where: is_nil(w.deleted_at) and w.project_id == ^project.id,
      order_by: [asc: w.name]
    )
    |> Repo.all()
  end

  @spec to_project_space([Workflow.t()]) :: %{}
  def to_project_space(workflows) when is_list(workflows) do
    %{
      "jobs" =>
        workflows
        |> Enum.flat_map(fn w -> w.jobs end)
        |> Enum.map(fn job ->
          %{
            "id" => job.id,
            "name" => job.name,
            "adaptor" => job.adaptor,
            "workflowId" => job.workflow_id
            # "trigger" => trigger_for_project_space(job)
          }
        end),
      "workflows" =>
        workflows
        |> Enum.map(fn w -> %{"id" => w.id, "name" => w.name} end)
    }
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the workflow request_deletion.

  ## Examples

      iex> change_request_deletion(workflow)
      %Ecto.Changeset{data: %Workflow{}}

  """
  def mark_for_deletion(workflow, _attrs \\ %{}) do
    workflow_triggers_query =
      from(t in Lightning.Workflows.Trigger,
        where: t.workflow_id == ^workflow.id
      )

    Repo.transaction(fn ->
      Workflow.request_deletion_changeset(workflow, %{
        "deleted_at" => DateTime.utc_now()
      })
      |> Repo.update()

      Repo.update_all(workflow_triggers_query, set: [enabled: false])
    end)
  end

  @doc """
  Creates an edge
  """
  def create_edge(attrs) do
    attrs
    |> Edge.new()
    |> Repo.insert()
  end

  @doc """
  Gets a Single Edge by it's webhook trigger.
  """
  def get_webhook_trigger(path, opts \\ []) when is_binary(path) do
    preloads = opts |> Keyword.get(:include, [])

    from(t in Trigger,
      where:
        fragment(
          "coalesce(?, ?)",
          t.custom_path,
          type(t.id, :string)
        ) == ^path,
      preload: ^preloads
    )
    |> Repo.one()
  end

  @doc """
  Gets a single `Trigger` by its `custom_path` or `id`.

  ## Parameters
  - `path`: A binary string representing the `custom_path` or `id` of the trigger.

  ## Returns
  - Returns a `Trigger` struct if a trigger is found.
  - Returns `nil` if no trigger is found for the given `path`.

  ## Examples

  ```
  Lightning.Workflows.get_trigger_by_webhook("some_path_or_id")
  # => %Trigger{id: 1, custom_path: "some_path_or_id", ...}

  Lightning.Workflows.get_trigger_by_webhook("non_existent_path_or_id")
  # => nil
  ```
  """
  def get_trigger_by_webhook(path) when is_binary(path) do
    from(t in Trigger,
      where:
        fragment("coalesce(?, ?)", t.custom_path, type(t.id, :string)) == ^path
    )
    |> Repo.one()
  end

  @doc """
  Gets an `Edge` by its associated `Trigger`.

  ## Parameters
  - `%Trigger{id: trigger_id}`: A `Trigger` struct from which the associated `Edge` is to be found.

  ## Returns
  - Returns an `Edge` struct preloaded with its `source_trigger` and `target_job` if found.
  - Returns `nil` if no `Edge` is associated with the given `Trigger`.

  ## Examples
  ```
  trigger = %Trigger{id: 1, ...}
  Lightning.Workflows.get_edge_by_trigger(trigger)
  # => %Edge{source_trigger: %Trigger{}, target_job: %Job{}, ...}

  non_existent_trigger = %Trigger{id: 999, ...}
  Lightning.Workflows.get_edge_by_trigger(non_existent_trigger)
  # => nil
  ```
  """
  def get_edge_by_trigger(%Trigger{id: trigger_id}) do
    from(e in Edge,
      join: j in Job,
      on: j.id == e.target_job_id,
      left_join: t in Trigger,
      on: e.source_trigger_id == t.id,
      where: t.id == ^trigger_id,
      preload: [:source_trigger, :target_job]
    )
    |> Repo.one()
  end

  @doc """
  Returns a list of edges with jobs to execute, given a current timestamp in Unix. This is
  used by the scheduler, which calls this function once every minute.
  """
  @spec get_edges_for_cron_execution(DateTime.t()) :: [Edge.t()]
  def get_edges_for_cron_execution(datetime) do
    cron_edges =
      Query.enabled_cron_jobs_by_edge()
      |> Repo.all()

    for e <- cron_edges,
        has_matching_trigger(e, datetime),
        do: e
  end

  defp has_matching_trigger(edge, datetime) do
    cron_expression = edge.source_trigger.cron_expression

    with {:ok, cron} <- Crontab.CronExpression.Parser.parse(cron_expression),
         true <- Crontab.DateChecker.matches_date?(cron, datetime) do
      edge
    else
      _ -> false
    end
  end

  @doc """
  Builds a Trigger
  """
  def build_trigger(attrs) do
    attrs
    |> Trigger.new()
    |> Repo.insert()
  end

  @doc """
  Updates a trigger
  """
  def update_trigger(trigger, attrs) do
    trigger
    |> Trigger.changeset(attrs)
    |> Repo.update()
  end

  @doc """
    Check if workflow exist
  """
  def workflow_exists?(project_id, workflow_name) do
    query =
      from w in Workflow,
        where: w.project_id == ^project_id and w.name == ^workflow_name

    Repo.exists?(query)
  end

  @doc """
  A way to ensure the consistency of nodes.
  This query orders jobs based on their `inserted_at` timestamps in ascending order
  """
  def jobs_ordered_subquery do
    from(j in Job, order_by: [asc: j.inserted_at])
  end
end
