defmodule Lightning.Policies.Decision do
  @moduledoc """
  The order a policy decides in, so each policy supplies only its grant and
  its rule.

  The order is what keeps refusals from leaking: a caller without the grant
  hears `{:error, {:insufficient_scope, grant}}` before anything about the
  target, and
  only a caller the rule allows learns `{:error, :scheduled_for_deletion}`.

  `allowed?` is computed before the call, so a rule must read only facts on
  the scope and subject, never load anything.

  A `:before_target` subject asks only about the grant, so `true` for it is not
  permission; only `Lightning.Policies.Permissions.permit/3` passes it.
  """
  alias Lightning.Scope

  @typedoc """
  The refusal of a caller whose token lacks `grant`, the one grant the
  refusing check needed (error-format spec §9.2).
  """
  @type insufficient_scope :: {:insufficient_scope, grant :: String.t()}

  @type answer ::
          boolean() | {:error, insufficient_scope() | :scheduled_for_deletion}

  @doc """
  Decides an action on a project. Without the grant the answer is
  `{:error, {:insufficient_scope, grant}}`, and `{:error, :scheduled_for_deletion}`
  comes only to a caller every other check allows.
  """
  @spec project(Scope.t(), term(), String.t(), boolean()) :: answer()
  def project(%Scope{} = scope, subject, grant, allowed?) do
    cond do
      not Scope.allows?(scope, grant) -> {:error, {:insufficient_scope, grant}}
      subject == :before_target -> true
      not Scope.describes?(scope, subject) -> false
      not scope.mfa_satisfied? -> false
      not allowed? -> false
      scope.scheduled_for_deletion? -> {:error, :scheduled_for_deletion}
      true -> true
    end
  end

  @doc """
  Decides an action with no project, answering `allowed?` once the grant is
  held.
  """
  @spec instance(Scope.t(), term(), String.t(), boolean()) :: answer()
  def instance(%Scope{} = scope, subject, grant, allowed?) do
    cond do
      not Scope.allows?(scope, grant) -> {:error, {:insufficient_scope, grant}}
      subject == :before_target -> true
      true -> allowed?
    end
  end
end
