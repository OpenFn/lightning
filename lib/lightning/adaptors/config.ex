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
  The supervisor instance public `Lightning.Adaptors` functions read
  through when called with no explicit instance. Defaults to
  `Lightning.Adaptors`, the one started in `application.ex`.

  Tests stub this to isolate reads to a private instance; see
  `Lightning.AdaptorTestHelpers.isolated_adaptors/1`.
  """
  @spec default_instance() :: atom()
  def default_instance, do: Lightning.Adaptors

  @doc """
  The active strategy module. Defaults to `Lightning.Adaptors.NPM`.
  """
  @spec strategy() :: module()
  def strategy do
    get(:strategy, @default_strategy)
  end

  @doc """
  The catalogue `source` a strategy writes under.

  `Lightning.Adaptors.Local` and `Lightning.Adaptors.NPM` are mapped
  here; any other strategy must declare a `:source` of `:npm` or
  `:local` under its own application key, or this raises rather than
  guessing at `:npm`.
  """
  @spec source_for(module()) :: :local | :npm
  def source_for(Lightning.Adaptors.Local), do: :local
  def source_for(Lightning.Adaptors.NPM), do: :npm

  def source_for(strategy) when is_atom(strategy) do
    case Keyword.fetch(strategy_opts(strategy), :source) do
      {:ok, source} when source in [:npm, :local] ->
        source

      _ ->
        raise ArgumentError,
              "strategy #{inspect(strategy)} has no catalogue source; " <>
                "map it in Lightning.Adaptors.Config.source_for/1 or set " <>
                "`config :lightning, #{inspect(strategy)}, source: :npm`"
    end
  end

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
