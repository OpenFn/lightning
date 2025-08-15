defmodule Lightning.SentryBehaviour do
  @moduledoc """
  Behaviour for our Sentry client.
  """
  @callback capture_message(String.t(), keyword()) :: any()
  @callback capture_exception(Exception.t(), keyword()) :: any()
end

defmodule Lightning.Sentry do
  @moduledoc """
  Runtime proxy around the configured Sentry implementation.
  """
  @behaviour Lightning.SentryBehaviour

  defp impl, do: Lightning.Config.sentry()

  @impl true
  def capture_message(msg, opts), do: impl().capture_message(msg, opts)

  @impl true
  def capture_exception(err, opts), do: impl().capture_exception(err, opts)
end
