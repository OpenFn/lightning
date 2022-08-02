defmodule Lightning.Accounts.PolicyTest do
  use Lightning.DataCase, async: true

  alias Lightning.Accounts.User

  describe "Accounts policy" do
    test "regular users can't access user management page" do
      assert {:error, :unauthorized} =
               Bodyguard.permit(Lightning.Accounts.Policy, :index, %User{
                 role: :user
               })
    end

    test "super users can access user management page" do
      assert :ok =
               Bodyguard.permit(Lightning.Accounts.Policy, :index, %User{
                 role: :superuser
               })
    end
  end
end
