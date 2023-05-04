defmodule Lightning.Policies.Permissions do
  @moduledoc """
  The Bodyguard permissions module.
  """
  def can(policy, action, user, params \\ []) do
    Bodyguard.permit(policy, action, user, params)
  end

  def can?(policy, action, user, params \\ []) do
    case can(policy, action, user, params) do
      :ok -> true
      {:error, :unauthorized} -> false
    end
  end
end
