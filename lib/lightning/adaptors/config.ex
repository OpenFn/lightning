defmodule Lightning.Adaptors.Config do
  @moduledoc """
  Runtime configuration for the adaptors subsystem, read from
  `config :lightning, Lightning.Adaptors` on every call.

  Strategy-specific options live under the strategy module's own key;
  see `strategy_opts/1`.
  """

  @parent_key Lightning.Adaptors

  @default_strategy Lightning.Adaptors.NPM
  @default_refresh_interval :timer.hours(1)
  @default_cache_timeout_ms 15_000
  @default_icon_path {:tmp, "lightning/adaptor_icons"}
  @default_first_load_timeout :timer.seconds(60)

  @doc """
  The active strategy module. Defaults to `Lightning.Adaptors.NPM`.
  """
  @spec strategy() :: module()
  def strategy do
    get(:strategy, @default_strategy)
  end

  @doc """
  Returns `:local` for `Lightning.Adaptors.Local` and `:npm` for any
  other strategy.
  """
  @spec source_for(module()) :: :local | :npm
  def source_for(Lightning.Adaptors.Local), do: :local
  def source_for(_strategy), do: :npm

  @doc """
  Scheduler tick interval in milliseconds. Defaults to one hour.
  """
  @spec refresh_interval() :: non_neg_integer()
  def refresh_interval do
    get(:refresh_interval, @default_refresh_interval)
  end

  @doc """
  How long a read waits for a cache fill, in milliseconds. Defaults to
  15 seconds.
  """
  @spec cache_timeout_ms() :: non_neg_integer()
  def cache_timeout_ms do
    get(:cache_timeout_ms, @default_cache_timeout_ms)
  end

  @doc """
  Filesystem path of the icon cache. A `{:tmp, suffix}` value is joined
  to `System.tmp_dir!/0` at call time; a binary is returned as is.
  Defaults to `{:tmp, "lightning/adaptor_icons"}`.
  """
  @spec icon_path() :: Path.t()
  def icon_path do
    case get(:icon_path, @default_icon_path) do
      {:tmp, suffix} -> Path.join(System.tmp_dir!(), suffix)
      path when is_binary(path) -> path
    end
  end

  @doc """
  Bound, in milliseconds, on how long `Lightning.Adaptors.ensure_loaded/1`
  and `Lightning.Adaptors.fetch_adaptor/2` block waiting for the
  catalogue's first load. Defaults to 60 seconds.
  """
  @spec first_load_timeout() :: non_neg_integer()
  def first_load_timeout do
    get(:first_load_timeout, @default_first_load_timeout)
  end

  @doc """
  Options configured under the strategy module's own application key, or
  `[]` when unset.
  """
  @spec strategy_opts(module()) :: keyword()
  def strategy_opts(strategy_mod) when is_atom(strategy_mod) do
    Application.get_env(:lightning, strategy_mod, [])
  end

  @spec get(atom(), term()) :: term()
  defp get(key, default) do
    :lightning
    |> Application.get_env(@parent_key, [])
    |> Keyword.get(key, default)
  end
end
