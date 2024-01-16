defmodule Lightning.Invocation.Query do
  @moduledoc """
  Query functions for working with Runs and Dataclips
  """
  import Ecto.Query

  alias Lightning.Accounts.User
  alias Lightning.Invocation.Dataclip
  alias Lightning.Invocation.Run
  alias Lightning.Workflows.Job

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
  The last run for a job for a particular exit reason, used in scheduler
  """
  @spec runs_with_reason(Ecto.Queryable.t(), String.t()) :: Ecto.Queryable.t()
  def runs_with_reason(query, exit_reason) do
    from(q in query, where: q.exit_reason == ^exit_reason)
  end

  @doc """
  The last successful run for a job, used in scheduler to enable downstream attempts
  to access a previous attempt's state
  """
  @spec last_successful_run_for_job(Job.t()) :: Ecto.Queryable.t()
  def last_successful_run_for_job(%Job{id: id}) do
    last_run_for_job(%Job{id: id})
    |> runs_with_reason("success")
  end

  @doc """
  By default, the dataclip body is not returned via a query. This query selects
  the body specifically.
  """
  def dataclip_with_body, do: from(d in Dataclip, select: %{d | body: d.body})
end
