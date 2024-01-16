defmodule Lightning.Invocation do
  @moduledoc """
  The Invocation context.
  """

  import Ecto.Query, warn: false
  import Lightning.Helpers, only: [coerce_json_field: 2]

  alias Lightning.Invocation.Dataclip
  alias Lightning.Invocation.Query
  alias Lightning.Invocation.Run
  alias Lightning.Projects.Project
  alias Lightning.Repo
  alias Lightning.WorkOrder
  alias Lightning.WorkOrders.SearchParams

  @workorders_search_timeout 30_000
  @workorders_count_limit 50

  def get_workorders_count_limit, do: @workorders_count_limit

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

  def list_dataclips_for_job(%Lightning.Workflows.Job{id: job_id}) do
    from(r in Run,
      join: d in assoc(r, :input_dataclip),
      where: r.job_id == ^job_id,
      select: %Dataclip{
        id: d.id,
        body: d.body,
        type: d.type,
        project_id: d.project_id,
        inserted_at: d.inserted_at,
        updated_at: d.updated_at
      },
      distinct: [desc: d.inserted_at],
      order_by: [desc: d.inserted_at],
      limit: 3
    )
    |> Repo.all()
  end

  @spec get_dataclip_details!(id :: Ecto.UUID.t()) :: Dataclip.t()
  def get_dataclip_details!(id),
    do: Repo.get!(Query.dataclip_with_body(), id)

  @spec get_dataclip_for_attempt(attempt_id :: Ecto.UUID.t()) ::
          Dataclip.t() | nil
  def get_dataclip_for_attempt(attempt_id) do
    query =
      from d in Query.dataclip_with_body(),
        join: a in Lightning.Attempt,
        on: a.dataclip_id == d.id and a.id == ^attempt_id

    Repo.one(query)
  end

  @spec get_dataclip_for_attempt_and_job(
          attempt_id :: Ecto.UUID.t(),
          job_id :: Ecto.UUID.t()
        ) ::
          Dataclip.t() | nil
  def get_dataclip_for_attempt_and_job(attempt_id, job_id) do
    query =
      from d in Query.dataclip_with_body(),
        join: r in Lightning.Invocation.Run,
        on: r.input_dataclip_id == d.id and r.job_id == ^job_id,
        join: a in assoc(r, :attempts),
        on: a.id == ^attempt_id

    Repo.one(query)
  end

  @spec get_run_for_attempt_and_job(
          attempt_id :: Ecto.UUID.t(),
          job_id :: Ecto.UUID.t()
        ) ::
          Lightning.Invocation.Run.t() | nil
  def get_run_for_attempt_and_job(attempt_id, job_id) do
    query =
      from r in Lightning.Invocation.Run,
        join: a in assoc(r, :attempts),
        on: a.id == ^attempt_id,
        where: r.job_id == ^job_id

    Repo.one(query)
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
  def get_output_dataclip_query(%Run{} = run) do
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
    |> Ecto.Changeset.change(%{})
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
  Returns an `%Ecto.Changeset{}` for tracking run changes.

  ## Examples

      iex> change_run(run)
      %Ecto.Changeset{data: %Run{}}

  """
  def change_run(%Run{} = run, attrs \\ %{}) do
    Run.changeset(run, attrs)
  end

  @doc """
  Searches for work orders based on project and search parameters.

  ## Parameters:
  - `project`: The project to filter the work orders by.
  - `search_params`: The parameters to guide the search.

  ## Returns:
  A paginated list of work orders that match the criteria.

  ## Example:
      search_workorders(%Project{id: 1}, %SearchParams{status: ["completed"]})
  """
  def search_workorders(%Project{} = project) do
    search_params = SearchParams.new(%{})
    search_workorders(project, search_params, %{})
  end

  def search_workorders(
        %Project{} = project,
        %SearchParams{search_term: search_term} = search_params,
        params \\ %{}
      ) do
    params =
      update_in(
        params,
        [:options],
        fn options ->
          [timeout: @workorders_search_timeout]
          |> Keyword.merge(options || [])
          |> then(fn options ->
            if search_term do
              Keyword.put(options, :limit, @workorders_count_limit)
            else
              options
            end
          end)
        end
      )

    project
    |> search_workorders_query(search_params)
    |> Repo.paginate(params)
  end

  def search_workorders_query(
        %Project{id: project_id},
        %SearchParams{status: status_list} = search_params
      ) do
    status_filter =
      if SearchParams.all_statuses_set?(search_params) do
        []
      else
        status_list
      end

    base_query(project_id)
    |> filter_by_workorder_id(search_params.workorder_id)
    |> filter_by_workflow_id(search_params.workflow_id)
    |> filter_by_statuses(status_filter)
    |> filter_by_wo_date_after(search_params.wo_date_after)
    |> filter_by_wo_date_before(search_params.wo_date_before)
    |> filter_by_date_after(search_params.date_after)
    |> filter_by_date_before(search_params.date_before)
    |> filter_by_body_or_log_or_id(
      search_params.search_fields,
      search_params.search_term
    )
  end

  defp base_query(project_id) do
    from(
      workorder in WorkOrder,
      as: :workorder,
      join: workflow in assoc(workorder, :workflow),
      as: :workflow,
      where: workflow.project_id == ^project_id,
      select: workorder,
      preload: [workflow: workflow, attempts: [runs: :job]],
      order_by: [desc_nulls_first: workorder.last_activity],
      distinct: true
    )
  end

  defp filter_by_workorder_id(query, nil), do: query

  defp filter_by_workorder_id(query, workorder_id)
       when is_binary(workorder_id) do
    from([workorder: workorder] in query, where: workorder.id == ^workorder_id)
  end

  defp filter_by_workflow_id(query, nil), do: query

  defp filter_by_workflow_id(query, workflow_id) when is_binary(workflow_id) do
    from([workflow: workflow] in query, where: workflow.id == ^workflow_id)
  end

  defp filter_by_statuses(query, []), do: query

  defp filter_by_statuses(query, statuses) when is_list(statuses) do
    from([workorder: workorder] in query, where: workorder.state in ^statuses)
  end

  defp filter_by_wo_date_after(query, nil), do: query

  defp filter_by_wo_date_after(query, wo_date_after) do
    from([workorder: workorder] in query,
      where: workorder.inserted_at >= ^wo_date_after
    )
  end

  defp filter_by_wo_date_before(query, nil), do: query

  defp filter_by_wo_date_before(query, wo_date_before) do
    from([workorder: workorder] in query,
      where: workorder.inserted_at <= ^wo_date_before
    )
  end

  defp filter_by_date_after(query, nil), do: query

  defp filter_by_date_after(query, date_after) do
    from([workorder: workorder] in query,
      where: workorder.last_activity >= ^date_after
    )
  end

  defp filter_by_date_before(query, nil), do: query

  defp filter_by_date_before(query, date_before) do
    from([workorder: workorder] in query,
      where: workorder.last_activity <= ^date_before
    )
  end

  defp filter_by_body_or_log_or_id(query, _search_fields, nil), do: query

  defp filter_by_body_or_log_or_id(query, search_fields, search_term) do
    query = build_search_fields_query(query, search_fields)

    from query, where: ^build_search_fields_where(search_fields, search_term)
  end

  defp build_search_fields_where(search_fields, search_term) do
    Enum.reduce(search_fields, dynamic(false), fn
      :body, dynamic ->
        dynamic(
          [input_dataclip: dataclip],
          ^dynamic or ilike(type(dataclip.body, :string), ^"%#{search_term}%")
        )

      :id, dynamic ->
        dynamic(
          [workorder: wo, attempts: att, runs: run],
          ^dynamic or like(type(wo.id, :string), ^"%#{search_term}%") or
            like(type(att.id, :string), ^"%#{search_term}%") or
            like(type(run.id, :string), ^"%#{search_term}%")
        )

      :log, dynamic ->
        dynamic(
          [log_lines: log_line],
          ^dynamic or
            ilike(type(log_line.message, :string), ^"%#{search_term}%")
        )

      _other, dynamic ->
        # Not a valid search field
        dynamic
    end)
  end

  defp build_search_fields_query(base_query, search_fields) do
    Enum.reduce(search_fields, base_query, fn
      :body, query ->
        from [runs: run] in safe_join_runs(query),
          left_join: dataclip in assoc(run, :input_dataclip),
          as: :input_dataclip

      :log, query ->
        from [attempts: attempt] in safe_join_attempts(query),
          left_join: log_line in assoc(attempt, :log_lines),
          as: :log_lines

      :id, query ->
        safe_join_runs(query)

      _other, query ->
        query
    end)
  end

  defp safe_join_attempts(query) do
    if has_named_binding?(query, :attempts) do
      query
    else
      join(query, :left, [workorder: workorder], assoc(workorder, :attempts),
        as: :attempts
      )
    end
  end

  defp safe_join_runs(query) do
    if has_named_binding?(query, :runs) do
      query
    else
      from [attempts: attempt] in safe_join_attempts(query),
        left_join: run in assoc(attempt, :runs),
        as: :runs
    end
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
            ^from(job in Lightning.Workflows.Job,
              select: %{id: job.id, name: job.name}
            )
        ]
      )

    attempts_query =
      from(a in Lightning.Attempt,
        order_by: [desc: a.inserted_at],
        preload: [runs: ^runs_query]
      )

    # we can use a ^custom_query to control (order_by ...) the way preloading is done
    from(wo in query,
      preload: [
        workflow:
          ^from(wf in Lightning.Workflows.Workflow,
            select: %{id: wf.id, name: wf.name, project_id: wf.project_id}
          ),
        attempts: ^attempts_query
      ]
    )
  end

  @doc """
  Return all logs for a run as a list
  """
  @spec logs_for_run(Run.t()) :: list()
  def logs_for_run(%Run{} = run) do
    Ecto.assoc(run, :log_lines)
    |> order_by([l], asc: l.timestamp)
    |> Repo.all()
  end

  def assemble_logs_for_run(nil), do: nil

  @doc """
  Return all logs for a run as a string of text, separated by new line \n breaks
  """
  @spec assemble_logs_for_run(Run.t()) :: binary()
  def assemble_logs_for_run(%Run{} = run),
    do:
      logs_for_run(run)
      |> Enum.map_join("\n", fn log -> log.message end)
end
