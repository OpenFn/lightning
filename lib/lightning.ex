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
    @behaviour Lightning
    @pubsub Lightning.PubSub

    @impl true
    def current_time do
      DateTime.utc_now()
    end

    @impl true
    def broadcast(topic, msg) do
      Phoenix.PubSub.broadcast(@pubsub, topic, msg)
    end

    def broadcast_from(from, topic, msg) do
      Phoenix.PubSub.broadcast_from(@pubsub, from, topic, msg)
    end

    @impl true
    def local_broadcast(topic, msg) do
      Phoenix.PubSub.local_broadcast(@pubsub, topic, msg)
    end

    @impl true
    def subscribe(topic) do
      Phoenix.PubSub.subscribe(@pubsub, topic)
    end

    @impl true
    def release do
      Application.get_env(:lightning, :release,
        label: nil,
        commit: nil,
        image_tag: nil,
        branch: nil
      )
      |> Keyword.merge(vsn: Application.spec(:lightning, :vsn))
      |> Map.new()
    end
  end

  @type release_info() :: %{
          label: String.t() | nil,
          commit: String.t() | nil,
          image_tag: String.t() | nil,
          branch: String.t() | nil,
          vsn: String.t()
        }

  # credo:disable-for-next-line
  @callback current_time() :: DateTime.t()
  @callback broadcast(binary(), {atom(), any()}) :: :ok | {:error, term()}
  @callback local_broadcast(binary(), {atom(), any()}) :: :ok | {:error, term()}
  @callback subscribe(binary()) :: :ok | {:error, term()}
  @callback release() :: release_info()

  @doc """
  Returns the current time at UTC.
  """
  def current_time, do: impl().current_time()

  def broadcast(topic, msg), do: impl().broadcast(topic, msg)

  def broadcast_from(from, topic, msg),
    do: impl().broadcast_from(from, topic, msg)

  def local_broadcast(topic, msg), do: impl().local_broadcast(topic, msg)

  def subscribe(topic), do: impl().subscribe(topic)

  @spec release() :: release_info()
  def release, do: impl().release()

  defp impl do
    Application.get_env(:lightning, __MODULE__, API)
  end
end
