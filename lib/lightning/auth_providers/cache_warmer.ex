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
    db_entries =
      try do
        with %AuthProviders.AuthConfig{name: name} = config <-
               AuthProviders.get_existing() || :not_found,
             {:ok, handler} <- AuthProviders.Handler.from_model(config) do
          [{name, handler}]
        else
          _ -> []
        end
      rescue
        _ -> []
      end

    github_entries =
      case Lightning.AuthProviders.GithubHandler.build() do
        {:ok, handler} -> [{handler.name, handler}]
        _ -> []
      end

    case db_entries ++ github_entries do
      [] -> :ignore
      entries -> {:ok, entries}
    end
  end
end
