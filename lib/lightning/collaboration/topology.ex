defmodule Lightning.Collaboration.Topology do
  @moduledoc """
  Resolves the active collaboration supervisor's base name, from which the
  Registry, DynamicSupervisor, and `:pg` scope names are derived.

  In production exactly one supervisor runs under the default base name.
  In tests, `Lightning.CollaborationCase` overrides the base for the
  duration of each test via `Application.put_env/3`.
  """

  @default_base Lightning.Collaboration.Supervisor

  @doc """
  Returns the base name of the active collaboration supervisor.

  Reads from application config so that every process in the VM — including
  GenServer children spawned under the production supervisor during tests —
  sees the same value without any Mox stub plumbing.
  """
  def base do
    Application.get_env(:lightning, __MODULE__, @default_base)
  end

  @doc """
  Returns the Registry name derived from the active base.
  """
  def registry, do: registry(base())
  def registry(base), do: Module.concat(base, Registry)

  @doc """
  Returns the dynamic supervisor name derived from the active base.
  """
  def doc_supervisor, do: doc_supervisor(base())
  def doc_supervisor(base), do: Module.concat(base, DocSupervisor)

  @doc """
  Returns the `:pg` scope atom derived from the active base.

  The default base preserves the historical `:workflow_collaboration` scope so
  that production deployments keep their existing process group name.
  """
  def pg_scope, do: pg_scope(base())
  def pg_scope(@default_base), do: :workflow_collaboration
  def pg_scope(other), do: :"#{other}_pg"

  @doc """
  Returns a `:via` tuple suitable for naming a process registered in the
  active Registry.
  """
  def via(key), do: {:via, Registry, {registry(), key}}
end
