defmodule Lightning.Invocation.Query do
  @moduledoc """
  Query functions for working with Steps and Dataclips
  """
  import Ecto.Query

  alias Lightning.Accounts.User
  alias Lightning.Invocation.Dataclip
  alias Lightning.Invocation.Step
  alias Lightning.Workflows.Job

  @doc """
  Steps for a specific user
  """
  @spec steps_for(User.t()) :: Ecto.Queryable.t()
  def steps_for(%User{} = user) do
    projects = Ecto.assoc(user, :projects) |> select([:id])

    from(s in Step,
      join: j in assoc(s, :job),
      join: w in assoc(j, :workflow),
      join: p in subquery(projects),
      on: w.project_id == p.id
    )
  end

  @doc """
  The last step for a job
  """
  @spec last_step_for_job(Job.t()) :: Ecto.Queryable.t()
  def last_step_for_job(%Job{id: id}) do
    from(s in Step,
      where: s.job_id == ^id,
      order_by: [desc: s.finished_at],
      limit: 1
    )
  end

  @doc """
  To be used in preloads for `workflow > job > step` when the presence of any
  step is all the information we need. As in, "Does this job have any steps?"
  """
  def any_step do
    by_job =
      from s in Step,
        select: %{id: s.id, row_number: over(row_number(), :jobs_partition)},
        windows: [jobs_partition: [partition_by: :job_id]]

    from s in Step,
      join: r in subquery(by_job),
      on: s.id == r.id and r.row_number == 1
  end

  @doc """
  The last step for a job for a particular exit reason, used in scheduler
  """
  @spec steps_with_reason(Ecto.Queryable.t(), String.t()) :: Ecto.Queryable.t()
  def steps_with_reason(query, exit_reason) do
    from(q in query, where: q.exit_reason == ^exit_reason)
  end

  @doc """
  The last successful step for a job, used in scheduler to enable downstream runs
  to access a previous run's state
  """
  @spec last_successful_step_for_job(Job.t()) :: Ecto.Queryable.t()
  def last_successful_step_for_job(%Job{id: id}) do
    last_step_for_job(%Job{id: id})
    |> steps_with_reason("success")
  end

  @doc """
  By default, the dataclip body is not returned via a query. This query selects
  the body specifically.
  """
  def dataclip_with_body, do: from(d in Dataclip) |> select_as_input()

  def last_n_for_job(job_id, limit) do
    from(d in Dataclip,
      join: s in Step,
      on: s.input_dataclip_id == d.id,
      where: s.job_id == ^job_id,
      distinct: [desc: d.inserted_at],
      order_by: [desc: d.inserted_at],
      limit: ^limit
    )
  end

  @doc """
  Returns a dataclip formatted for use as an input state.

  Only `http_request` dataclips are changed, their `body` is nested inside a
  `"data"` key and `request` data is added as a `"request"` key.
  """
  def select_as_input(query) do
    from(d in query,
      select: %{
        d
        | body:
            fragment(
              """
              CASE WHEN type = 'http_request'
              THEN jsonb_build_object('data', ?, 'request', ?)
              ELSE ? END
              """,
              d.body,
              d.request,
              d.body
            )
      }
    )
  end
end
