defmodule Lightning.Collaboration.Supervisor do
  @moduledoc """
  Supervisor for workflow collaboration infrastructure.

  Manages the collaboration Registry, :pg process group, and a dynamic
  supervisor for workflow collaboration processes.

  The Registry must be started first to ensure processes can register
  themselves during startup.
  """
  use Supervisor

  alias Lightning.Collaboration.Instance

  @doc """
  Starts the collaboration supervisor.

  The registered name is taken from the `:name` option (defaulting to
  `__MODULE__`). That name is the base from which `init/1` derives the
  instance's Registry, `:pg` scope, and DynamicSupervisor names, so a test can
  start a fully isolated tree by passing a unique `:name`.
  """
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, Keyword.put(opts, :name, name), name: name)
  end

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)
    instance = Instance.derive(name)

    children = [
      # Start Registry first - processes depend on it for registration
      {Lightning.Collaboration.Registry, name: instance.registry},
      # Start :pg for cluster-wide SharedDoc coordination
      %{
        id: :collaboration_pg,
        start: {:pg, :start_link, [instance.pg_scope]},
        type: :worker
      },
      # Start the dynamic supervisor for collaboration processes
      %{
        id: :collaboration_dynamic_supervisor,
        start:
          {DynamicSupervisor, :start_link,
           [
             [
               strategy: :one_for_one,
               name: instance.dynamic_supervisor
             ]
           ]},
        type: :supervisor
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def start_child(dynamic_supervisor \\ __MODULE__.DocSupervisor, child_spec) do
    DynamicSupervisor.start_child(dynamic_supervisor, child_spec)
  end

  def terminate_child(dynamic_supervisor \\ __MODULE__.DocSupervisor, pid)
      when is_pid(pid) do
    DynamicSupervisor.terminate_child(dynamic_supervisor, pid)
  end
end
