defmodule Lightning.Projects.PolicyTest do
  use Lightning.DataCase

  alias Lightning.Accounts.User

  describe "Projects policy" do
    test "regular users can't do anything" do
      assert {:error, :unauthorized} =
               Bodyguard.permit(Lightning.Projects.Policy, :index, %User{
                 role: :user
               })
    end

    test "super users can access user management page" do
      assert :ok =
               Bodyguard.permit(Lightning.Projects.Policy, :index, %User{
                 role: :superuser
               })
    end
  end
end
