defmodule Lightning.Jobs do
  @moduledoc """
  The Jobs context.
  """

  import Ecto.Query, warn: false
  alias Lightning.Repo

  alias Lightning.Jobs.{Job, Trigger}
  alias Lightning.Projects.Project

  @doc """
  Returns the list of jobs.
  """
  def list_jobs do
    Repo.all(Job |> preload(:trigger))
  end

  def list_active_cron_jobs do
    Repo.all(
      from j in Job,
        join: t in assoc(j, :trigger),
        where: t.type == :cron and j.enabled == true,
        preload: [trigger: t]
    )
  end

  @spec jobs_for_project_query(Project.t()) :: Ecto.Queryable.t()
  def jobs_for_project_query(%Project{} = project) do
    Ecto.assoc(project, :jobs) |> preload(:trigger)
  end

  @spec jobs_for_project(Project.t()) :: [Job.t()]
  def jobs_for_project(%Project{} = project) do
    jobs_for_project_query(project) |> Repo.all()
  end

  @doc """
  Returns the list of jobs excluding the one given.
  """
  @spec get_upstream_jobs_for(Job.t()) :: [Job.t()]
  def get_upstream_jobs_for(%Job{id: id}) do
    query = from(j in Job, preload: :trigger)

    if is_nil(id) do
      Repo.all(query)
    else
      from(j in query, where: j.id != ^id) |> Repo.all()
    end
  end

  @doc """
  Returns a list of jobs to execute, given a current timestamp in Unix. This is
  used by the scheduler, which calls this function once every minute.
  """
  @spec get_jobs_for_cron_execution(integer) :: [Job.t()]
  def get_jobs_for_cron_execution(timestamp) do
    list_active_cron_jobs()
    |> Enum.filter(fn job ->
      cron_expression = Map.get(Map.get(job, :trigger), :cron_expression)
      {:ok, cron} = Crontab.CronExpression.Parser.parse(cron_expression)
      datetime = timestamp |> DateTime.from_unix!(:millisecond)

      if Crontab.DateChecker.matches_date?(cron, datetime), do: job
    end)
  end

  @doc """
  Returns the list of downstream jobs for a given job, optionally matching a
  specific trigger type.
  """
  @spec get_downstream_jobs_for(
          Job.t() | Ecto.UUID.t(),
          Trigger.trigger_type() | nil
        ) :: [
          Job.t()
        ]
  def get_downstream_jobs_for(job, trigger_type \\ nil)

  def get_downstream_jobs_for(%Job{id: job_id}, trigger_type) do
    get_downstream_jobs_for(job_id, trigger_type)
  end

  def get_downstream_jobs_for(job_id, nil) do
    downstream_query(job_id)
    |> Repo.all()
  end

  def get_downstream_jobs_for(job_id, trigger_type) do
    downstream_query(job_id)
    |> where([_, t], t.type == ^trigger_type)
    |> Repo.all()
  end

  defp downstream_query(job_id) do
    from(j in Job,
      join: t in assoc(j, :trigger),
      where: t.upstream_job_id == ^job_id,
      preload: [trigger: t]
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
  def get_job!(id), do: Repo.get!(Job |> preload(:trigger), id)

  def get_job(id) do
    from(j in Job, preload: :trigger) |> Repo.get(id)
  end

  @doc """
  Gets a single job basic on it's webhook trigger.
  """
  def get_job_by_webhook(path) when is_binary(path) do
    from(j in Job,
      join: t in assoc(j, :trigger),
      where:
        fragment("coalesce(?, ?)", t.custom_path, type(j.id, :string)) == ^path,
      preload: [:trigger]
    )
    |> Repo.one()
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
    |> Job.add_to_workflow()
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
    |> Job.add_to_workflow()
    |> Repo.update()
  end

  @doc """
  Deletes a job.

  ## Examples

      iex> delete_job(job)
      {:ok, %Job{}}

      iex> delete_job(job)
      {:error, %Ecto.Changeset{}}

  """
  def delete_job(%Job{} = job) do
    Repo.delete(job)
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
end
