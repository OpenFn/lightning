defmodule Lightning.Policies.Permissions do
  @moduledoc """
  The Bodyguard permissions module.
  """
  def can(policy, action, user, params \\ []) do
    case Bodyguard.permit(policy, action, user, params) do
      :ok -> true
      {:error, :unauthorized} -> false
    end
  end
end
