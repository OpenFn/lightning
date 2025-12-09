defmodule Lightning.Invocation do
  @moduledoc """
  The Invocation context.
  """
  import Ecto.Query, warn: false
  import Lightning.Helpers, only: [coerce_json_field: 2]

  alias Lightning.Accounts.User
  alias Lightning.Invocation.Dataclip
  alias Lightning.Invocation.DataclipAudit
  alias Lightning.Invocation.Query
  alias Lightning.Invocation.Step
  alias Lightning.Projects.File, as: ProjectFile
  alias Lightning.Projects.Project
  alias Lightning.Repo
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Trigger
  alias Lightning.WorkOrder
  alias Lightning.WorkOrders.ExportAudit
  alias Lightning.WorkOrders.ExportWorker
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

  @spec list_dataclips_query(Project.t()) :: Ecto.Queryable.t()
  def list_dataclips_query(%Project{id: project_id}) do
    from(d in Dataclip,
      where: d.project_id == ^project_id,
      order_by: [desc: d.inserted_at]
    )
  end

  @spec list_dataclips(Project.t()) :: [Dataclip.t()]
  def list_dataclips(%Project{id: project_id}) do
    list_dataclips_query(%Project{id: project_id}) |> Repo.all()
  end

  @spec list_dataclips_for_job(Job.t(), limit :: pos_integer()) :: [Dataclip.t()]
  def list_dataclips_for_job(%Job{id: job_id}, limit \\ 5) do
    Query.last_n_for_job(job_id, limit)
    |> where([d], is_nil(d.wiped_at))
    |> Repo.all()
  end

  @spec list_dataclips_for_job(
          Job.t(),
          user_filters :: map(),
          opts :: Keyword.t()
        ) :: [Dataclip.t()]
  def list_dataclips_for_job(%Job{id: job_id}, user_filters, opts) do
    limit = Keyword.fetch!(opts, :limit)
    offset = Keyword.get(opts, :offset)

    Query.last_n_for_job(job_id, limit)
    |> where([d], is_nil(d.wiped_at))
    |> where([d], ^dataclip_where_filter(user_filters))
    |> then(fn query -> if offset, do: query, else: offset(query, ^offset) end)
    |> Repo.all()
    |> maybe_filter_uuid_prefix(user_filters)
  end

  @spec get_dataclip_with_body!(id :: Ecto.UUID.t()) :: %{
          body_json: String.t(),
          type: atom(),
          id: Ecto.UUID.t(),
          updated_at: DateTime.t()
        }
  def get_dataclip_with_body!(id) do
    # Query body as pretty-printed JSON text directly from PostgreSQL, avoiding expensive
    # deserialization to Elixir map (saves ~38x memory amplification!)
    # For http_request/kafka types, wraps body in {"data": ..., "request": ...} structure
    dataclip =
      from(d in Lightning.Invocation.Dataclip, where: d.id == ^id)
      |> Query.select_as_input_text()
      |> Repo.one!()

    %{
      body_json: dataclip.body,
      type: dataclip.type,
      id: dataclip.id,
      updated_at: dataclip.updated_at
    }
  end

  @spec get_dataclip_for_run(run_id :: Ecto.UUID.t()) ::
          Dataclip.t() | nil
  def get_dataclip_for_run(run_id) do
    query =
      from d in Dataclip,
        join: a in Lightning.Run,
        on: a.dataclip_id == d.id and a.id == ^run_id

    Repo.one(query)
  end

  @spec get_first_dataclip_for_run_and_job(
          run_id :: Ecto.UUID.t(),
          job_id :: Ecto.UUID.t()
        ) ::
          Dataclip.t() | nil
  def get_first_dataclip_for_run_and_job(run_id, job_id) do
    query =
      from d in Dataclip,
        join: s in Lightning.Invocation.Step,
        on: s.input_dataclip_id == d.id and s.job_id == ^job_id,
        join: a in assoc(s, :runs),
        on: a.id == ^run_id

    query
    |> first(:inserted_at)
    |> Repo.one()
  end

  @spec get_first_step_for_run_and_job(
          run_id :: Ecto.UUID.t(),
          job_id :: Ecto.UUID.t()
        ) ::
          Lightning.Invocation.Step.t() | nil
  def get_first_step_for_run_and_job(run_id, job_id) do
    query =
      from s in Lightning.Invocation.Step,
        join: a in assoc(s, :runs),
        on: a.id == ^run_id,
        where: s.job_id == ^job_id,
        preload: [snapshot: [triggers: :webhook_auth_methods]]

    query
    |> first(:inserted_at)
    |> Repo.one()
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
  Gets the next cron run dataclip for a job.

  Returns the most recent output dataclip from a successful step for the given job,
  filtered by the provided database filters.
  """
  @spec get_next_cron_run_dataclip(
          job_id :: Ecto.UUID.t(),
          db_filters :: Ecto.Query.dynamic_expr()
        ) ::
          map() | nil
  def get_next_cron_run_dataclip(job_id, db_filters) do
    from(d in Dataclip,
      join: s in Step,
      on: s.output_dataclip_id == d.id,
      where:
        s.job_id == ^job_id and s.exit_reason == "success" and
          is_nil(d.wiped_at),
      where: ^db_filters,
      order_by: [desc: s.finished_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Checks if a job is triggered by a cron trigger.
  """
  @spec cron_triggered_job?(job_id :: Ecto.UUID.t()) :: boolean()
  def cron_triggered_job?(job_id) do
    from(e in Edge,
      join: t in Trigger,
      on: e.source_trigger_id == t.id,
      where: e.target_job_id == ^job_id and t.type == :cron
    )
    |> Repo.exists?()
  end

  @doc """
  Lists dataclips for a job, including next cron run state if cron-triggered.

  For cron-triggered jobs, this function will include the next run state dataclip
  and return its ID even if it doesn't match the filters.

  Returns a tuple of {dataclips, next_cron_run_dataclip_id}.
  """
  @spec list_dataclips_for_job_with_cron_state(
          Job.t(),
          user_filters :: map(),
          opts :: Keyword.t()
        ) :: {[Dataclip.t()], Ecto.UUID.t() | nil}
  def list_dataclips_for_job_with_cron_state(
        %Job{id: job_id} = job,
        user_filters,
        opts
      ) do
    if cron_triggered_job?(job_id) do
      list_dataclips_with_cron_state(job_id, user_filters, opts)
    else
      dataclips = list_dataclips_for_job(job, user_filters, opts)
      {dataclips, nil}
    end
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

  @spec update_dataclip_name(Dataclip.t(), String.t() | nil, User.t()) ::
          {:ok, Dataclip.t()} | {:error, Ecto.Changeset.t()}
  def update_dataclip_name(%Dataclip{} = dataclip, name, acting_user) do
    changeset =
      dataclip
      |> Ecto.Changeset.cast(%{name: name}, [:name])
      |> Ecto.Changeset.unique_constraint([:name, :project_id])

    Repo.transact(fn ->
      with {:ok, updated_dataclip} <- Repo.update(changeset),
           {:ok, _} <-
             DataclipAudit.save_name_updated(dataclip, changeset, acting_user) do
        {:ok, updated_dataclip}
      end
    end)
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
  Gets a step by ID with its input and output dataclips preloaded.
  Returns nil if step not found.

  Note: Dataclip body fields have `load_in_query: false` for performance,
  so we use a custom preload query to explicitly select the body field.
  """
  @spec get_step_with_dataclips(Ecto.UUID.t()) :: Step.t() | nil
  def get_step_with_dataclips(step_id) do
    # Dataclip.body has load_in_query: false, so we need to explicitly select it
    dataclip_with_body_query =
      from(d in Dataclip, select: %{d | body: d.body})

    Step
    |> where([s], s.id == ^step_id)
    |> preload(input_dataclip: ^dataclip_with_body_query)
    |> preload(output_dataclip: ^dataclip_with_body_query)
    |> Repo.one()
  end

  @doc """
  Fetches a step and preloads the job via the step's event.
  """
  def get_step_with_job!(id),
    do: from(s in Step, where: s.id == ^id, preload: :job) |> Repo.one!()

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

  @spec search_workorders(
          Lightning.Projects.Project.t(),
          SearchParams.t(),
          keyword | map
        ) :: Scrivener.Page.t(WorkOrder.t())
  def search_workorders(
        %Project{id: project_id},
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

    project_id
    |> base_query()
    |> search_workorders_query(search_params)
    |> Repo.paginate(params)
  end

  def search_workorders_for_retry(
        %Project{id: project_id},
        search_params
      ) do
    project_id
    |> base_query_without_preload()
    |> search_workorders_query(search_params)
    |> exclude_wiped_dataclips()
    |> Repo.all()
  end

  def search_workorders_for_export_query(%Project{id: project_id}, search_params) do
    project_id
    |> base_query_without_preload()
    |> search_workorders_query(search_params)
  end

  def count_workorders(%Project{id: project_id}, search_params) do
    project_id
    |> base_query_without_preload()
    |> search_workorders_query(search_params)
    |> Repo.aggregate(:count)
  end

  defp search_workorders_query(
         query,
         %SearchParams{status: status_list} = search_params
       ) do
    status_filter =
      if SearchParams.all_statuses_set?(search_params) do
        []
      else
        status_list
      end

    query
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
    |> apply_sorting(search_params.sort_by, search_params.sort_direction)
  end

  defp exclude_wiped_dataclips(work_order_query) do
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
        :dataclip,
        workflow: workflow,
        runs: [
          steps: [
            :job,
            :input_dataclip,
            snapshot: [triggers: :webhook_auth_methods]
          ]
        ],
        snapshot: [triggers: :webhook_auth_methods]
      ],
      order_by: [desc_nulls_first: workorder.last_activity],
      distinct: true
    )
  end

  defp base_query_without_preload(project_id) do
    from(
      workorder in WorkOrder,
      as: :workorder,
      join: workflow in assoc(workorder, :workflow),
      as: :workflow,
      where: workflow.project_id == ^project_id,
      select: workorder,
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
    ts_query = for_tsquery_partial_match(search_term)

    Enum.reduce(search_fields, dynamic(false), fn
      :body, dynamic ->
        dynamic(
          [input_dataclip: dataclip],
          ^dynamic or
            fragment(
              "? @@ to_tsquery('english_nostop', ?)",
              dataclip.search_vector,
              ^ts_query
            )
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
            fragment(
              "? @@ to_tsquery('english_nostop', ?)",
              log_line.search_vector,
              ^ts_query
            )
        )

      :dataclip_name, dynamic ->
        dynamic(
          [dataclip: d],
          ^dynamic or ilike(d.name, ^"%#{search_term}%")
        )
    end)
  end

  defp for_tsquery_partial_match(string) do
    "'" <> String.replace(string, "'", " ", global: true) <> "':*"
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

      :dataclip_name, query ->
        safe_join_dataclip(query)
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

  defp safe_join_dataclip(query) do
    if has_named_binding?(query, :dataclip) do
      query
    else
      join(query, :left, [workorder: workorder], assoc(workorder, :dataclip),
        as: :dataclip
      )
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

  @spec assemble_logs_for_job_and_run(Ecto.UUID.t(), Ecto.UUID.t()) :: binary()
  def assemble_logs_for_job_and_run(job_id, run_id) do
    query =
      from s in Step,
        join: l in assoc(s, :log_lines),
        on: s.job_id == ^job_id,
        where: l.run_id == ^run_id,
        order_by: [asc: l.timestamp],
        select: l.message

    query
    |> Repo.all()
    |> Enum.join("\n")
  end

  def assemble_logs_for_step(nil), do: nil

  @doc """
  Return all logs for a step as a string of text, separated by new line \n breaks
  """
  @spec assemble_logs_for_step(Step.t()) :: binary()
  def assemble_logs_for_step(%Step{} = step) do
    step
    |> Ecto.assoc(:log_lines)
    |> order_by([l], asc: l.timestamp)
    |> select([l], l.message)
    |> Repo.all()
    |> Enum.join("\n")
  end

  @doc """
  Exports work orders by performing a series of database operations wrapped in a transaction.

  This function creates an audit log, a project file record, and enqueues an export job using a transaction.
  Each step is executed as part of an `Ecto.Multi` operation, ensuring atomicity.

  ## Parameters

    - `project` - The project for which work orders are being exported. Expected to be a map or struct with an `id` field.
    - `user` - The user initiating the export operation. Expected to be a map or struct with an `id` field.
    - `search_params` - A map of search parameters used to filter work orders to export.

  ## Returns

    - `{:ok, %{audit: audit, project_file: project_file, export_job: job}}` on success:
      - `audit`: The audit log entry created for the export operation.
      - `project_file`: The project file record created for the export operation.
      - `export_job`: The result of the export job enqueuing step.

    - `{:error, step, reason, changes}` if any step in the transaction fails:
      - `step`: The step where the error occurred, e.g., `:audit`, `:project_file`, or `:export_job`.
      - `reason`: The reason for the failure, typically an error atom.
      - `changes`: A map of changes up to the point of failure.
  """
  def export_workorders(project, user, search_params) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(
      :audit,
      ExportAudit.event(
        "requested",
        project.id,
        user,
        %{},
        %{search_params: search_params}
      )
    )
    |> Ecto.Multi.insert(
      :project_file,
      ProjectFile.new(%{
        type: :export,
        status: :enqueued,
        created_by: user,
        project: project
      })
    )
    |> Ecto.Multi.run(:export_job, fn _repo, %{project_file: project_file} ->
      ExportWorker.enqueue_export(
        project,
        project_file,
        search_params
      )
    end)
    |> Repo.transaction()
  end

  # Query dataclips for cron-triggered jobs, including the next run state
  defp list_dataclips_with_cron_state(job_id, user_filters, opts) do
    # Get the next cron run dataclip (always needed for the ID)
    next_cron_dataclip = get_next_cron_run_dataclip(job_id, dynamic(true))
    next_cron_run_dataclip_id = next_cron_dataclip && next_cron_dataclip.id

    # Check if next cron dataclip matches user filters
    include_next_cron? =
      next_cron_dataclip &&
        dataclip_matches_filters?(next_cron_dataclip, user_filters)

    # Get regular dataclips, excluding next cron if it will be included to avoid duplication
    filters =
      if include_next_cron?,
        do: Map.put(user_filters, :exclude_id, next_cron_dataclip.id),
        else: user_filters

    regular_dataclips = list_dataclips_for_job(%Job{id: job_id}, filters, opts)

    # Combine results with next cron dataclip first if it matches filters
    dataclips =
      if include_next_cron?,
        do: [next_cron_dataclip | regular_dataclips],
        else: regular_dataclips

    {dataclips, next_cron_run_dataclip_id}
  end

  # Check if a dataclip matches the user filters (applied in Elixir)
  defp dataclip_matches_filters?(dataclip, user_filters) do
    Enum.all?(user_filters, fn
      {:id, uuid} ->
        dataclip.id == uuid

      {:name_or_id_part, query} ->
        String.starts_with?(dataclip.id, query) or
          dataclip_name_matches?(dataclip.name, query)

      {:type, type} ->
        dataclip.type == type

      {:after, ts} ->
        DateTime.compare(dataclip.inserted_at, ts) != :lt

      {:before, ts} ->
        DateTime.compare(dataclip.inserted_at, ts) != :gt

      {:exclude_id, exclude_id} ->
        dataclip.id != exclude_id

      {:name_part, name_part} ->
        dataclip_name_matches?(dataclip.name, name_part)

      {:named_only, true} ->
        is_binary(dataclip.name)

      _other ->
        true
    end)
  end

  defp dataclip_name_matches?(nil, _name_part), do: false

  defp dataclip_name_matches?(name, name_part) do
    name
    |> String.downcase()
    |> String.contains?(String.downcase(name_part))
  end

  # credo:disable-for-next-line
  defp dataclip_where_filter(user_filters) do
    Enum.reduce(user_filters, dynamic(true), fn
      {:id, uuid}, dynamic ->
        dynamic([d], ^dynamic and d.id == ^uuid)

      {:name_or_id_part, query}, dynamic ->
        {id_prefix_start, id_prefix_end} =
          id_prefix_interval(query)

        dynamic(
          [d],
          (^dynamic and ilike(d.name, ^"%#{query}%")) or
            (d.id > ^id_prefix_start and d.id < ^id_prefix_end)
        )

      {:type, type}, dynamic ->
        dynamic([d], ^dynamic and d.type == ^type)

      {:after, ts}, dynamic ->
        dynamic([d], ^dynamic and d.inserted_at >= ^ts)

      {:before, ts}, dynamic ->
        dynamic([d], ^dynamic and d.inserted_at <= ^ts)

      {:exclude_id, exclude_id}, dynamic ->
        dynamic([d], ^dynamic and d.id != ^exclude_id)

      {:name_part, name}, dynamic ->
        dynamic([d], ^dynamic and ilike(d.name, ^"%#{name}%"))

      {:named_only, true}, dynamic ->
        dynamic([d], ^dynamic and not is_nil(d.name))

      _other, dynamic ->
        dynamic
    end)
  end

  defp id_prefix_interval(id_prefix) do
    prefix_bin =
      id_prefix
      |> String.to_charlist()
      |> Enum.chunk_every(2)
      |> Enum.reduce(<<>>, fn
        [_single_char], prefix_bin ->
          prefix_bin

        byte_list, prefix_bin ->
          byte_int = byte_list |> :binary.list_to_bin() |> String.to_integer(16)
          prefix_bin <> <<byte_int>>
      end)

    prefix_size = byte_size(prefix_bin)

    # UUIDs are 128 bits (16 bytes) in binary form.
    # We calculate how many bytes are missing from the prefix.
    # missing_byte_size is the number of bytes to pad to reach a full UUID binary.
    # We pad with 0s for the lower bound and 255s for the upper bound.
    missing_byte_size = 16 - prefix_size

    {
      Ecto.UUID.load!(prefix_bin <> :binary.copy(<<0>>, missing_byte_size)),
      Ecto.UUID.load!(prefix_bin <> :binary.copy(<<255>>, missing_byte_size))
    }
  end

  # A pair of hex chars on UUID strings comprise a byte on UUID binary
  # Searching by prefix with an odd number of chars (not in pairs) requires
  # additional filtering once you can't filter half of a byte on the database
  # using > or < operators
  defp maybe_filter_uuid_prefix(dataclips, filters) do
    case Map.get(filters, :id_prefix, "") do
      id_prefix when rem(byte_size(id_prefix), 2) == 1 ->
        Enum.filter(dataclips, &String.starts_with?(&1.id, id_prefix))

      _ ->
        dataclips
    end
  end

  defp apply_sorting(query, sort_by, sort_direction)
       when sort_by in ["inserted_at", "last_activity"] and
              sort_direction in ["asc", "desc"] do
    sort_direction_atom = String.to_existing_atom(sort_direction)
    sort_field = String.to_existing_atom(sort_by)

    # Remove existing order_by clauses first
    query = exclude(query, :order_by)

    case sort_field do
      :inserted_at ->
        from([workorder: workorder] in query,
          order_by: [{^sort_direction_atom, workorder.inserted_at}]
        )

      :last_activity ->
        if sort_direction == "desc" do
          from([workorder: workorder] in query,
            order_by: [desc_nulls_first: workorder.last_activity]
          )
        else
          from([workorder: workorder] in query,
            order_by: [asc_nulls_last: workorder.last_activity]
          )
        end
    end
  end

  defp apply_sorting(query, _sort_by, _sort_direction) do
    # Default sorting: keep the original order_by from base_query
    query
  end

  @doc """
  Get a run with all its steps preloaded, including work_order and workflow
  for authorization checks.
  """
  def get_run_with_steps(run_id) do
    from(r in Lightning.Run,
      where: r.id == ^run_id,
      preload: [
        :steps,
        :created_by,
        work_order: [workflow: :project]
      ]
    )
    |> Repo.one()
  end
end
