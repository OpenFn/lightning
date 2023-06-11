defmodule Lightning.Invocation do
  @moduledoc """
  The Invocation context.
  """

  import Ecto.Query, warn: false
  import Lightning.Helpers, only: [coerce_json_field: 2]
  alias Lightning.Invocation.LogLine
  alias Lightning.Workorders.SearchParams
  alias Lightning.Repo

  alias Lightning.Invocation.{Dataclip, Run}
  alias Lightning.Projects.Project

  @doc """
  Returns the list of dataclips.

  ## Examples

      iex> list_dataclips()
      [%Dataclip{}, ...]

  """
  @spec list_dataclips() :: [Dataclip.t()]
  def list_dataclips do
    Repo.all(Dataclip)
  end

  @spec list_dataclips_query(project :: Project.t()) :: Ecto.Queryable.t()
  def list_dataclips_query(%Project{id: project_id}) do
    from(d in Dataclip,
      where: d.project_id == ^project_id,
      order_by: [desc: d.inserted_at]
    )
  end

  @spec list_dataclips(project :: Project.t()) :: [Dataclip.t()]
  def list_dataclips(%Project{id: project_id}) do
    list_dataclips_query(%Project{id: project_id}) |> Repo.all()
  end

  def list_dataclips_for_job(%Lightning.Jobs.Job{id: job_id}) do
    from(r in Run,
      join: d in assoc(r, :input_dataclip),
      where: r.job_id == ^job_id,
      select: d,
      distinct: [desc: d.inserted_at],
      order_by: [desc: d.inserted_at],
      limit: 3
    )
    |> Repo.all()
  end

  @doc """
  Gets a single dataclip.

  Raises `Ecto.NoResultsError` if the Dataclip does not exist.

  ## Examples

      iex> get_dataclip!(123)
      %Dataclip{}

      iex> get_dataclip!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_dataclip!(id :: Ecto.UUID.t()) :: Dataclip.t()
  def get_dataclip!(id), do: Repo.get!(Dataclip, id)

  @doc """
  Gets a single dataclip given one of:

  - a Dataclip uuid
  - a Run model

  Returns `nil` if the Dataclip does not exist.

  ## Examples

      iex> get_dataclip("27b73932-16c7-4a72-86a3-85d805ccff98")
      %Dataclip{}

      iex> get_dataclip("27b73932-16c7-4a72-86a3-85d805ccff98")
      nil

      iex> get_dataclip(%Run{id: "a uuid"})
      %Dataclip{}

  """
  @spec get_dataclip(run_or_uuid :: Run.t() | Ecto.UUID.t()) ::
          Dataclip.t() | nil
  def get_dataclip(%Run{} = run) do
    get_dataclip_query(run) |> Repo.one()
  end

  def get_dataclip(id), do: Repo.get(Dataclip, id)

  @doc """
  Query for retrieving the dataclip that was the result of a successful run.
  """
  def get_result_dataclip_query(%Run{} = run) do
    Ecto.assoc(run, :output_dataclip)
  end

  @doc """
  Query for retrieving the dataclip that a runs starting dataclip.
  """
  def get_dataclip_query(%Run{} = run) do
    Ecto.assoc(run, :input_dataclip)
  end

  @doc """
  Creates a dataclip.

  ## Examples

      iex> create_dataclip(%{field: value})
      {:ok, %Dataclip{}}

      iex> create_dataclip(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_dataclip(attrs :: map()) ::
          {:ok, Dataclip.t()} | {:error, Ecto.Changeset.t(Dataclip)}
  def create_dataclip(attrs \\ %{}) do
    %Dataclip{}
    |> Dataclip.changeset(attrs |> coerce_json_field("body"))
    |> Repo.insert()
  end

  @doc """
  Updates a dataclip.

  ## Examples

      iex> update_dataclip(dataclip, %{field: new_value})
      {:ok, %Dataclip{}}

      iex> update_dataclip(dataclip, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_dataclip(%Dataclip{} = dataclip, attrs) do
    dataclip
    |> Dataclip.changeset(attrs |> coerce_json_field("body"))
    |> Repo.update()
  end

  @doc """
  Deletes a dataclip.

  ## Examples

      iex> delete_dataclip(dataclip)
      {:ok, %Dataclip{}}

      iex> delete_dataclip(dataclip)
      {:error, %Ecto.Changeset{}}

  """
  def delete_dataclip(%Dataclip{} = dataclip) do
    dataclip
    |> Dataclip.changeset(%{})
    |> Map.put(:action, :delete)
    |> Dataclip.changeset(%{body: nil})
    |> Repo.update()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking dataclip changes.

  ## Examples

      iex> change_dataclip(dataclip)
      %Ecto.Changeset{data: %Dataclip{}}

  """
  def change_dataclip(%Dataclip{} = dataclip, attrs \\ %{}) do
    Dataclip.changeset(dataclip, attrs |> coerce_json_field("body"))
  end

  @doc """
  Returns the list of runs.

  ## Examples

      iex> list_runs()
      [%Run{}, ...]

  """
  def list_runs do
    Repo.all(Run)
  end

  @spec list_runs_for_project_query(Lightning.Projects.Project.t()) ::
          Ecto.Query.t()
  def list_runs_for_project_query(%Project{id: project_id}) do
    from(r in Run,
      join: j in assoc(r, :job),
      join: w in assoc(j, :workflow),
      where: w.project_id == ^project_id,
      order_by: [desc: r.inserted_at, desc: r.started_at],
      preload: [job: j]
    )
  end

  @spec list_runs_for_project(Lightning.Projects.Project.t(), keyword | map) ::
          Scrivener.Page.t()
  def list_runs_for_project(%Project{} = project, params \\ %{}) do
    list_runs_for_project_query(project)
    |> Repo.paginate(params)
  end

  @doc """
  Gets a single run.

  Raises `Ecto.NoResultsError` if the Run does not exist.

  ## Examples

      iex> get_run!(123)
      %Run{}

      iex> get_run!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_run!(Ecto.UUID.t()) :: Run.t()
  def get_run!(id), do: Repo.get!(Run, id)

  @doc """
  Fetches a run and preloads the job via the run's event.
  """
  def get_run_with_job!(id),
    do: from(r in Run, where: r.id == ^id, preload: :job) |> Repo.one!()

  @doc """
  Creates a run.

  ## Examples

      iex> create_run(%{field: value})
      {:ok, %Run{}}

      iex> create_run(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_run(attrs \\ %{}) do
    %Run{}
    |> Run.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a run.

  ## Examples

      iex> update_run(run, %{field: new_value})
      {:ok, %Run{}}

      iex> update_run(run, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_run(%Run{} = run, attrs) do
    run
    |> Run.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, run} = res ->
        LightningWeb.Endpoint.broadcast!(
          "run:#{run.id}",
          "update",
          %{}
        )

        Lightning.WorkOrderService.attempt_updated(run)

        res

      res ->
        res
    end
  end

  def create_log_line(run, body) do
    %LogLine{}
    |> Ecto.Changeset.change(%{run: run, body: body |> to_string})
    |> LogLine.validate()
    |> Repo.insert!()
  end

  @doc """
  Deletes a run.

  ## Examples

      iex> delete_run(run)
      {:ok, %Run{}}

      iex> delete_run(run)
      {:error, %Ecto.Changeset{}}

  """
  def delete_run(%Run{} = run) do
    Repo.delete(run)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking run changes.

  ## Examples

      iex> change_run(run)
      %Ecto.Changeset{data: %Run{}}

  """
  def change_run(%Run{} = run, attrs \\ %{}) do
    Run.changeset(run, attrs)
  end

  def filter_workflow_where(workflow_id) do
    case workflow_id do
      d when d in ["", nil] -> dynamic(true)
      _ -> dynamic([workflow: w], w.id == ^workflow_id)
    end
  end

  def filter_workorder_insert_after_where(date_after) do
    case date_after do
      d when d in ["", nil] -> dynamic(true)
      _ -> dynamic([wo], wo.inserted_at >= ^date_after)
    end
  end

  def filter_workorder_insert_before_where(date_before) do
    case date_before do
      d when d in ["", nil] -> dynamic(true)
      _ -> dynamic([wo], wo.inserted_at < ^date_before)
    end
  end

  def filter_run_finished_after_where(date_after) do
    case date_after do
      d when d in ["", nil] -> dynamic(true)
      _ -> dynamic([runs: r], r.finished_at >= ^date_after)
    end
  end

  def filter_run_finished_before_where(date_before) do
    case date_before do
      d when d in ["", nil] -> dynamic(true)
      _ -> dynamic([runs: r], r.finished_at < ^date_before)
    end
  end

  def filter_run_status_where(statuses) do
    Enum.reduce(statuses, dynamic(false), fn
      :pending, query ->
        dynamic([runs: r], ^query or is_nil(r.exit_code))

      :success, query ->
        dynamic([runs: r], ^query or r.exit_code == 0)

      :failure, query ->
        dynamic([runs: r], ^query or r.exit_code == 1)

      :timeout, query ->
        dynamic([runs: r], ^query or r.exit_code == 2)

      :crash, query ->
        dynamic([runs: r], ^query or r.exit_code > 2)

      _, query ->
        # Not a where parameter
        query
    end)
  end

  def filter_run_body_and_logs_where(_search_term, search_fields)
      when search_fields == [] do
    dynamic(true)
  end

  def filter_run_body_and_logs_where(search_term, search_fields)
      when search_fields != [] do
    Enum.reduce(search_fields, dynamic(false), fn
      :log, query ->
        dynamic(
          [log_lines: l],
          ^query or
            fragment(
              "cast(?  as VARCHAR) ilike ?",
              l.body,
              ^"%#{search_term}%"
            )
        )

      :body, query ->
        dynamic(
          [input: i],
          ^query or
            fragment("cast(?  as VARCHAR) ilike ?", i.body, ^"%#{search_term}%")
        )

      _, query ->
        query
    end)
  end

  def list_work_orders_for_project_query(
        %Project{id: project_id},
        %SearchParams{} = search_params
      ) do
    last_attempts =
      from(att in Lightning.Attempt,
        group_by: att.work_order_id,
        select: %{
          work_order_id: att.work_order_id,
          last_inserted_at: max(att.inserted_at)
        }
      )

    last_runs =
      from(r in Lightning.Invocation.Run,
        join: att in assoc(r, :attempts),
        distinct: att.id,
        order_by: [desc_nulls_first: r.finished_at],
        select: %{
          attempt_id: att.id,
          last_finished_at: r.finished_at
        }
      )

    # TODO: Refactor to remove the fragment used here; it causes timezone issues
    from(wo in Lightning.WorkOrder,
      join: wo_re in assoc(wo, :reason),
      join: w in assoc(wo, :workflow),
      as: :workflow,
      join: att in assoc(wo, :attempts),
      join: last in subquery(last_attempts),
      on:
        last.last_inserted_at == att.inserted_at and wo.id == last.work_order_id,
      join: r in assoc(att, :runs),
      as: :runs,
      join: last_run in subquery(last_runs),
      on:
        (att.id == last_run.attempt_id and
           last_run.last_finished_at == r.finished_at) or is_nil(r.finished_at),
      join: att_re in assoc(att, :reason),
      join: d in assoc(r, :input_dataclip),
      as: :input,
      left_join: l in LogLine,
      on: l.run_id == r.id,
      as: :log_lines,
      where: w.project_id == ^project_id,
      where: ^filter_run_status_where(search_params.status),
      where: ^filter_workflow_where(search_params.workflow_id),
      where: ^filter_workorder_insert_after_where(search_params.wo_date_after),
      where: ^filter_workorder_insert_before_where(search_params.wo_date_before),
      where: ^filter_run_finished_after_where(search_params.date_after),
      where: ^filter_run_finished_before_where(search_params.date_before),
      where:
        ^filter_run_body_and_logs_where(
          search_params.search_term,
          search_params.search_fields
        ),
      select: %{
        id: wo.id,
        last_finished_at:
          fragment(
            "nullif(max(coalesce(?, 'infinity')), 'infinity')",
            r.finished_at
          )
          |> selected_as(:last_finished_at)
      },
      group_by: wo.id,
      order_by: [desc_nulls_first: selected_as(:last_finished_at)]
    )
  end

  def get_workorders_by_ids(ids) do
    from(wo in Lightning.WorkOrder, where: wo.id in ^ids)
  end

  def with_attempts(query) do
    runs_query =
      from(r in Lightning.Invocation.Run,
        as: :runs,
        join: j in assoc(r, :job),
        join: d in assoc(r, :input_dataclip),
        as: :input,
        order_by: [asc: r.finished_at],
        preload: [
          job:
            ^from(job in Lightning.Jobs.Job,
              select: %{id: job.id, name: job.name}
            )
        ]
      )

    attempts_query =
      from(a in Lightning.Attempt,
        join: re in assoc(a, :reason),
        join: r in assoc(a, :runs),
        order_by: [desc: a.inserted_at],
        preload: [reason: re, runs: ^runs_query]
      )

    dataclips_query =
      from(d in Lightning.Invocation.Dataclip,
        select: %{id: d.id, type: d.type}
      )

    # we can use a ^custom_query to control (order_by ...) the way preloading is done
    from(wo in query,
      preload: [
        reason:
          ^from(r in Lightning.InvocationReason,
            preload: [dataclip: ^dataclips_query]
          ),
        workflow:
          ^from(wf in Lightning.Workflows.Workflow,
            select: %{id: wf.id, name: wf.name, project_id: wf.project_id}
          ),
        attempts: ^attempts_query
      ]
    )
  end

  def search_workorders(%Project{} = project) do
    search_params = SearchParams.new(%{})
    search_workorders(project, search_params, %{})
  end

  def search_workorders(%Project{} = project, filter, params \\ %{}) do
    # TODO: The "get_and_update" below is only necessary because of the fragment
    # on line 461 of this file. See other "TODO".
    list_work_orders_for_project_query(project, filter)
    |> Repo.paginate(params)
    |> Map.get_and_update!(
      :entries,
      fn current_value ->
        {current_value,
         Enum.map(current_value, fn e ->
           %{
             id: e.id,
             last_finished_at:
               if is_nil(e.last_finished_at) do
                 nil
               else
                 DateTime.from_naive!(e.last_finished_at, "Etc/UTC")
               end
           }
         end)}
      end
    )
    |> elem(1)
  end
end
