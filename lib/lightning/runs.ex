defmodule Lightning.Runs do
  @moduledoc """
  Gathers operations to create, update and delete Runs.
  """
  import Ecto.Query

  alias Lightning.Invocation.LogLine
  alias Lightning.Repo
  alias Lightning.Run
  alias Lightning.Runs.Events
  alias Lightning.Runs.Handlers
  alias Lightning.Services.RunQueue

  require Logger

  @doc """
  Enqueue a run to be processed.
  """
  def enqueue(run) do
    RunQueue.enqueue(run)
  end

  # @doc """
  # Claim an available run.
  #
  # The `demand` parameter is used to request more than a since run,
  # all implementation should default to 1.
  # """
  def claim(demand \\ 1) do
    RunQueue.claim(demand)
  end

  # @doc """
  # Removes a run from the queue.
  # """
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
    preloads = opts |> Keyword.get(:include, [])

    from(a in Run,
      where: a.id == ^id,
      preload: ^preloads
    )
    |> Repo.one()
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

  Only `http_request` dataclips are changed, their `body` is nested inside a
  `"data"` key and `request` data is added as a `"request"` key.

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
            CASE WHEN type = 'http_request'
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
    query =
      from(d in Ecto.assoc(run, :dataclip),
        update: [set: [request: nil, body: nil, wiped_at: ^DateTime.utc_now()]],
        select: d
      )

    query
    |> Repo.update_all([])
    |> then(fn {1, [dataclip]} ->
      Events.dataclip_updated(run.id, dataclip)
      :ok
    end)
  end

  def get_credential(%Run{} = run, id) do
    from(c in Ecto.assoc(run, [:workflow, :jobs, :credential]),
      where: c.id == ^id
    )
    |> Repo.one()
  end

  def start_run(%Run{} = run) do
    Run.start(run)
    |> update_run()
    |> tap(&track_run_queue_delay/1)
  end

  @spec complete_run(Run.t(), %{optional(any()) => any()}) ::
          {:ok, Run.t()} | {:error, Ecto.Changeset.t(Run.t())}
  def complete_run(run, params) do
    Run.complete(run, params)
    |> case do
      %{valid?: false} = changeset ->
        {:error, changeset}

      changeset ->
        changeset |> update_run()
    end
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
    |> Ecto.Multi.run(:post, fn _, %{runs: {_, runs}} ->
      Enum.each(runs, fn run ->
        {:ok, _} = Lightning.WorkOrders.update_state(run)
      end)

      {:ok, nil}
    end)
    |> Repo.transaction()
    |> tap(fn result ->
      with {:ok, %{runs: {_n, runs}}} <- result do
        Enum.each(runs, &Events.run_updated/1)
      end
    end)
  end

  def append_run_log(run, params, scrubber \\ nil) do
    LogLine.new(run, params, scrubber)
    |> Ecto.Changeset.validate_change(:step_id, fn _, step_id ->
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
  Creates a Step for a given run and job.

  The Step is created and marked as started at the current time.
  """
  @spec start_step(map()) ::
          {:ok, Lightning.Invocation.Step.t()} | {:error, Ecto.Changeset.t()}
  def start_step(params) do
    Handlers.StartStep.call(params)
  end

  @spec complete_step(map(), Lightning.Projects.Project.retention_policy_type()) ::
          {:ok, Lightning.Invocation.Step.t()} | {:error, Ecto.Changeset.t()}
  def complete_step(params, retention_policy \\ :retain_all) do
    Handlers.CompleteStep.call(params, retention_policy)
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

    Logger.warning(fn ->
      "Detected lost run with reason #{error_type}: #{inspect(run)}"
    end)

    Repo.transaction(fn ->
      complete_run(run, %{state: :lost, error_type: error_type})

      Ecto.assoc(run, :steps)
      |> where([r], is_nil(r.exit_reason))
      |> Repo.update_all(
        set: [exit_reason: "lost", finished_at: DateTime.utc_now()]
      )
    end)
  end

  defdelegate subscribe(run), to: Events

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

  defp track_run_queue_delay({:ok, run}) do
    %Run{inserted_at: inserted_at, started_at: started_at} = run

    delay = DateTime.diff(started_at, inserted_at, :millisecond)

    :telemetry.execute(
      [:domain, :run, :queue],
      %{delay: delay},
      %{}
    )
  end

  defp track_run_queue_delay({:error, _changeset}) do
  end
end
