defmodule Lightning.AuthProviders.CacheWarmer do
  @moduledoc """
  Dummy warmer which caches database rows every 30s.
  """
  use Cachex.Warmer
  alias Lightning.AuthProviders

  require Logger

  # Suppress dialyzer warning for Cachex.Warmer.init/1
  # This has been fixed upstream but not released on hex.
  # https://github.com/whitfin/cachex/issues/276
  @dialyzer {:nowarn_function, init: 1}

  # `GithubHandler.build/0` and `GoogleHandler.build/0` read their client
  # credentials through `Lightning.Config.*_oauth/1`, which dispatches
  # dynamically through an extension module. Dialyzer can't see that the
  # binary branch is reachable, so it concludes `build/0` only ever returns
  # `{:error, :not_configured}` and flags the `{:ok, _}` pattern here as
  # unreachable. The runtime behaviour is fine.
  @dialyzer {:nowarn_function, execute: 1}

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
        error ->
          Logger.warning(
            "AuthProviders.CacheWarmer failed to warm the DB-backed provider: " <>
              Exception.message(error)
          )

          []
      end

    github_entries =
      case Lightning.AuthProviders.GithubHandler.build() do
        {:ok, handler} -> [{handler.name, handler}]
        _ -> []
      end

    google_entries =
      case Lightning.AuthProviders.GoogleHandler.build() do
        {:ok, handler} -> [{handler.name, handler}]
        _ -> []
      end

    case db_entries ++ github_entries ++ google_entries do
      [] -> :ignore
      entries -> {:ok, entries}
    end
  end
end
