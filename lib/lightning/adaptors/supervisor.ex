defmodule Lightning.Adaptors.Supervisor do
  @moduledoc """
  Supervises one instance of the adaptors subsystem: the cache, task
  supervisor, invalidator, node monitor, channel broadcaster and the
  `HighlanderPG`-wrapped scheduler.

  Every child, cache, topic and lock name derives from the `:name` opt,
  so several instances can run in one BEAM. Production starts one under
  `name: Lightning.Adaptors`. The scheduler is a cluster singleton
  registered under `global_scheduler_name/1`.
  """

  use Supervisor

  alias Lightning.Adaptors.Config

  @doc """
  Starts a supervisor instance.

  Options:

    * `:name` - required; every child name derives from it
    * `:strategy` - `Lightning.Adaptors.Strategy` implementation,
      defaulting to `Lightning.Adaptors.Config.strategy/0`
    * `:lock_key` - `HighlanderPG` advisory-lock key, defaulting to
      `lock_key(name)`
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
    lock_key = Keyword.get(opts, :lock_key, lock_key(name))

    :persistent_term.put(meta_key(name), %{
      strategy: strategy,
      source: Config.source_for(strategy)
    })

    cache = cache_name(name)
    tasks = tasks_name(name)
    source_topic = source_topic(name)
    client_topic = client_topic(name)

    scheduler_child =
      %{
        id: Lightning.Adaptors.Scheduler,
        start:
          {Lightning.Adaptors.Scheduler, :start_link,
           [
             [
               name: global_scheduler_name(name),
               sup: name,
               lock_key: lock_key,
               cache: cache,
               tasks: tasks,
               source_topic: source_topic
             ]
           ]}
      }

    children = [
      {Cachex, name: cache},
      {Task.Supervisor, name: tasks},
      {Lightning.Adaptors.Invalidator,
       name: invalidator_name(name), source_topic: source_topic, cache: cache},
      {Lightning.Adaptors.NodeMonitor, name: node_monitor_name(name), sup: name},
      {Lightning.Adaptors.ChannelBroadcaster,
       name: channel_broadcaster_name(name),
       source_topic: source_topic,
       client_topic: client_topic},
      Supervisor.child_spec(
        {HighlanderPG,
         child: scheduler_child,
         repo: Lightning.Repo,
         name: lock_key,
         sup_name: highlander_name(name)},
        id: highlander_name(name)
      )
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Returns the strategy of the supervisor named `name`. Raises if no
  supervisor has started under that name.
  """
  @spec strategy(atom()) :: module()
  def strategy(name) do
    :persistent_term.get(meta_key(name)).strategy
  end

  @doc """
  Returns the source (`:npm | :local`) of the supervisor named `name`.
  """
  @spec source(atom()) :: :npm | :local
  def source(name) do
    :persistent_term.get(meta_key(name)).source
  end

  @doc """
  Erases the instance's `:persistent_term` entry. Not called
  automatically, since `:persistent_term.erase/1` triggers a global GC.
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

  @doc """
  Atom form of the Scheduler name for the supervisor named `name`. The
  process itself registers under `global_scheduler_name/1`.
  """
  @spec scheduler_name(atom()) :: atom()
  def scheduler_name(name), do: Module.concat(name, Scheduler)

  @doc """
  `:global` Scheduler name for the supervisor named `name`; pass it to
  `GenServer.call/3` directly.
  """
  @spec global_scheduler_name(atom()) :: {:global, atom()}
  def global_scheduler_name(name), do: {:global, scheduler_name(name)}

  @doc "`HighlanderPG` supervisor name for the supervisor named `name`."
  @spec highlander_name(atom()) :: atom()
  def highlander_name(name), do: Module.concat(name, HighlanderPG)

  @doc """
  PubSub topic carrying `{:changed, name, source}` events for the
  supervisor named `name`.
  """
  @spec source_topic(atom()) :: String.t()
  def source_topic(name), do: "adaptors:#{inspect(name)}"

  @doc """
  PubSub topic carrying debounced `adaptors_updated` events for the
  supervisor named `name`; see `Lightning.Adaptors.subscribe_to_updates/1`.
  """
  @spec client_topic(atom()) :: String.t()
  def client_topic(name), do: "adaptors:client_update:#{inspect(name)}"

  @doc """
  Postgres advisory-lock key for the supervisor named `name`.
  """
  @spec lock_key(atom()) :: non_neg_integer()
  def lock_key(name), do: :erlang.phash2({:adaptors, name})

  defp meta_key(name), do: {__MODULE__, name}
end
