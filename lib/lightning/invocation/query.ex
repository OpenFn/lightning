defmodule Lightning.Invocation.Query do
  @moduledoc """
  Query functions for working with Events, Runs and Dataclips
  """
  import Ecto.Query

  alias Lightning.Accounts.User
  alias Lightning.Invocation.Run
  alias Lightning.Jobs.Job

  @doc """
  Runs for a specific user
  """
  @spec runs_for(User.t()) :: Ecto.Queryable.t()
  def runs_for(%User{} = user) do
    projects = Ecto.assoc(user, :projects) |> select([:id])

    from(r in Run,
      join: e in assoc(r, :event),
      join: p in subquery(projects),
      on: e.project_id == p.id
    )
  end

  @doc """
  The last run for a job, used in scheduler
  """
  @spec last_run_for_job(Job.t()) :: Ecto.Queryable.t()
  def last_run_for_job(%Job{id: id}) do
    from(r in Run,
      join: e in assoc(r, :event),
      where: e.job_id == ^id,
      order_by: [desc: r.inserted_at],
      limit: 1
    )
  end
end
