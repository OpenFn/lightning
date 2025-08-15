defmodule Lightning.Collaboration.Supervisor do
  @moduledoc """
  Supervisor for workflow collaboration infrastructure.

  Manages the :pg process group and a dynamic supervisor for
  workflow collaboration processes.
  """
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Start :pg first
      %{
        id: :workflow_collaboration_pg,
        start: {:pg, :start_link, [:workflow_collaboration]},
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
               name: __MODULE__.DocSupervisor
             ]
           ]},
        type: :supervisor
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def start_child(child_spec) do
    DynamicSupervisor.start_child(__MODULE__.DocSupervisor, child_spec)
  end

  def stop_child(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__.DocSupervisor, pid)
  end
end
