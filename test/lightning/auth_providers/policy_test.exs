defmodule Lightning.AuthProviders.PolicyTest do
  use ExUnit.Case, async: true

  alias Lightning.Accounts.User

  describe "AuthProviders policy" do
    test "regular users can't do anything" do
      assert {:error, :unauthorized} =
               Bodyguard.permit(Lightning.AuthProviders.Policy, :index, %User{
                 role: :user
               })
    end

    test "super users can access the auth management page" do
      assert :ok =
               Bodyguard.permit(Lightning.AuthProviders.Policy, :index, %User{
                 role: :superuser
               })
    end
  end
end
