defmodule Lightning.Collaboration.Supervisor do
  @moduledoc """
  Supervisor for workflow collaboration infrastructure.

  Manages the collaboration Registry, `:pg` process group, and a dynamic
  supervisor for workflow collaboration processes.

  The Registry must be started first to ensure processes can register
  themselves during startup.

  Accepts an optional `:name` option so that tests can run isolated
  supervision trees side-by-side. The default name (`__MODULE__`) is what
  production uses; from there the Registry name, DynamicSupervisor name and
  `:pg` scope are derived via `Lightning.Collaboration.Topology`.
  """
  use Supervisor

  alias Lightning.Collaboration.Topology

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, name, name: name)
  end

  @impl true
  def init(name) do
    registry = Topology.registry(name)
    doc_sup = Topology.doc_supervisor(name)
    pg_scope = Topology.pg_scope(name)

    children = [
      # Start Registry first - processes depend on it for registration
      %{
        id: {:registry, registry},
        start: {Registry, :start_link, [[keys: :unique, name: registry]]},
        type: :supervisor
      },
      # Start :pg for cluster-wide SharedDoc coordination
      %{
        id: {:pg, pg_scope},
        start: {:pg, :start_link, [pg_scope]},
        type: :worker
      },
      # Start the dynamic supervisor for collaboration processes
      %{
        id: {:doc_sup, doc_sup},
        start:
          {DynamicSupervisor, :start_link,
           [[strategy: :one_for_one, name: doc_sup]]},
        type: :supervisor
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Starts a child of the active document supervisor.

  Defaults to the production supervisor; tests can pass an explicit `base`
  atom to start the child in their isolated tree.
  """
  def start_child(base \\ __MODULE__, child_spec) do
    DynamicSupervisor.start_child(Topology.doc_supervisor(base), child_spec)
  end

  @doc """
  Terminates a child of the active document supervisor.
  """
  def terminate_child(base \\ __MODULE__, pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(Topology.doc_supervisor(base), pid)
  end
end
