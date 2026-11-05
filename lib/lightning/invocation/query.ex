defmodule Lightning.Invocation.Query do
  @moduledoc """
  Query functions for working with Steps and Dataclips
  """
  import Ecto.Query

  alias Lightning.Accounts.User
  alias Lightning.Invocation.Dataclip
  alias Lightning.Invocation.LogLine
  alias Lightning.Invocation.Step
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Run
  alias Lightning.Scope
  alias Lightning.Workflows.Job
  alias Lightning.WorkOrder

  @doc """
  Work orders of a given project, or of every project the caller may list
  (`Lightning.Projects.visible_project_ids/1`).
  """
  @spec work_orders_for(Scope.t()) :: Ecto.Queryable.t()
  def work_orders_for(%Scope{} = scope) do
    from(wo in WorkOrder,
      as: :work_order,
      join: w in assoc(wo, :workflow),
      as: :workflow,
      where: w.project_id in subquery(Projects.visible_project_ids(scope)),
      order_by: [desc: wo.last_activity]
    )
  end

  @spec work_orders_for(Project.t()) :: Ecto.Queryable.t()
  def work_orders_for(%Project{id: project_id}) do
    from(wo in WorkOrder,
      as: :work_order,
      join: w in assoc(wo, :workflow),
      as: :workflow,
      where: w.project_id == ^project_id,
      order_by: [desc: wo.last_activity]
    )
  end

  @doc """
  Appends `exit_reason != "success"` to a query of `Step`.

  A step that never finished carries a `nil` `exit_reason`, and `NULL !=
  'success'` is false in SQL, so it is excluded here too: a step still in
  flight is not yet a failure.
  """
  @spec where_step_failed(Ecto.Queryable.t()) :: Ecto.Queryable.t()
  def where_step_failed(query) do
    from(s in query, where: s.exit_reason != "success")
  end

  # Shared so the health page's bulk `DISTINCT ON` and the history filter's
  # correlated per-work-order lookup can't drift apart on what "latest" means.
  @spec order_by_run_recency(Ecto.Queryable.t()) :: Ecto.Queryable.t()
  def order_by_run_recency(query) do
    from([run: r] in query,
      order_by: [desc_nulls_last: r.finished_at, desc: r.id]
    )
  end

  @doc """
  Runs of a given project, or of every project the caller may list
  (`Lightning.Projects.visible_project_ids/1`).
  """
  @spec runs_for(Scope.t()) :: Ecto.Queryable.t()
  def runs_for(%Scope{} = scope) do
    from(r in Run,
      as: :run,
      join: wo in assoc(r, :work_order),
      as: :work_order,
      join: w in assoc(wo, :workflow),
      as: :workflow,
      where: w.project_id in subquery(Projects.visible_project_ids(scope)),
      order_by: [desc: r.inserted_at]
    )
  end

  @spec runs_for(Project.t()) :: Ecto.Queryable.t()
  def runs_for(%Project{id: project_id}) do
    from(r in Run,
      as: :run,
      join: wo in assoc(r, :work_order),
      as: :work_order,
      join: w in assoc(wo, :workflow),
      as: :workflow,
      where: w.project_id == ^project_id,
      order_by: [desc: r.inserted_at]
    )
  end

  @run_filters %{
    inserted_after: :utc_datetime_usec,
    inserted_before: :utc_datetime_usec,
    updated_after: :utc_datetime_usec,
    updated_before: :utc_datetime_usec,
    project_id: Ecto.UUID,
    workflow_id: Ecto.UUID,
    work_order_id: Ecto.UUID,
    state: {:array, :string}
  }

  @doc """
  The filters `filter_runs/2` takes, each with its type.
  """
  @spec run_filter_types() :: %{atom() => Ecto.Type.t()}
  def run_filter_types, do: @run_filters

  @doc """
  Narrows a query of runs by `filters`, keyed and typed as
  `run_filter_types/0` says.
  """
  @spec filter_runs(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  def filter_runs(query, filters),
    do: Enum.reduce(filters, query, &where_run/2)

  defp where_run({:project_id, id}, query),
    do: from([workflow: w] in query, where: w.project_id == ^id)

  defp where_run({:workflow_id, id}, query),
    do: from([workflow: w] in query, where: w.id == ^id)

  defp where_run({:work_order_id, id}, query),
    do: from([work_order: wo] in query, where: wo.id == ^id)

  defp where_run({:state, states}, query),
    do: from(r in query, where: r.state in ^states)

  defp where_run(timestamp_filter, query),
    do: where_timestamps(timestamp_filter, query)

  defp where_timestamps({:inserted_after, at}, query),
    do: from(q in query, where: q.inserted_at >= ^at)

  defp where_timestamps({:inserted_before, at}, query),
    do: from(q in query, where: q.inserted_at <= ^at)

  defp where_timestamps({:updated_after, at}, query),
    do: from(q in query, where: q.updated_at >= ^at)

  defp where_timestamps({:updated_before, at}, query),
    do: from(q in query, where: q.updated_at <= ^at)

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
  Dataclips a job can be run against: the ones it has consumed, plus every
  named dataclip in its project.

  A named dataclip is a curated input rather than a trace of a past run, so the
  result is no longer bounded by the job. The two sources are unioned rather
  than ORed so each keeps its own index, instead of making dataclips the
  driving relation on every keystroke of the picker's search.
  """
  def selectable_for_job(job_id, project_id, limit) do
    consumed = job_input_dataclip_ids(job_id)

    selectable =
      if project_id do
        union(consumed, ^named_dataclip_ids(project_id))
      else
        consumed
      end

    from(d in Dataclip,
      where: d.id in subquery(selectable),
      order_by: [
        desc: d.id in subquery(consumed),
        desc: d.inserted_at
      ],
      limit: ^limit
    )
  end

  defp job_input_dataclip_ids(job_id) do
    from(s in Step,
      where: s.job_id == ^job_id and not is_nil(s.input_dataclip_id),
      select: s.input_dataclip_id
    )
  end

  defp named_dataclip_ids(project_id) do
    from(d in Dataclip,
      where: d.project_id == ^project_id and not is_nil(d.name),
      select: d.id
    )
  end

  @doc """
  By default, the dataclip body is not returned via a query. This query selects
  the body specifically.
  """
  def dataclip_with_body, do: from(d in Dataclip) |> select_as_input_text()

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

  Like `select_as_input/1`, but returns body as JSON text string to avoid
  expensive deserialization to Elixir map (saves ~38x memory amplification).
  """
  def select_as_input_text(query) do
    from(d in query,
      select: %{
        d
        | body:
            fragment(
              """
              CASE WHEN type IN ('http_request', 'kafka')
              THEN jsonb_build_object('data', ?, 'request', ?)::text
              ELSE ?::text END
              """,
              d.body,
              d.request,
              d.body
            )
      }
    )
  end

  def wipe_dataclips(query \\ Dataclip) do
    from(d in query,
      where: d.type in [:http_request, :step_result, :saved_input, :kafka],
      where: is_nil(d.name),
      where: is_nil(d.wiped_at),
      update: [
        set: [request: nil, body: nil, wiped_at: ^Lightning.current_time()]
      ]
    )
  end

  @work_order_filters %{
    id: {:array, Ecto.UUID},
    inserted_after: :utc_datetime_usec,
    inserted_before: :utc_datetime_usec,
    updated_after: :utc_datetime_usec,
    updated_before: :utc_datetime_usec,
    project_id: Ecto.UUID,
    workflow_id: Ecto.UUID,
    state: {:array, :string}
  }

  @doc """
  The filters `filter_work_orders/2` takes, each with its type.
  """
  @spec work_order_filter_types() :: %{atom() => Ecto.Type.t()}
  def work_order_filter_types, do: @work_order_filters

  @doc """
  Narrows a query of work orders by `filters`, keyed and typed as
  `work_order_filter_types/0` says.
  """
  @spec filter_work_orders(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  def filter_work_orders(query, filters),
    do: Enum.reduce(filters, query, &where_work_order/2)

  defp where_work_order({:id, ids}, query),
    do: from(wo in query, where: wo.id in ^ids)

  defp where_work_order({:project_id, id}, query),
    do: from([workflow: w] in query, where: w.project_id == ^id)

  defp where_work_order({:workflow_id, id}, query),
    do: from([workflow: w] in query, where: w.id == ^id)

  defp where_work_order({:state, states}, query),
    do: from(wo in query, where: wo.state in ^states)

  defp where_work_order(timestamp_filter, query),
    do: where_timestamps(timestamp_filter, query)

  @doc """
  Log lines of every project the caller may list
  (`Lightning.Projects.visible_project_ids/1`).
  """
  @spec log_lines_for(Scope.t()) :: Ecto.Queryable.t()
  def log_lines_for(%Scope{} = scope) do
    from(log in LogLine,
      as: :log,
      join: r in assoc(log, :run),
      as: :run,
      join: wo in assoc(r, :work_order),
      as: :work_order,
      join: w in assoc(wo, :workflow),
      as: :workflow,
      where: w.project_id in subquery(Projects.visible_project_ids(scope)),
      order_by: [desc: log.timestamp]
    )
  end

  @spec log_lines_for(Project.t()) :: Ecto.Queryable.t()
  def log_lines_for(%Project{id: project_id}) do
    from(log in LogLine,
      as: :log,
      join: r in assoc(log, :run),
      as: :run,
      join: wo in assoc(r, :work_order),
      as: :work_order,
      join: w in assoc(wo, :workflow),
      as: :workflow,
      where: w.project_id == ^project_id,
      order_by: [desc: log.timestamp]
    )
  end

  @log_line_filters %{
    timestamp_after: :utc_datetime_usec,
    timestamp_before: :utc_datetime_usec,
    workflow_id: Ecto.UUID,
    job_id: Ecto.UUID,
    work_order_id: Ecto.UUID,
    run_id: Ecto.UUID,
    level: :string
  }

  @doc """
  The filters `filter_log_lines/2` takes, each with its type.
  """
  @spec log_line_filter_types() :: %{atom() => Ecto.Type.t()}
  def log_line_filter_types, do: @log_line_filters

  @doc """
  Narrows a query of log lines by `filters`, keyed and typed as
  `log_line_filter_types/0` says.
  """
  @spec filter_log_lines(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  def filter_log_lines(query, filters),
    do: Enum.reduce(filters, query, &where_log_line/2)

  defp where_log_line({:timestamp_after, at}, query),
    do: from([log: log] in query, where: log.timestamp >= ^at)

  defp where_log_line({:timestamp_before, at}, query),
    do: from([log: log] in query, where: log.timestamp <= ^at)

  defp where_log_line({:workflow_id, id}, query),
    do: from([work_order: wo] in query, where: wo.workflow_id == ^id)

  defp where_log_line({:job_id, id}, query) do
    from([log: log] in query,
      join: s in assoc(log, :step),
      where: s.job_id == ^id
    )
  end

  defp where_log_line({:work_order_id, id}, query),
    do: from([run: r] in query, where: r.work_order_id == ^id)

  defp where_log_line({:run_id, id}, query),
    do: from([log: log] in query, where: log.run_id == ^id)

  defp where_log_line({:level, level}, query),
    do: from([log: log] in query, where: log.level == ^level)
end
