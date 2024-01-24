defmodule Lightning.Attempts do
  import Ecto.Query

  alias Lightning.Attempt
  alias Lightning.Attempts.Events
  alias Lightning.Attempts.Handlers
  alias Lightning.Invocation.LogLine
  alias Lightning.Repo
  require Logger

  defmodule Adaptor do
    @moduledoc """
    Behaviour for implementing an adaptor for the Lightning.Attempts module.
    """

    @callback enqueue(
                attempt ::
                  Lightning.Attempt.t() | Ecto.Changeset.t(Lightning.Attempt.t())
              ) ::
                {:ok, Lightning.Attempt.t()}
                | {:error, Ecto.Changeset.t(Lightning.Attempt.t())}

    @callback claim(demand :: non_neg_integer()) ::
                {:ok, [Lightning.Attempt.t()]}

    @callback dequeue(attempt :: Lightning.Attempt.t()) ::
                {:ok, Lightning.Attempt.t()}
  end

  # credo:disable-for-next-line
  @behaviour Adaptor

  @doc """
  Enqueue an attempt to be processed.
  """
  @impl true
  def enqueue(attempt) do
    adaptor().enqueue(attempt)
  end

  # @doc """
  # Claim an available attempt.
  #
  # The `demand` parameter is used to request more than a since attempt,
  # all implementation should default to 1.
  # """
  @impl true
  def claim(demand \\ 1) do
    adaptor().claim(demand)
  end

  # @doc """
  # Removes an attempt from the queue.
  # """
  @impl true
  def dequeue(attempt) do
    adaptor().dequeue(attempt)
  end

  @doc """
  Get an Attempt by id.

  Optionally preload associations by passing a list of atoms to `:include`.

      Lightning.Attempts.get(id, include: [:workflow])
  """
  @spec get(Ecto.UUID.t(), [{:include, term()}]) ::
          Attempt.t() | nil
  def get(id, opts \\ []) do
    preloads = opts |> Keyword.get(:include, [])

    from(a in Attempt,
      where: a.id == ^id,
      preload: ^preloads
    )
    |> Repo.one()
  end

  @doc """
  Returns only the dataclip body as a string
  """
  def get_dataclip_body(%Attempt{} = attempt) do
    from(d in Ecto.assoc(attempt, :dataclip),
      select: type(d.body, :string)
    )
    |> Repo.one()
  end

  @doc """
  Returns only the dataclip request as a string
  """
  def get_dataclip_request(%Attempt{} = attempt) do
    from(d in Ecto.assoc(attempt, :dataclip),
      select: type(d.request, :string)
    )
    |> Repo.one()
  end

  @doc """
  Returns an Attempts dataclip formatted for use as state.

  Only `http_request` dataclips are changed, their `body` is nested inside a
  `"data"` key and `request` data is added as a `"request"` key.

  See LightingWeb.AttemptChannel.handle_in("fetch:dataclip", _, _)
  for more details.
  """
  @spec get_input(Attempt.t()) :: String.t() | nil
  def get_input(%Attempt{} = attempt) do
    from(d in Ecto.assoc(attempt, :dataclip),
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
  Clears the body and request fields of the dataclip associated with the given attempt.
  """
  @spec wipe_dataclip_body(Attempt.t()) :: :ok
  def wipe_dataclip_body(%Attempt{} = attempt) do
    query =
      from(d in Ecto.assoc(attempt, :dataclip),
        update: [set: [request: nil, body: nil, wiped_at: ^DateTime.utc_now()]]
      )

    {1, _rows} = Repo.update_all(query, [])
    :ok
  end

  def get_credential(%Attempt{} = attempt, id) do
    from(c in Ecto.assoc(attempt, [:workflow, :jobs, :credential]),
      where: c.id == ^id
    )
    |> Repo.one()
  end

  def start_attempt(%Attempt{} = attempt) do
    Attempt.start(attempt)
    |> update_attempt()
    |> tap(&track_attempt_queue_delay/1)
  end

  @spec complete_attempt(Attempt.t(), %{optional(any()) => any()}) ::
          {:ok, Attempt.t()} | {:error, Ecto.Changeset.t(Attempt.t())}
  def complete_attempt(attempt, params) do
    Attempt.complete(attempt, params)
    |> case do
      %{valid?: false} = changeset ->
        {:error, changeset}

      changeset ->
        changeset |> update_attempt()
    end
  end

  @spec update_attempt(Ecto.Changeset.t(Attempt.t())) ::
          {:ok, Attempt.t()} | {:error, Ecto.Changeset.t(Attempt.t())}
  def update_attempt(%Ecto.Changeset{data: %Attempt{}} = changeset) do
    attempt_id = Ecto.Changeset.get_field(changeset, :id)

    attempt_query =
      from(a in Attempt,
        where: a.id == ^attempt_id,
        lock: "FOR UPDATE"
      )

    update_query =
      Attempt
      |> with_cte("subset", as: ^attempt_query)
      |> join(:inner, [a], s in fragment(~s("subset")), on: a.id == s.id)
      |> select([a, _], a)

    case update_attempts(update_query, changeset) do
      {:ok, %{attempts: {1, [attempt]}}} ->
        {:ok, attempt}

      {:error, _op, changeset, _changes} ->
        {:error, changeset}
    end
  end

  def update_attempts(update_query, updates) do
    updates =
      case updates do
        %Ecto.Changeset{changes: changes} -> [set: changes |> Enum.into([])]
        updates when is_list(updates) -> updates
      end

    Ecto.Multi.new()
    |> Ecto.Multi.update_all(:attempts, update_query, updates)
    |> Ecto.Multi.run(:post, fn _, %{attempts: {_, attempts}} ->
      Enum.each(attempts, fn attempt ->
        {:ok, _} = Lightning.WorkOrders.update_state(attempt)
      end)

      {:ok, nil}
    end)
    |> Repo.transaction()
    |> tap(fn result ->
      with {:ok, %{attempts: {_n, attempts}}} <- result do
        Enum.each(attempts, &Events.attempt_updated/1)
      end
    end)
  end

  def append_attempt_log(attempt, params, scrubber \\ nil) do
    LogLine.new(attempt, params, scrubber)
    |> Ecto.Changeset.validate_change(:step_id, fn _, step_id ->
      if is_nil(step_id) do
        []
      else
        where(Lightning.AttemptStep, step_id: ^step_id, attempt_id: ^attempt.id)
        |> Repo.exists?()
        |> if do
          []
        else
          [{:step_id, "must be associated with the attempt"}]
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
  Creates a Step for a given attempt and job.

  The Step is created and marked as started at the current time.
  """
  @spec start_step(map()) ::
          {:ok, Lightning.Invocation.Step.t()} | {:error, Ecto.Changeset.t()}
  def start_step(params) do
    Handlers.StartStep.call(params)
  end

  @spec complete_step(map()) ::
          {:ok, Lightning.Invocation.Step.t()} | {:error, Ecto.Changeset.t()}
  def complete_step(params) do
    Handlers.CompleteStep.call(params)
  end

  @spec mark_attempt_lost(Lightning.Attempt.t()) ::
          {:ok, any()} | {:error, any()}
  def mark_attempt_lost(%Attempt{} = attempt) do
    error_type =
      case attempt.state do
        :claimed -> "LostAfterClaim"
        :started -> "LostAfterStart"
        _other -> "UnknownReason"
      end

    Logger.warning(fn ->
      "Detected lost attempt with reason #{error_type}: #{inspect(attempt)}"
    end)

    Repo.transaction(fn ->
      complete_attempt(attempt, %{state: :lost, error_type: error_type})

      Ecto.assoc(attempt, :steps)
      |> where([r], is_nil(r.exit_reason))
      |> Repo.update_all(
        set: [exit_reason: "lost", finished_at: DateTime.utc_now()]
      )
    end)
  end

  defdelegate subscribe(attempt), to: Events

  def get_project_id_for_attempt(attempt) do
    Ecto.assoc(attempt, [:work_order, :workflow, :project])
    |> select([p], p.id)
    |> Repo.one()
  end

  def get_log_lines(attempt, order \\ :asc) do
    Ecto.assoc(attempt, :log_lines)
    |> order_by([{^order, :timestamp}])
    |> Repo.stream()
  end

  defp adaptor do
    Lightning.Config.attempts_adaptor()
  end

  defp track_attempt_queue_delay({:ok, attempt}) do
    %Attempt{inserted_at: inserted_at, started_at: started_at} = attempt

    delay = DateTime.diff(started_at, inserted_at, :millisecond)

    :telemetry.execute(
      [:domain, :attempt, :queue],
      %{delay: delay},
      %{}
    )
  end

  defp track_attempt_queue_delay({:error, _changeset}) do
  end
end
