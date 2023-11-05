defmodule Lightning.Invocation.Query do
  @moduledoc """
  Query functions for working with Runs and Dataclips
  """
  import Ecto.Query

  alias Lightning.Accounts.User
  alias Lightning.Invocation.Run
  alias Lightning.Workflows.Job
  alias Lightning.Invocation.Dataclip

  @doc """
  Runs for a specific user
  """
  @spec runs_for(User.t()) :: Ecto.Queryable.t()
  def runs_for(%User{} = user) do
    projects = Ecto.assoc(user, :projects) |> select([:id])

    from(r in Run,
      join: j in assoc(r, :job),
      join: w in assoc(j, :workflow),
      join: p in subquery(projects),
      on: w.project_id == p.id
    )
  end

  @doc """
  The last run for a job
  """
  @spec last_run_for_job(Job.t()) :: Ecto.Queryable.t()
  def last_run_for_job(%Job{id: id}) do
    from(r in Run,
      where: r.job_id == ^id,
      order_by: [desc: r.finished_at],
      limit: 1
    )
  end

  @doc """
  The last run for a job for a particular exit code, used in scheduler
  """
  @spec runs_with_code(Ecto.Queryable.t(), integer()) :: Ecto.Queryable.t()
  def runs_with_code(query, exit_code) do
    from(q in query, where: q.exit_code == ^exit_code)
  end

  @doc """
  The last run for a job for a particular exit code, used in scheduler
  """
  @spec last_successful_run_for_job(Job.t()) :: Ecto.Queryable.t()
  def last_successful_run_for_job(%Job{id: id}) do
    last_run_for_job(%Job{id: id})
    |> runs_with_code(0)
  end

  @doc """
  By default, the dataclip body is not returned via a query. This query selects
  the body specifically.
  """
  def dataclip_with_body() do
    from(d in Dataclip,
      select: [:id, :body, :type, :project_id, :inserted_at, :updated_at]
    )
  end
end
