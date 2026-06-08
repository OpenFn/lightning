defmodule Lightning.Collaboration.Instance do
  @moduledoc """
  Names the three pieces of collaboration infrastructure that a single
  `Lightning.Collaboration.Supervisor` owns: its `Registry`, its
  `DynamicSupervisor`, and its `:pg` scope.

  A plain value (no process), threaded from the public API down into child
  specs so the whole tree can be addressed under a chosen base name. Production
  uses `default/0`, which pins the three names to the application-wide
  singletons started in `application.ex`. Tests can `derive/1` a fresh, isolated
  set from a unique base, letting independent supervisor instances coexist.
  """

  @enforce_keys [:registry, :dynamic_supervisor, :pg_scope]
  defstruct [:registry, :dynamic_supervisor, :pg_scope]

  @type t :: %__MODULE__{
          registry: atom(),
          dynamic_supervisor: atom(),
          pg_scope: atom()
        }

  @doc """
  The production instance: the application-wide singletons.

  These are the literal names started by the collaboration supervision tree in
  `application.ex`, so every defaulted public call resolves to the same global
  infrastructure it always has.
  """
  @spec default() :: t()
  def default do
    %__MODULE__{
      registry: Lightning.Collaboration.Registry,
      dynamic_supervisor: Lightning.Collaboration.Supervisor.DocSupervisor,
      pg_scope: :workflow_collaboration
    }
  end

  @doc """
  Derive an instance from a base name.

  Passing `Lightning.Collaboration.Supervisor` (the production base) yields the
  exact `default/0` names. Any other base produces a distinct, isolated set,
  which is how tests run independent supervisor instances side by side.
  """
  @spec derive(atom()) :: t()
  def derive(Lightning.Collaboration.Supervisor), do: default()

  def derive(base) when is_atom(base) do
    %__MODULE__{
      registry: Module.concat(base, Registry),
      dynamic_supervisor: Module.concat(base, DocSupervisor),
      pg_scope: base
    }
  end
end
