defmodule Lightning.AuthProviders.CacheWarmer do
  @moduledoc """
  Dummy warmer which caches database rows every 30s.
  """
  use Cachex.Warmer
  alias Lightning.AuthProviders

  # Suppress dialyzer warning for Cachex.Warmer.init/1
  # This has been fixed upstream but not released on hex.
  # https://github.com/whitfin/cachex/issues/276
  @dialyzer {:nowarn_function, init: 1}

  @doc """
  Returns the interval for this warmer.
  """
  def interval,
    do: :timer.minutes(30)

  @doc """
  Executes this cache warmer with a connection.
  """
  def execute(_state) do
    with %AuthProviders.AuthConfig{name: name} = config <-
           AuthProviders.get_existing() || :ignore,
         {:ok, handler} <- AuthProviders.Handler.from_model(config) do
      {:ok, [{name, handler}]}
    else
      _error -> :ignore
    end
  end
end
