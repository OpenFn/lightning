defmodule Lightning.Jobs do
  @moduledoc """
  The Jobs context.
  """

  import Ecto.Query, warn: false
  alias Lightning.Repo

  alias Lightning.Workflows.{Edge, Workflow}
  alias Lightning.Workflows.{Job, Query}
  alias Lightning.Projects.Project

  @doc """
  Returns the list of jobs.
  """
  def list_jobs do
    Repo.all(Job |> preload([:workflow]))
  end

  def list_active_cron_jobs do
    Query.enabled_cron_jobs_by_edge()
    |> Repo.all()
    |> Enum.map(fn e -> e.target_job end)
  end

  @spec jobs_for_project_query(Project.t()) :: Ecto.Queryable.t()
  def jobs_for_project_query(%Project{} = project) do
    Query.jobs_for(project)
  end

  @spec jobs_for_project(Project.t()) :: [Job.t()]
  def jobs_for_project(%Project{} = project) do
    jobs_for_project_query(project) |> Repo.all()
  end

  @doc """
  Returns the list of jobs excluding the one given.
  """
  @spec get_upstream_jobs_for(Job.t()) :: [Job.t()]
  def get_upstream_jobs_for(%{workflow_id: workflow_id, id: id}) do
    case [workflow_id, id] do
      [nil, nil] ->
        []

      [workflow_id, nil] ->
        from(j in Job,
          where: j.workflow_id == ^workflow_id,
          preload: [:workflow]
        )
        |> Repo.all()

      [workflow_id, id] ->
        from(j in Job,
          where: j.workflow_id == ^workflow_id,
          where: j.id != ^id,
          preload: [:workflow]
        )
        |> Repo.all()
    end
  end

  @doc """
  Returns the list of downstream jobs for a given job, optionally matching a
  specific trigger type.
  When downstream_jobs_for is called without a trigger that means its between jobs
  when it called with a trigger that means we are starting from outside the pipeline
  """
  @spec get_downstream_jobs_for(
          Job.t() | Ecto.UUID.t(),
          Edge.edge_condition() | nil
        ) :: [
          Job.t()
        ]
  def get_downstream_jobs_for(job, edge_condition \\ nil)

  def get_downstream_jobs_for(%Job{id: job_id}, edge_condition) do
    get_downstream_jobs_for(job_id, edge_condition)
  end

  def get_downstream_jobs_for(job_id, nil) do
    downstream_query(job_id)
    |> Repo.all()
  end

  def get_downstream_jobs_for(job_id, edge_condition) do
    downstream_query(job_id)
    |> where([_, e], e.condition == ^edge_condition)
    |> Repo.all()
  end

  defp downstream_query(job_id) do
    from(target_job in Job,
      join: e in Edge,
      on:
        e.source_job_id == ^job_id and
          target_job.id == e.target_job_id,
      preload: [:workflow]
    )
  end

  @doc """
  Gets a single job.

  Raises `Ecto.NoResultsError` if the Job does not exist.

  ## Examples

      iex> get_job!(123)
      %Job{}

      iex> get_job!(456)
      ** (Ecto.NoResultsError)

  """
  def get_job!(id), do: Repo.get!(Job |> preload([:workflow]), id)

  def get_job_with_credential(id) do
    Repo.get(Job, id)
    |> Repo.preload(:credential)
  end

  @doc """
  Creates a job.

  ## Examples

      iex> create_job(%{field: value})
      {:ok, %Job{}}

      iex> create_job(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_job(attrs \\ %{}) do
    %Job{}
    |> Job.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a job.

  ## Examples

      iex> update_job(job, %{field: new_value})
      {:ok, %Job{}}

      iex> update_job(job, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_job(%Job{} = job, attrs) do
    job
    |> Job.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking job changes.

  ## Examples

      iex> change_job(job)
      %Ecto.Changeset{data: %Job{}}

  """
  def change_job(%Job{} = job, attrs \\ %{}) do
    Job.changeset(job, attrs)
  end

  @spec list_jobs_for_workflow(Workflow.t()) :: [Job.t(), ...] | []
  def list_jobs_for_workflow(%Workflow{id: workflow_id}) do
    query =
      from j in Job,
        where: j.workflow_id == ^workflow_id,
        order_by: j.name,
        select: [:id, :name]

    Repo.all(query)
  end
end
