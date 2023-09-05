defmodule Lightning.Workflows do
  @moduledoc """
  The Workflows context.
  """

  import Ecto.Query
  alias Lightning.Repo
  alias Lightning.Workflows.{Edge, Workflow}
  alias Lightning.Projects.Project
  alias Lightning.{Jobs, Jobs.Trigger}

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
  Deletes a workflow.

  ## Examples

      iex> delete_workflow(workflow)
      {:ok, %Workflow{}}

      iex> delete_workflow(workflow)
      {:error, %Ecto.Changeset{}}

  """
  def delete_workflow(%Workflow{} = workflow) do
    Repo.delete(workflow)
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
  Retrieves a list of Workflows with their jobs and triggers preloaded.
  """
  @spec get_workflows_for(Project.t()) :: [Workflow.t()]
  def get_workflows_for(%Project{} = project) do
    get_workflows_for_query(project)
    |> Repo.all()
  end

  def get_workflows_for_query(%Project{} = project) do
    from(w in Workflow,
      preload: [:triggers, :edges, jobs: [:credential, :workflow]],
      where: is_nil(w.deleted_at) and w.project_id == ^project.id,
      order_by: [asc: w.name]
    )
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
    workflow_jobs_query =
      from(j in Lightning.Jobs.Job,
        where: j.workflow_id == ^workflow.id
      )

    Repo.transaction(fn ->
      Workflow.request_deletion_changeset(workflow, %{
        "deleted_at" => DateTime.utc_now()
      })
      |> Repo.update()

      Repo.update_all(workflow_jobs_query, set: [enabled: false])
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
  Returns a list of edges with jobs to execute, given a current timestamp in Unix. This is
  used by the scheduler, which calls this function once every minute.
  """
  @spec get_edges_for_cron_execution(DateTime.t()) :: [Edge.t()]
  def get_edges_for_cron_execution(datetime) do
    cron_edges =
      Jobs.Query.enabled_cron_jobs_by_edge()
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
end
