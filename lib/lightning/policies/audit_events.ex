defmodule Lightning.Policies.AuditEvents do
  @moduledoc """
  The Bodyguard Policy module for reading the instance's audit trail.

  Audit events cover every project, so reading them is for a superuser, on
  any of their tokens, or the service account with `audit:read`. It is a fact
  about the caller alone, so the check made before any target decides it.
  """
  @behaviour Bodyguard.Policy

  alias Lightning.Policies.Decision
  alias Lightning.Scope

  @type actions :: :read_audit_events

  @spec authorize(actions(), Scope.t(), term()) :: Decision.answer()
  def authorize(:read_audit_events, %Scope{} = scope, _subject),
    do: Decision.instance(scope, nil, "audit:read", Scope.instance_wide?(scope))
end
