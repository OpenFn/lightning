defmodule Lightning.Invocation.Query do
  @moduledoc """
  Query functions for working with Steps and Dataclips
  """
  import Ecto.Query

  alias Lightning.Accounts.User
  alias Lightning.Invocation.Dataclip
  alias Lightning.Invocation.Step
  alias Lightning.Projects.Project
  alias Lightning.Run
  alias Lightning.Workflows.Job
  alias Lightning.WorkOrder

  @doc """
  Work orders for a specific project, or all runs available to the requesting user
  """
  @spec work_orders_for(User.t()) :: Ecto.Queryable.t()
  def work_orders_for(%User{} = user) do
    projects = Ecto.assoc(user, :projects) |> select([:id])

    from(wo in WorkOrder,
      as: :work_order,
      join: w in assoc(wo, :workflow),
      as: :workflow,
      join: p in subquery(projects),
      on: w.project_id == p.id,
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
  Runs for a specific project, or all runs available to the requesting user
  """
  @spec runs_for(User.t()) :: Ecto.Queryable.t()
  def runs_for(%User{} = user) do
    projects = Ecto.assoc(user, :projects) |> select([:id])

    from(r in Run,
      as: :run,
      join: wo in assoc(r, :work_order),
      as: :work_order,
      join: w in assoc(wo, :workflow),
      as: :workflow,
      join: p in subquery(projects),
      on: w.project_id == p.id,
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

  @doc """
  Validate datetime parameters for filtering
  """
  @spec validate_datetime_params(map(), list(String.t())) ::
          :ok | {:error, String.t()}
  def validate_datetime_params(params, keys) do
    keys
    |> Enum.find_value(fn key ->
      case params[key] do
        nil ->
          nil

        value ->
          case parse_datetime(value) do
            {:ok, _} ->
              nil

            :error ->
              {:error, "Invalid datetime format for '#{key}': #{inspect(value)}"}
          end
      end
    end)
    |> case do
      nil -> :ok
      error -> error
    end
  end

  @doc """
  Filter runs by inserted_at date range
  """
  @spec filter_runs_by_date(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  def filter_runs_by_date(query, params) do
    query
    |> filter_by_inserted_after(params["inserted_after"])
    |> filter_by_inserted_before(params["inserted_before"])
    |> filter_by_updated_after(params["updated_after"])
    |> filter_by_updated_before(params["updated_before"])
  end

  @doc """
  Filter runs by various criteria
  """
  @spec filter_runs(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  def filter_runs(query, params) do
    query
    |> filter_runs_by_date(params)
    |> filter_runs_by_project(params["project_id"])
    |> filter_runs_by_workflow(params["workflow_id"])
    |> filter_runs_by_work_order(params["work_order_id"])
  end

  defp filter_runs_by_project(query, nil), do: query

  defp filter_runs_by_project(query, project_id) do
    from([workflow: w] in query, where: w.project_id == ^project_id)
  end

  defp filter_runs_by_workflow(query, nil), do: query

  defp filter_runs_by_workflow(query, workflow_id) do
    from([workflow: w] in query, where: w.id == ^workflow_id)
  end

  defp filter_runs_by_work_order(query, nil), do: query

  defp filter_runs_by_work_order(query, work_order_id) do
    from([work_order: wo] in query, where: wo.id == ^work_order_id)
  end

  defp filter_by_inserted_after(query, nil), do: query

  defp filter_by_inserted_after(query, date_string) do
    {:ok, datetime} = parse_datetime(date_string)
    from(r in query, where: r.inserted_at >= ^datetime)
  end

  defp filter_by_inserted_before(query, nil), do: query

  defp filter_by_inserted_before(query, date_string) do
    {:ok, datetime} = parse_datetime(date_string)
    from(r in query, where: r.inserted_at <= ^datetime)
  end

  defp filter_by_updated_after(query, nil), do: query

  defp filter_by_updated_after(query, date_string) do
    {:ok, datetime} = parse_datetime(date_string)
    from(r in query, where: r.updated_at >= ^datetime)
  end

  defp filter_by_updated_before(query, nil), do: query

  defp filter_by_updated_before(query, date_string) do
    {:ok, datetime} = parse_datetime(date_string)
    from(r in query, where: r.updated_at <= ^datetime)
  end

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
      where: d.type in [:http_request, :step_result, :saved_input],
      where: is_nil(d.name),
      update: [
        set: [request: nil, body: nil, wiped_at: ^Lightning.current_time()]
      ]
    )
  end

  @doc """
  Filter work orders by date range
  """
  @spec filter_work_orders_by_date(Ecto.Queryable.t(), map()) ::
          Ecto.Queryable.t()
  def filter_work_orders_by_date(query, params) do
    query
    |> filter_wo_by_inserted_after(params["inserted_after"])
    |> filter_wo_by_inserted_before(params["inserted_before"])
    |> filter_wo_by_updated_after(params["updated_after"])
    |> filter_wo_by_updated_before(params["updated_before"])
  end

  @doc """
  Filter work orders by various criteria
  """
  @spec filter_work_orders(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  def filter_work_orders(query, params) do
    query
    |> filter_work_orders_by_date(params)
    |> filter_work_orders_by_project(params["project_id"])
    |> filter_work_orders_by_workflow(params["workflow_id"])
  end

  defp filter_work_orders_by_project(query, nil), do: query

  defp filter_work_orders_by_project(query, project_id) do
    from([workflow: w] in query, where: w.project_id == ^project_id)
  end

  defp filter_work_orders_by_workflow(query, nil), do: query

  defp filter_work_orders_by_workflow(query, workflow_id) do
    from([workflow: w] in query, where: w.id == ^workflow_id)
  end

  defp filter_wo_by_inserted_after(query, nil), do: query

  defp filter_wo_by_inserted_after(query, date_string) do
    {:ok, datetime} = parse_datetime(date_string)
    from(wo in query, where: wo.inserted_at >= ^datetime)
  end

  defp filter_wo_by_inserted_before(query, nil), do: query

  defp filter_wo_by_inserted_before(query, date_string) do
    {:ok, datetime} = parse_datetime(date_string)
    from(wo in query, where: wo.inserted_at <= ^datetime)
  end

  defp filter_wo_by_updated_after(query, nil), do: query

  defp filter_wo_by_updated_after(query, date_string) do
    {:ok, datetime} = parse_datetime(date_string)
    from(wo in query, where: wo.updated_at >= ^datetime)
  end

  defp filter_wo_by_updated_before(query, nil), do: query

  defp filter_wo_by_updated_before(query, date_string) do
    {:ok, datetime} = parse_datetime(date_string)
    from(wo in query, where: wo.updated_at <= ^datetime)
  end

  defp parse_datetime(nil), do: :error

  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _} -> :error
    end
  end

  defp parse_datetime(_), do: :error

  @doc """
  Log lines for a specific user, filtered by their accessible projects
  """
  @spec log_lines_for(User.t()) :: Ecto.Queryable.t()
  def log_lines_for(%User{} = user) do
    projects = Ecto.assoc(user, :projects) |> select([:id])

    from(log in Lightning.Invocation.LogLine,
      as: :log,
      join: r in assoc(log, :run),
      as: :run,
      join: wo in assoc(r, :work_order),
      as: :work_order,
      join: w in assoc(wo, :workflow),
      as: :workflow,
      join: p in subquery(projects),
      on: w.project_id == p.id,
      order_by: [desc: log.timestamp]
    )
  end

  @doc """
  Filter log lines by various criteria
  """
  @spec filter_log_lines(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  def filter_log_lines(query, params) do
    query
    |> filter_log_by_timestamp_after(params["timestamp_after"])
    |> filter_log_by_timestamp_before(params["timestamp_before"])
    |> filter_log_by_project(params["project_id"])
    |> filter_log_by_workflow(params["workflow_id"])
    |> filter_log_by_job(params["job_id"])
    |> filter_log_by_work_order(params["work_order_id"])
    |> filter_log_by_run(params["run_id"])
    |> filter_log_by_level(params["level"])
  end

  defp filter_log_by_timestamp_after(query, nil), do: query

  defp filter_log_by_timestamp_after(query, date_string) do
    {:ok, datetime} = parse_datetime(date_string)
    from([log: log] in query, where: log.timestamp >= ^datetime)
  end

  defp filter_log_by_timestamp_before(query, nil), do: query

  defp filter_log_by_timestamp_before(query, date_string) do
    {:ok, datetime} = parse_datetime(date_string)
    from([log: log] in query, where: log.timestamp <= ^datetime)
  end

  defp filter_log_by_project(query, nil), do: query

  defp filter_log_by_project(query, project_id) do
    from([workflow: w] in query, where: w.project_id == ^project_id)
  end

  defp filter_log_by_workflow(query, nil), do: query

  defp filter_log_by_workflow(query, workflow_id) do
    from([work_order: wo] in query, where: wo.workflow_id == ^workflow_id)
  end

  defp filter_log_by_job(query, nil), do: query

  defp filter_log_by_job(query, job_id) do
    from([log: log] in query,
      join: s in assoc(log, :step),
      where: s.job_id == ^job_id
    )
  end

  defp filter_log_by_work_order(query, nil), do: query

  defp filter_log_by_work_order(query, work_order_id) do
    from([run: r] in query, where: r.work_order_id == ^work_order_id)
  end

  defp filter_log_by_run(query, nil), do: query

  defp filter_log_by_run(query, run_id) do
    from([log: log] in query, where: log.run_id == ^run_id)
  end

  defp filter_log_by_level(query, nil), do: query

  defp filter_log_by_level(query, level) when is_binary(level) do
    level_atom = String.to_existing_atom(level)

    if level_atom in [:success, :always, :info, :warn, :error, :debug] do
      from([log: log] in query, where: log.level == ^level_atom)
    else
      query
    end
  rescue
    ArgumentError -> query
  end

  defp filter_log_by_level(query, _), do: query
end
