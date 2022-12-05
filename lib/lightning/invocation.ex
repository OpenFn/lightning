defmodule Lightning.Invocation do
  @moduledoc """
  The Invocation context.
  """

  import Ecto.Query, warn: false
  import Lightning.Helpers, only: [coerce_json_field: 2]
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

        res

      res ->
        res
    end
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

  def filter_run_started_after_where(date_after) do
    case date_after do
      d when d in ["", nil] -> dynamic(true)
      _ -> dynamic([runs: r], r.started_at >= ^date_after)
    end
  end

  def filter_run_started_before_where(date_before) do
    case date_before do
      d when d in ["", nil] -> dynamic(true)
      _ -> dynamic([runs: r], r.started_at <= ^date_before)
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

  def filter_run_body_and_logs_where(search_term, searchfors)
      when search_term in ["", nil] or searchfors == [] do
    dynamic(true)
  end

  def filter_run_body_and_logs_where(search_term, searchfors) when searchfors != [] do
    Enum.reduce(searchfors, dynamic(false), fn
      :log, query ->
        dynamic(
          [runs: r],
          ^query or
            fragment("cast(?  as VARCHAR) ilike ?", r.log, ^"%#{search_term}%")
        )

      :body, query ->
        dynamic(
          [input: i],
          ^query or
            fragment("cast(?  as VARCHAR) ilike ?", i.body, ^"%#{search_term}%")
        )

      _, query ->
        # Not a where parameter
        query
    end)
  end

  def list_work_orders_for_project_query(
        %Project{id: project_id},
        status: status,
        searchfors: searchfors,
        search_term: search_term,
        workflow_id: workflow_id,
        date_after: date_after,
        date_before: date_before
      ) do

    # we can use a ^custom_query to control (order_by ...) the way preloading is done
    runs_query =
      from(r in Lightning.Invocation.Run,
        as: :runs,
        join: j in assoc(r, :job),
        join: d in assoc(r, :input_dataclip),
        as: :input,
        order_by: [asc: r.finished_at],
        where: r.input_dataclip_id == d.id,
        where: ^filter_run_status_where(status),
        where: ^filter_run_started_after_where(date_after),
        where: ^filter_run_started_before_where(date_before),
        where: ^filter_run_body_and_logs_where(search_term, searchfors),
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

    from(wo in Lightning.WorkOrder,
      join: wo_re in assoc(wo, :reason),
      join: w in assoc(wo, :workflow),
      as: :workflow,
      join: att in assoc(wo, :attempts),
      join: r in assoc(att, :runs),
      as: :runs,
      join: att_re in assoc(att, :reason),
      join: d in assoc(r, :input_dataclip),
      as: :input,
      where: w.project_id == ^project_id,
      where: d.id in [wo_re.dataclip_id, att_re.dataclip_id],
      where: ^filter_workflow_where(workflow_id),
      where: ^filter_run_status_where(status),
      where: ^filter_run_started_after_where(date_after),
      where: ^filter_run_started_before_where(date_before),
      where: ^filter_run_body_and_logs_where(search_term, searchfors),
      order_by: [desc_nulls_first: r.finished_at],
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
      ],
      select: %{
        id: wo.id,
        last_finished_at: r.finished_at,
        work_order: wo
      }
    )
  end

  def list_work_orders_for_project(%Project{} = project, filter, params)
      when filter in [nil, []] do
    list_work_orders_for_project(
      project,
      [
        status: [:success, :failure, :timeout, :crash, :pending],
        searchfors: [],
        search_term: "",
        workflow_id: "",
        date_after: "",
        date_before: ""
      ],
      params
    )
  end

  def list_work_orders_for_project(%Project{} = project, filter, params) do
    list_work_orders_for_project_query(project, filter)
    |> Repo.paginate(params)
    |> find_uniq_wo()
  end

  def find_uniq_wo(page) do
    %{page | entries: Enum.uniq_by(page.entries, fn wo -> wo.id end)}
  end

  def list_work_orders_for_project(%Project{} = project) do
    list_work_orders_for_project(
      project,
      [
        status: [:success, :failure, :timeout, :crash, :pending],
        searchfors: [],
        search_term: "",
        workflow_id: "",
        date_after: "",
        date_before: ""
      ],
      %{}
    )
  end
end
