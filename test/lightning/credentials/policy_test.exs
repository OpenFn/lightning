defmodule Lightning.Credentials.PolicyTest do
  use Lightning.DataCase, async: true

  describe "Accounts policy" do
    test "users can only access their credentials" do
      user = Lightning.AccountsFixtures.user_fixture()

      credential_1 =
        Lightning.CredentialsFixtures.credential_fixture(user_id: user.id)

      credential_2 = Lightning.CredentialsFixtures.credential_fixture()

      assert :ok =
               Bodyguard.permit(
                 Lightning.Credentials.Policy,
                 :show,
                 user,
                 credential_1
               )

      assert {:error, :unauthorized} =
               Bodyguard.permit(
                 Lightning.Credentials.Policy,
                 :show,
                 user,
                 credential_2
               )
    end
  end
end
