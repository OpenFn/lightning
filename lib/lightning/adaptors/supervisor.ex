defmodule Lightning.Adaptors.Supervisor do
  @moduledoc """
  Per-instance supervisor for the `Lightning.Adaptors.*` subsystem.

  The entire subsystem boots, crashes, and is supervised as a unit
  under `:rest_for_one`. `Cachex` is the load-bearing root: if it
  crashes, the supervisor restarts it and cascades to its dependents
  (`Task.Supervisor`, `Invalidator`, `ChannelBroadcaster`, `NodeMonitor`,
  `Scheduler`) so they re-bind to the fresh Cachex name on the way back
  up.

  No registered name, Cachex table name, PubSub topic, `Task.Supervisor`
  name, or `HighlanderPG` lock key is hardcoded. Every name is derived
  from a single `:name` opt — which is what lets the integration suite
  spin up multiple isolated instances inside one BEAM for
  `async: true` tests. Production starts exactly one instance under
  `name: Lightning.Adaptors`.

  Strategy is **not** an opt — it is read at runtime via
  `Lightning.Adaptors.Config.strategy/0`.
  """

  use Supervisor

  @doc """
  Start a supervisor instance.

  The `:name` opt is mandatory; absence raises `KeyError`.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
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
       name: invalidator_name(name), cache: cache, source_topic: source_topic},
      {Lightning.Adaptors.ChannelBroadcaster,
       name: channel_broadcaster_name(name),
       source_topic: source_topic,
       client_topic: client_topic},
      {Lightning.Adaptors.NodeMonitor, name: node_monitor_name(name), sup: name},
      {HighlanderPG,
       {Lightning.Adaptors.Scheduler,
        name: scheduler_name(name),
        lock_key: lock_key(name),
        cache: cache,
        tasks: tasks,
        source_topic: source_topic}}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
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
end
