defmodule Lightning.Invocation do
  @moduledoc """
  The Invocation context.
  """

  import Ecto.Query, warn: false
  import Lightning.Helpers, only: [coerce_json_field: 2]

  alias Lightning.Invocation.Dataclip
  alias Lightning.Invocation.Query
  alias Lightning.Invocation.Step
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
    Query.last_n_for_job(job_id, 5)
    |> Query.select_as_input()
    |> where([d], is_nil(d.wiped_at))
    |> Repo.all()
  end

  @spec get_dataclip_details!(id :: Ecto.UUID.t()) :: Dataclip.t()
  def get_dataclip_details!(id),
    do: Repo.get!(Query.dataclip_with_body(), id)

  @spec get_dataclip_for_run(run_id :: Ecto.UUID.t()) ::
          Dataclip.t() | nil
  def get_dataclip_for_run(run_id) do
    query =
      from d in Query.dataclip_with_body(),
        join: a in Lightning.Run,
        on: a.dataclip_id == d.id and a.id == ^run_id

    Repo.one(query)
  end

  @spec get_dataclip_for_run_and_job(
          run_id :: Ecto.UUID.t(),
          job_id :: Ecto.UUID.t()
        ) ::
          Dataclip.t() | nil
  def get_dataclip_for_run_and_job(run_id, job_id) do
    query =
      from d in Query.dataclip_with_body(),
        join: s in Lightning.Invocation.Step,
        on: s.input_dataclip_id == d.id and s.job_id == ^job_id,
        join: a in assoc(s, :runs),
        on: a.id == ^run_id

    Repo.one(query)
  end

  @spec get_step_for_run_and_job(
          run_id :: Ecto.UUID.t(),
          job_id :: Ecto.UUID.t()
        ) ::
          Lightning.Invocation.Step.t() | nil
  def get_step_for_run_and_job(run_id, job_id) do
    query =
      from s in Lightning.Invocation.Step,
        join: a in assoc(s, :runs),
        on: a.id == ^run_id,
        where: s.job_id == ^job_id

    Repo.one(query)
  end

  @spec get_step_count_for_run(run_id :: Ecto.UUID.t()) :: non_neg_integer()
  def get_step_count_for_run(run_id) do
    query =
      from s in Lightning.Invocation.Step,
        join: a in assoc(s, :runs),
        on: a.id == ^run_id

    Repo.aggregate(query, :count)
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
  - a Step model

  Returns `nil` if the Dataclip does not exist.

  ## Examples

      iex> get_dataclip("27b73932-16c7-4a72-86a3-85d805ccff98")
      %Dataclip{}

      iex> get_dataclip("27b73932-16c7-4a72-86a3-85d805ccff98")
      nil

      iex> get_dataclip(%Step{id: "a uuid"})
      %Dataclip{}

  """
  @spec get_dataclip(step_or_uuid :: Step.t() | Ecto.UUID.t()) ::
          Dataclip.t() | nil
  def get_dataclip(%Step{} = step) do
    get_dataclip_query(step) |> Repo.one()
  end

  def get_dataclip(id), do: Repo.get(Dataclip, id)

  @doc """
  Query for retrieving the dataclip that was the result of a successful step.
  """
  def get_output_dataclip_query(%Step{} = step) do
    Ecto.assoc(step, :output_dataclip)
  end

  @doc """
  Query for retrieving the dataclip that was step's starting dataclip.
  """
  def get_dataclip_query(%Step{} = step) do
    Ecto.assoc(step, :input_dataclip)
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
  Returns the list of steps.

  ## Examples

      iex> list_steps()
      [%Step{}, ...]

  """
  def list_steps do
    Repo.all(Step)
  end

  @spec list_steps_for_project_query(Lightning.Projects.Project.t()) ::
          Ecto.Query.t()
  def list_steps_for_project_query(%Project{id: project_id}) do
    from(s in Step,
      join: j in assoc(s, :job),
      join: w in assoc(j, :workflow),
      where: w.project_id == ^project_id,
      order_by: [desc: s.inserted_at, desc: s.started_at],
      preload: [job: j]
    )
  end

  @spec list_steps_for_project(Lightning.Projects.Project.t(), keyword | map) ::
          Scrivener.Page.t()
  def list_steps_for_project(%Project{} = project, params \\ %{}) do
    list_steps_for_project_query(project)
    |> Repo.paginate(params)
  end

  @doc """
  Gets a single step.

  Raises `Ecto.NoResultsError` if the Step does not exist.

  ## Examples

      iex> get_step!(123)
      %Step{}

      iex> get_step!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_step!(Ecto.UUID.t()) :: Step.t()
  def get_step!(id), do: Repo.get!(Step, id)

  @doc """
  Fetches a step and preloads the job via the step's event.
  """
  def get_step_with_job!(id),
    do: from(s in Step, where: s.id == ^id, preload: :job) |> Repo.one!()

  @doc """
  Creates a step.

  ## Examples

      iex> create_step(%{field: value})
      {:ok, %Step{}}

      iex> create_step(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_step(attrs \\ %{}) do
    %Step{}
    |> Step.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking step changes.

  ## Examples

      iex> change_step(step)
      %Ecto.Changeset{data: %Step{}}

  """
  def change_step(%Step{} = step, attrs \\ %{}) do
    Step.changeset(step, attrs)
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

  def exclude_wiped_dataclips(work_order_query) do
    work_order_query
    |> join(:inner, [workorder: wo], assoc(wo, :dataclip), as: :dataclip)
    |> where([dataclip: d], is_nil(d.wiped_at))
  end

  defp base_query(project_id) do
    from(
      workorder in WorkOrder,
      as: :workorder,
      join: workflow in assoc(workorder, :workflow),
      as: :workflow,
      where: workflow.project_id == ^project_id,
      select: workorder,
      preload: [
        workflow: workflow,
        runs: [steps: [:job, :input_dataclip]],
        dataclip: []
      ],
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
          [workorder: wo, runs: att, steps: step],
          ^dynamic or like(type(wo.id, :string), ^"%#{search_term}%") or
            like(type(att.id, :string), ^"%#{search_term}%") or
            like(type(step.id, :string), ^"%#{search_term}%")
        )

      :log, dynamic ->
        dynamic(
          [log_lines: log_line],
          ^dynamic or
            ilike(type(log_line.message, :string), ^"%#{search_term}%")
        )
    end)
  end

  defp build_search_fields_query(base_query, search_fields) do
    Enum.reduce(search_fields, base_query, fn
      :body, query ->
        from [steps: step] in safe_join_steps(query),
          left_join: dataclip in assoc(step, :input_dataclip),
          as: :input_dataclip

      :log, query ->
        from [runs: run] in safe_join_runs(query),
          left_join: log_line in assoc(run, :log_lines),
          as: :log_lines

      :id, query ->
        safe_join_steps(query)
    end)
  end

  defp safe_join_runs(query) do
    if has_named_binding?(query, :runs) do
      query
    else
      join(query, :left, [workorder: workorder], assoc(workorder, :runs),
        as: :runs
      )
    end
  end

  defp safe_join_steps(query) do
    if has_named_binding?(query, :steps) do
      query
    else
      from [runs: run] in safe_join_runs(query),
        left_join: step in assoc(run, :steps),
        as: :steps
    end
  end

  def get_workorders_by_ids(ids) do
    from(wo in Lightning.WorkOrder, where: wo.id in ^ids)
  end

  def with_runs(query) do
    steps_query =
      from(s in Lightning.Invocation.Step,
        as: :steps,
        join: j in assoc(s, :job),
        join: d in assoc(s, :input_dataclip),
        as: :input,
        order_by: [asc: s.finished_at],
        preload: [
          job:
            ^from(job in Lightning.Workflows.Job,
              select: %{id: job.id, name: job.name}
            )
        ]
      )

    runs_query =
      from(a in Lightning.Run,
        order_by: [desc: a.inserted_at],
        preload: [steps: ^steps_query]
      )

    # we can use a ^custom_query to control (order_by ...) the way preloading is done
    from(wo in query,
      preload: [
        workflow:
          ^from(wf in Lightning.Workflows.Workflow,
            select: %{id: wf.id, name: wf.name, project_id: wf.project_id}
          ),
        runs: ^runs_query
      ]
    )
  end

  @doc """
  Return all logs for a step as a list
  """
  @spec logs_for_step(Step.t()) :: list()
  def logs_for_step(%Step{} = step) do
    Ecto.assoc(step, :log_lines)
    |> order_by([l], asc: l.timestamp)
    |> Repo.all()
  end

  def assemble_logs_for_step(nil), do: nil

  @doc """
  Return all logs for a step as a string of text, separated by new line \n breaks
  """
  @spec assemble_logs_for_step(Step.t()) :: binary()
  def assemble_logs_for_step(%Step{} = step),
    do:
      logs_for_step(step)
      |> Enum.map_join("\n", fn log -> log.message end)
end
