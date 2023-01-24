defmodule Lightning.Policies.Utils do
  @moduledoc """
  The Bodyguard policies utilitaries module.
  """
  def can_edit(policy, action, user) do
    case Bodyguard.permit(policy, action, user) do
      :ok -> true
      {:error, :unauthorized} -> false
    end
  end

  # def can_edit(policy, action, user, params \\ []) do
  #   case Bodyguard.permit(policy, action, user, params) do
  #     :ok -> true
  #     {:error, :unauthorized} -> false
  #   end
  # end
end
