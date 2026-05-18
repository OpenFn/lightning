defmodule Lightning.Adaptors.Supervisor do
  @moduledoc """
  Per-instance supervisor for the `Lightning.Adaptors.*` subsystem.

  The entire subsystem boots, crashes, and is supervised as a unit
  under `:rest_for_one`. `Cachex` is the load-bearing root: if it
  crashes, the supervisor restarts it and cascades to its dependents
  (`Task.Supervisor`, plus the broadcaster/scheduler children added in
  later phases) so they re-bind to the fresh Cachex name on the way
  back up.

  No registered name, Cachex table name, PubSub topic, `Task.Supervisor`
  name, or `HighlanderPG` lock key is hardcoded. Every name is derived
  from a single `:name` opt — which is what lets the integration suite
  spin up multiple isolated instances inside one BEAM for
  `async: true` tests. Production starts exactly one instance under
  `name: Lightning.Adaptors`.

  ## Strategy injection

  The active `Lightning.Adaptors.Strategy` implementation is passed in
  explicitly via the `:strategy` opt. Tests instantiate an isolated
  supervisor with `strategy: Lightning.Adaptors.StrategyMock` — no
  `Application.put_env` mutation, no shared mutable state. The
  production caller in `lib/lightning/application.ex` passes the
  default from `Lightning.Adaptors.Config.strategy/0` (resolved from
  Application env at boot time).

  `strategy/1` and `source/1` expose the per-instance values back to
  the stateless `Lightning.Adaptors.Store` callers.
  """

  use Supervisor

  alias Lightning.Adaptors.Config

  @doc """
  Start a supervisor instance.

  Required opts:

    * `:name` — supervisor instance name (atom). Derives every child
      name via `Module.concat/2`.

  Optional opts:

    * `:strategy` — `Lightning.Adaptors.Strategy` implementation.
      Defaults to `Lightning.Adaptors.Config.strategy/0`.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    strategy = Keyword.get(opts, :strategy, Config.strategy())

    :persistent_term.put(meta_key(name), %{
      strategy: strategy,
      source: source_for(strategy)
    })

    cache = cache_name(name)
    tasks = tasks_name(name)
    source_topic = source_topic(name)
    client_topic = client_topic(name)

    children = [
      {Cachex, name: cache},
      # One-shot clear immediately after Cachex starts (§6.5a). Sits
      # under :rest_for_one so a Cachex restart also re-runs this.
      Supervisor.child_spec({Task, fn -> Cachex.clear(cache) end},
        id: Module.concat(name, CacheClear),
        restart: :transient
      ),
      {Task.Supervisor, name: tasks},
      {Lightning.Adaptors.Invalidator,
       name: invalidator_name(name), source_topic: source_topic, cache: cache},
      {Lightning.Adaptors.NodeMonitor, name: node_monitor_name(name), sup: name},
      {Lightning.Adaptors.ChannelBroadcaster,
       name: channel_broadcaster_name(name),
       source_topic: source_topic,
       client_topic: client_topic,
       sup: name},
      {Lightning.Adaptors.Scheduler,
       name: scheduler_name(name),
       sup: name,
       lock_key: lock_key(name),
       cache: cache,
       tasks: tasks,
       source_topic: source_topic}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc """
  The active strategy for the supervisor instance named `name`.

  Reads from `:persistent_term` populated at `init/1`. Raises if the
  supervisor has not been started under that name.
  """
  @spec strategy(atom()) :: module()
  def strategy(name) do
    :persistent_term.get(meta_key(name)).strategy
  end

  @doc """
  The active source (`:npm | :local`) for the supervisor instance
  named `name`.
  """
  @spec source(atom()) :: :npm | :local
  def source(name) do
    :persistent_term.get(meta_key(name)).source
  end

  @doc """
  Best-effort cleanup of the per-instance `:persistent_term` entry.

  Not called automatically — `:persistent_term.erase/1` triggers a
  global GC and is expensive enough that we leave it to deliberate
  teardown paths (e.g. release shutdown).
  """
  @spec forget(atom()) :: boolean()
  def forget(name) do
    :persistent_term.erase(meta_key(name))
  end

  @doc "Cachex table name for the supervisor named `name`."
  @spec cache_name(atom()) :: atom()
  def cache_name(name), do: Module.concat(name, Cache)

  @doc "`Task.Supervisor` name for the supervisor named `name`."
  @spec tasks_name(atom()) :: atom()
  def tasks_name(name), do: Module.concat(name, Tasks)

  @doc "`Invalidator` GenServer name for the supervisor named `name`."
  @spec invalidator_name(atom()) :: atom()
  def invalidator_name(name), do: Module.concat(name, Invalidator)

  @doc "`ChannelBroadcaster` GenServer name for the supervisor named `name`."
  @spec channel_broadcaster_name(atom()) :: atom()
  def channel_broadcaster_name(name),
    do: Module.concat(name, ChannelBroadcaster)

  @doc "`NodeMonitor` GenServer name for the supervisor named `name`."
  @spec node_monitor_name(atom()) :: atom()
  def node_monitor_name(name), do: Module.concat(name, NodeMonitor)

  @doc "`Scheduler` GenServer name for the supervisor named `name`."
  @spec scheduler_name(atom()) :: atom()
  def scheduler_name(name), do: Module.concat(name, Scheduler)

  @doc """
  Source-side PubSub topic for the supervisor named `name`.

  Used by the `Scheduler` and `Invalidator` to broadcast and receive
  `{:changed, name, source}` style events.
  """
  @spec source_topic(atom()) :: String.t()
  def source_topic(name), do: "adaptors:#{inspect(name)}"

  @doc """
  Client-side PubSub topic for the supervisor named `name`.

  The `ChannelBroadcaster` republishes throttled updates from
  `source_topic/1` onto this topic for `WorkflowChannel` subscribers.
  """
  @spec client_topic(atom()) :: String.t()
  def client_topic(name), do: "adaptors:client_update:#{inspect(name)}"

  @doc """
  Postgres advisory-lock key for the supervisor named `name`.

  Derived as `:erlang.phash2({:adaptors, name})` so each supervisor
  instance leases its `HighlanderPG`-wrapped `Scheduler` against a
  distinct `int4` key — two concurrent test supervisors with different
  names cannot collide on advisory locks.
  """
  @spec lock_key(atom()) :: non_neg_integer()
  def lock_key(name), do: :erlang.phash2({:adaptors, name})

  defp meta_key(name), do: {__MODULE__, name}

  defp source_for(Lightning.Adaptors.Local), do: :local
  defp source_for(_other), do: :npm
end
