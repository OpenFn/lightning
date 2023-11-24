defmodule Lightning do
  @moduledoc """
  Lightning keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  defmodule API do
    @moduledoc """
    Behaviour for implementing the Lightning interface.

    This behaviour is used to mock specific functions in tests.
    """
    @callback current_time() :: DateTime.t()
    @callback broadcast(binary(), {atom(), any()}) :: :ok | {:error, term()}
    @callback subscribe(binary()) :: :ok | {:error, term()}
    @callback transaction(fun_or_multi :: (... -> any()) | Ecto.Multi.t()) ::
                {:ok, any()}
                | {:error, any()}
                | {:error, Ecto.Multi.name(), any(),
                   %{required(Ecto.Multi.name()) => any()}}

    @pubsub Lightning.PubSub

    def current_time() do
      DateTime.utc_now()
    end

    def broadcast(topic, msg) do
      Phoenix.PubSub.broadcast(@pubsub, topic, msg)
    end

    def subscribe(topic) do
      Phoenix.PubSub.subscribe(@pubsub, topic)
    end

    def transaction(fun_or_multi) do
      Lightning.Repo.transaction(fun_or_multi)
    end
  end

  @behaviour API

  @doc """
  Returns the current time at UTC.
  """
  @impl true
  def current_time, do: impl().current_time()

  @impl true
  def broadcast(topic, msg), do: impl().broadcast(topic, msg)

  @impl true
  def subscribe(topic), do: impl().subscribe(topic)

  @impl true
  def transaction(fun_or_multi) do
    impl().transaction(fun_or_multi)
  end

  defp impl() do
    Application.get_env(:lightning, __MODULE__, API)
  end
end
