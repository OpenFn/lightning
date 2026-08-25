defmodule Lightning.Adaptors.Config do
  @moduledoc """
  Stateless runtime configuration for the `Lightning.Adaptors.*` subsystem.

  Every helper is a thin wrapper around `Application.get_env/3`. It is the
  single runtime source of truth for which strategy is active, how often
  the scheduler ticks, the per-call cache fetch deadline, the icon cache
  root, and per-strategy opt blocks.

  ## Application key layout

  Two-tier:

    * `:lightning, Lightning.Adaptors` — subsystem-wide knobs
      (`:strategy`, `:refresh_interval`, `:cache_timeout_ms`, `:icon_path`).
    * `:lightning, <strategy_module>` — each strategy owns its own
      Application key for its own knobs; read via `strategy_opts/1`.

  No GenServer, no ETS, no `:persistent_term` — every call is a fresh
  `Application.get_env/3`.
  """

  @parent_key Lightning.Adaptors

  @default_strategy Lightning.Adaptors.NPM
  @default_refresh_interval :timer.hours(1)
  @default_cache_timeout_ms 15_000
  @default_icon_path {:tmp, "lightning/adaptor_icons"}

  @doc """
  The active strategy module. Defaults to `Lightning.Adaptors.NPM`.
  """
  @spec strategy() :: module()
  def strategy do
    get(:strategy, @default_strategy)
  end

  @doc """
  Atom mapping of `strategy/0`: `:local` for `Lightning.Adaptors.Local`,
  `:npm` for any other strategy module.
  """
  @spec current_source() :: :local | :npm
  def current_source do
    case strategy() do
      Lightning.Adaptors.Local -> :local
      _other -> :npm
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
  Per-`Cachex.fetch` courier deadline in milliseconds. Defaults to 15s.
  """
  @spec cache_timeout_ms() :: non_neg_integer()
  def cache_timeout_ms do
    get(:cache_timeout_ms, @default_cache_timeout_ms)
  end

  @doc """
  Resolved filesystem path for the icon cache.

  Accepts either:

    * `{:tmp, suffix}` — resolved against `System.tmp_dir!/0` at call
      time so the default does not bake a container-specific tmp path
      into a compiled release.
    * a plain binary path — returned verbatim.

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
  Per-strategy keyword opts. Parameterised on the strategy module — each
  strategy is its own Application key, not nested under the parent.
  Returns `[]` when the strategy's Application key is unset.
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
