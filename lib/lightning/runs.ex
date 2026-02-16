defmodule Lightning.Runs do
  @moduledoc """
  Gathers operations to create, update and delete Runs.
  """
  @behaviour Lightning.Extensions.RunQueue

  import Ecto.Query

  alias Ecto.Multi
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Invocation.LogLine
  alias Lightning.Repo
  alias Lightning.Run
  alias Lightning.Runs.Events
  alias Lightning.Runs.Handlers
  alias Lightning.Runs.PromExPlugin
  alias Lightning.Runs.RunOptions
  alias Lightning.Services.RunQueue
  alias Lightning.Services.UsageLimiter
  alias Lightning.Workflows.Workflow

  require Logger

  @doc """
  Enqueue a run to be processed.
  """
  @impl Lightning.Extensions.RunQueue
  def enqueue(run) do
    RunQueue.enqueue(run)
  end

  @impl Lightning.Extensions.RunQueue
  def enqueue_many(run) do
    RunQueue.enqueue_many(run)
  end

  # @doc """
  # Claim an available run.
  #
  # The `demand` parameter is used to request more than a since run,
  # all implementation should default to 1.
  # """
  @impl Lightning.Extensions.RunQueue
  def claim(demand \\ 1, worker_name) do
    RunQueue.claim(demand, worker_name)
  end

  # @doc """
  # Removes a run from the queue.
  # """
  @impl Lightning.Extensions.RunQueue
  def dequeue(run) do
    RunQueue.dequeue(run)
  end

  @doc """
  Get a run by id.

  Optionally preload associations by passing a list of atoms to `:include`.

      Lightning.Runs.get(id, include: [:workflow])
  """
  @spec get(Ecto.UUID.t(), [{:include, term()}]) ::
          Run.t() | nil
  def get(id, opts \\ []) do
    get_query(id, opts)
    |> Repo.one()
  end

  @doc """
  Get a run by id, preloading the snapshot and its credential.
  """
  @spec get_for_worker(Ecto.UUID.t()) :: Run.t() | nil
  def get_for_worker(id) do
    Multi.new()
    |> Multi.one(
      :__pre_check_run__,
      get_query(id, include: [snapshot: [jobs: :credential]])
    )
    |> Multi.merge(fn %{__pre_check_run__: run} ->
      Multi.new() |> Multi.put(:run, run)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{run: run}} -> run
    end
  end

  defp get_query(id, opts) do
    preloads = opts |> Keyword.get(:include, [])

    from(r in Run, where: r.id == ^id, preload: ^preloads)
  end

  @spec get_run_options(
          workflow_id :: Ecto.UUID.t(),
          project_id :: Ecto.UUID.t()
        ) :: RunOptions.t()
  def get_run_options(workflow_id, project_id) do
    workflow_options =
      Workflow
      |> where(id: ^workflow_id)
      |> select([w], map(w, [:enable_job_logs]))
      |> Repo.one!()

    project_options =
      UsageLimiter.get_run_options(%Context{project_id: project_id})

    struct(RunOptions, Enum.into(project_options, workflow_options))
  end

  @doc """
  Returns only the dataclip body as a string
  """
  def get_dataclip_body(%Run{} = run) do
    from(d in Ecto.assoc(run, :dataclip),
      select: type(d.body, :string)
    )
    |> Repo.one()
  end

  @doc """
  Returns only the dataclip request as a string
  """
  def get_dataclip_request(%Run{} = run) do
    from(d in Ecto.assoc(run, :dataclip),
      select: type(d.request, :string)
    )
    |> Repo.one()
  end

  @doc """
  Returns a run's dataclip formatted for use as state.

  Only `http_request` and kafka dataclips are changed,
  their `body` is nested inside a `"data"` key and `request` data
  is added as a `"request"` key.

  See LightingWeb.RunChannel.handle_in("fetch:dataclip", _, _)
  for more details.
  """
  @spec get_input(Run.t()) :: String.t() | nil
  def get_input(%Run{} = run) do
    from(d in Ecto.assoc(run, :dataclip),
      select:
        type(
          fragment(
            """
            CASE WHEN type IN ('http_request', 'kafka')
            THEN jsonb_build_object('data', ?, 'request', ?)
            ELSE ? END
            """,
            d.body,
            d.request,
            d.body
          ),
          :string
        )
    )
    |> Repo.one()
  end

  @doc """
  Clears the body and request fields of the dataclip associated with the given run.
  """
  @spec wipe_dataclips(Run.t()) :: :ok
  def wipe_dataclips(%Run{} = run) do
    run
    |> Ecto.assoc(:dataclip)
    |> select([d], d)
    |> Lightning.Invocation.Query.wipe_dataclips()
    |> Repo.update_all([])
    |> then(fn {1, [dataclip]} ->
      Events.dataclip_updated(run.id, dataclip)
      :ok
    end)
  end

  @spec get_credential(Run.t(), Ecto.UUID.t()) ::
          Lightning.Credentials.Credential.t() | nil
  def get_credential(%Run{} = run, id) do
    from(c in Ecto.assoc(run, [:workflow, :jobs, :credential]),
      where: c.id == ^id
    )
    |> Repo.one()
  end

  def start_run(%Run{} = run, params \\ %{}) do
    Handlers.StartRun.call(run, params)
  end

  @spec complete_run(Run.t(), %{optional(any()) => any()}) ::
          {:ok, Run.t()} | {:error, Ecto.Changeset.t(Run.t())}
  def complete_run(run, params) do
    Handlers.CompleteRun.call(run, params)
  end

  @spec update_run(Ecto.Changeset.t(Run.t())) ::
          {:ok, Run.t()} | {:error, Ecto.Changeset.t(Run.t())}
  def update_run(%Ecto.Changeset{data: %Run{}} = changeset) do
    run_id = Ecto.Changeset.get_field(changeset, :id)

    run_query =
      from(a in Run,
        where: a.id == ^run_id,
        lock: "FOR UPDATE"
      )

    update_query =
      Run
      |> with_cte("subset", as: ^run_query)
      |> join(:inner, [a], s in fragment(~s("subset")), on: a.id == s.id)
      |> select([a, _], a)

    case update_runs(update_query, changeset) do
      {:ok, %{runs: {1, [run]}}} ->
        {:ok, run}

      {:error, _op, changeset, _changes} ->
        {:error, changeset}
    end
  end

  def update_runs(update_query, updates) do
    updates =
      case updates do
        %Ecto.Changeset{changes: changes} -> [set: changes |> Enum.into([])]
        updates when is_list(updates) -> updates
      end

    Ecto.Multi.new()
    |> Ecto.Multi.update_all(:runs, update_query, updates)
    |> Ecto.Multi.run(:post, fn _repo, %{runs: {_, runs}} ->
      Enum.each(runs, fn run ->
        {:ok, _run} = Lightning.WorkOrders.update_state(run)
      end)

      {:ok, nil}
    end)
    |> Repo.transaction()
    |> tap(fn result ->
      with {:ok, %{runs: {_n, runs}}} <- result do
        # TODO: remove the requirement for events to be hydrated with a specific
        # set of preloads.
        runs
        |> Enum.map(fn run ->
          Repo.preload(run, [
            :snapshot,
            :created_by,
            :starting_trigger,
            workflow: [:project]
          ])
        end)
        |> Enum.each(fn run ->
          # Broadcast to run-specific topic (for run viewer)
          Events.run_updated(run)
          # Broadcast to project topic (for workflow channel/history)
          Lightning.WorkOrders.Events.run_updated(run.workflow.project_id, run)
        end)
      end
    end)
  end

  def append_run_log(run, params, scrubber \\ nil) do
    LogLine.new(run, params, scrubber)
    |> Ecto.Changeset.validate_change(:step_id, fn _field, step_id ->
      if is_nil(step_id) do
        []
      else
        where(Lightning.RunStep, step_id: ^step_id, run_id: ^run.id)
        |> Repo.exists?()
        |> if do
          []
        else
          [{:step_id, "must be associated with the run"}]
        end
      end
    end)
    |> Repo.insert()
    |> case do
      {:ok, log_line} ->
        Events.log_appended(log_line)
        {:ok, log_line}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Appends multiple log lines to a run in a batch operation.

  Returns `{:ok, [%LogLine{}, ...]}` if all logs are inserted successfully, or `{:error, changeset}`
  for the first validation error encountered.
  """
  def append_run_logs_batch(run, log_entries, scrubber \\ nil)
      when is_list(log_entries) do
    valid_step_ids = fetch_valid_step_ids(run, log_entries)

    changesets =
      Enum.map(log_entries, fn log_entry ->
        LogLine.new(run, log_entry, scrubber)
        |> Ecto.Changeset.validate_change(:step_id, fn _field, step_id ->
          validate_step_id(step_id, valid_step_ids)
        end)
      end)

    with {:ok, log_lines} <- insert_all_logs(changesets) do
      Enum.each(log_lines, &Events.log_appended/1)

      {:ok, log_lines}
    end
  end

  defp fetch_valid_step_ids(run, log_entries) do
    step_ids =
      log_entries
      |> Enum.map(&(Map.get(&1, "step_id") || Map.get(&1, :step_id)))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if Enum.empty?(step_ids) do
      []
    else
      from(s in Lightning.RunStep,
        where: s.step_id in ^step_ids and s.run_id == ^run.id,
        select: s.step_id
      )
      |> Repo.all()
    end
  end

  defp validate_step_id(nil, _valid_step_ids), do: []

  defp validate_step_id(step_id, valid_step_ids) do
    if step_id in valid_step_ids do
      []
    else
      [{:step_id, "must be associated with the run"}]
    end
  end

  defp insert_all_logs(changesets) do
    case Enum.find(changesets, fn cs -> not cs.valid? end) do
      nil ->
        entries =
          Enum.map(changesets, fn changeset ->
            changeset
            |> Ecto.Changeset.apply_changes()
            |> Map.take(LogLine.__schema__(:fields))
          end)

        {_count, log_lines} =
          Repo.insert_all(
            Lightning.Invocation.LogLine,
            entries,
            returning: true
          )

        {:ok, log_lines}

      invalid_changeset ->
        {:error, invalid_changeset}
    end
  end

  @doc """
  Creates a Step for a given run and job.

  The Step is created and marked as started at the current time.
  """
  @spec start_step(Run.t(), map()) ::
          {:ok, Lightning.Invocation.Step.t()} | {:error, Ecto.Changeset.t()}
  def start_step(run, params) do
    Handlers.StartStep.call(run, params)
  end

  @spec complete_step(map(), Lightning.Runs.RunOptions) ::
          {:ok, Lightning.Invocation.Step.t()} | {:error, Ecto.Changeset.t()}
  def complete_step(params, options \\ Lightning.Runs.RunOptions) do
    Handlers.CompleteStep.call(params, options)
  end

  @spec mark_run_lost(Lightning.Run.t()) ::
          {:ok, any()} | {:error, any()}
  def mark_run_lost(%Run{} = run) do
    error_type =
      case run.state do
        :claimed -> "LostAfterClaim"
        :started -> "LostAfterStart"
        _other -> "UnknownReason"
      end

    result =
      Repo.transaction(fn ->
        case complete_run(run, %{state: "lost", error_type: error_type}) do
          {:ok, updated_run} ->
            Ecto.assoc(run, :steps)
            |> where([r], is_nil(r.exit_reason))
            |> mark_steps_lost()

            {:ok, updated_run}

          {:error, changeset} ->
            Repo.rollback({:error, :already_completed, changeset})
        end
      end)

    case result do
      {:ok, {:ok, updated_run}} ->
        PromExPlugin.fire_lost_run_event()

        Logger.warning(fn ->
          "Detected lost run with reason #{error_type}: #{inspect(run)}"
        end)

        {:ok, updated_run}

      {:error, {:error, :already_completed, _changeset}} ->
        {:error, :already_completed}

      error ->
        error
    end
  end

  @spec mark_steps_lost(Ecto.Queryable.t()) :: {:ok, non_neg_integer()}
  def mark_steps_lost(steps_query) do
    {updated_count, nil} =
      Repo.update_all(
        steps_query,
        [set: [exit_reason: "lost", finished_at: DateTime.utc_now()]],
        returning: false
      )

    {:ok, updated_count}
  end

  defdelegate subscribe(run), to: Events

  @doc """
  Returns a query for runs belonging to a specific project
  """
  @spec runs_for_project_query(Lightning.Projects.Project.t()) ::
          Ecto.Queryable.t()
  def runs_for_project_query(%Lightning.Projects.Project{} = project) do
    Lightning.Invocation.Query.runs_for(project)
  end

  @doc """
  Returns a query for runs accessible to a user
  """
  @spec runs_for_user_query(Lightning.Accounts.User.t()) ::
          Ecto.Queryable.t()
  def runs_for_user_query(%Lightning.Accounts.User{} = user) do
    Lightning.Invocation.Query.runs_for(user)
  end

  @spec get_project_id_for_run(Run.t()) :: Ecto.UUID.t() | nil
  def get_project_id_for_run(run) do
    Ecto.assoc(run, [:work_order, :workflow, :project])
    |> select([p], p.id)
    |> Repo.one()
  end

  def get_log_lines(run, order \\ :asc) do
    Ecto.assoc(run, :log_lines)
    |> order_by([{^order, :timestamp}])
    |> Repo.stream()
  end
end
