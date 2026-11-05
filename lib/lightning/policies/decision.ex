defmodule Lightning.Policies.Decision do
  @moduledoc """
  The order every `%Scope{}` policy decides in, so each policy supplies only its
  token grant and its rule. `project/4` decides actions on a project and
  `instance/4` actions with no project.

  The order keeps refusals from leaking. A caller without the grant hears
  `{:error, {:insufficient_scope, grant}}` before anything about the target. A
  caller the rule refuses who has no standing on the project hears
  `{:error, :no_standing}`, before the MFA check, so it learns nothing about the
  project, not even that it exists. Only a caller every other check allows
  learns `{:error, :scheduled_for_deletion}`.

  `allowed?` is computed before the call, so it reads only facts already on the
  scope and subject. A rule that needs another project's facts loads that
  project's scope through `Lightning.Scope`, outside `allowed?` and only after
  `Decision` has answered for the subject's own project. `:see_credential` does
  this for a credential's linked projects, and the sandbox rules for a
  sandbox's root project.

  A `:before_target` subject asks only about the grant, so `true` for it is not
  permission. Only `Lightning.Policies.Permissions.permit/3` passes it, so that
  `LightningWeb.Plugs.AuthorizeAction` can refuse a missing grant before
  anything is loaded.
  """
  alias Lightning.Scope

  @typedoc """
  The refusal of a caller whose token lacks `grant`, the one grant the
  refusing check needed.
  """
  @type insufficient_scope :: {:insufficient_scope, grant :: String.t()}

  @type grants :: String.t() | [String.t(), ...]

  @type answer ::
          boolean()
          | {:error,
             insufficient_scope() | :no_standing | :scheduled_for_deletion}

  @doc """
  Decides an action on a project. `grants` is one token grant or a list, any
  one of which is enough; holding none, the answer is
  `{:error, {:insufficient_scope, grant}}` naming the first. A refused caller
  with no standing on the project hears `{:error, :no_standing}`, and
  `{:error, :scheduled_for_deletion}` comes only to a caller every other check
  allows.
  """
  @spec project(Scope.t(), term(), grants(), boolean()) :: answer()
  def project(%Scope{} = scope, subject, grants, allowed?) do
    cond do
      not holds_any?(scope, grants) -> insufficient(grants)
      subject == :before_target -> true
      not Scope.describes?(scope, subject) -> false
      true -> on_project(scope, allowed?)
    end
  end

  defp on_project(scope, allowed?) do
    cond do
      not allowed? and not Scope.has_standing?(scope) -> {:error, :no_standing}
      not scope.mfa_satisfied? -> false
      not allowed? -> false
      scope.scheduled_for_deletion? -> {:error, :scheduled_for_deletion}
      true -> true
    end
  end

  @doc """
  Decides an action with no project, answering `allowed?` once one of `grants`
  is held.
  """
  @spec instance(Scope.t(), term(), grants(), boolean()) :: answer()
  def instance(%Scope{} = scope, subject, grants, allowed?) do
    cond do
      not holds_any?(scope, grants) -> insufficient(grants)
      subject == :before_target -> true
      true -> allowed?
    end
  end

  defp holds_any?(scope, grants),
    do: grants |> List.wrap() |> Enum.any?(&Scope.allows?(scope, &1))

  defp insufficient(grants),
    do: {:error, {:insufficient_scope, grants |> List.wrap() |> hd()}}
end
