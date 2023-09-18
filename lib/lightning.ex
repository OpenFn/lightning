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

    def current_time() do
      DateTime.utc_now()
    end
  end

  @behaviour API

  @doc """
  Returns the current time at UTC.
  """
  @impl true
  def current_time, do: impl().current_time()

  defp impl() do
    Application.get_env(:lightning, __MODULE__, API)
  end
end
