defmodule Lightning.Attempts do
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

    @callback resolve(attempt :: Lightning.Attempt.t()) ::
                {:ok, Lightning.Attempt.t()}
  end

  alias Lightning.{Repo, Attempt}
  import Ecto.Query

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
  # Marks an attempt as resolved.
  # """
  @impl true
  def resolve(attempt) do
    adaptor().resolve(attempt)
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
  @spec get(Ecto.UUID.t(), [{:include, [atom() | {atom(), [atom()]}]}]) ::
          %Attempt{} | nil
  def get(id, opts \\ []) do
    preloads = opts |> Keyword.get(:include, [])

    from(a in Attempt,
      where: a.id == ^id,
      preload: ^preloads
    )
    |> Repo.one()
  end

  def get_dataclip(attempt = %Attempt{}) do
    from(d in Ecto.assoc(attempt, :dataclip),
      select: type(d.body, :string)
    )
    |> Repo.one()
  end

  @doc """
  Creates a Run for a given attempt and job.

  The Run is created with and marked as started at the current time.
  """
  @spec start_run(%{required(binary()) => Ecto.UUID.t()}) ::
          {:ok, %Lightning.Invocation.Run{}} | {:error, Ecto.Changeset.t()}
  def start_run(params) do
    import Ecto.Changeset
    import Ecto.Query

    cast(
      {%{},
       %{
         attempt_id: Ecto.UUID,
         job_id: Ecto.UUID,
         input_dataclip_id: Ecto.UUID,
         run_id: Ecto.UUID
       }},
      params,
      [:attempt_id, :job_id, :input_dataclip_id, :run_id]
    )
    |> validate_required([:attempt_id, :job_id, :input_dataclip_id, :run_id])
    |> then(&validate_run_association_exists/1)
    |> then(&insert_run/1)
  end

  defp insert_run({:error, _} = e), do: e

  defp insert_run({:ok, params}) do
    Lightning.AttemptRun.changeset(
      %Lightning.AttemptRun{},
      %{
        attempt_id: params[:attempt_id],
        run: %{
          id: params[:run_id],
          input_dataclip_id: params[:input_dataclip_id],
          started_at: DateTime.utc_now(),
          job_id: params[:job_id]
        }
      }
    )
    |> Repo.insert()
    |> case do
      {:ok, %{run: run}} ->
        {:ok, run}

      e ->
        e
    end
  end

  defp validate_run_association_exists(%{valid?: false} = changeset) do
    {:error, changeset}
  end

  defp validate_run_association_exists(changeset) do
    import Ecto.Changeset
    import Ecto.Query

    # TODO: verify that the dataclip is reachable? (in the same project?)

    params = changeset |> apply_changes()
    %{attempt_id: attempt_id, job_id: job_id} = params

    # Verify that all of the required entities exist with a single query,
    # then reduce the results into a single changeset by adding errors for
    # any columns/ids that are null.
    from(a in Attempt,
      where: a.id == ^attempt_id,
      join: w in assoc(a, :workflow),
      left_join: j in assoc(w, :jobs),
      on: j.id == ^job_id,
      select: %{attempt_id: a.id, job_id: j.id}
    )
    |> Repo.one()
    |> Enum.reduce(changeset, fn {k, v}, changeset ->
      if is_nil(v) do
        add_error(changeset, k, "does not exist")
      else
        changeset
      end
    end)
    |> apply_action(:validate)
  end

  defp adaptor do
    Lightning.Config.attempts_adaptor()
  end
end
