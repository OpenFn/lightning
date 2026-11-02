defmodule Lightning.Accounts.ApiTokensTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Accounts
  alias Lightning.Accounts.UserToken

  describe "create_api_token/1" do
    test "stores a personal access token for the user and returns its entry" do
      user = insert(:user)

      assert {:ok, %UserToken{context: "api", token: token} = entry} =
               Accounts.create_api_token(user)

      assert entry.user_id == user.id
      assert Accounts.get_user_by_api_token(token).id == user.id
    end
  end

  describe "revoke_api_token/2" do
    test "revokes the user's personal access token" do
      user = insert(:user)
      {:ok, entry} = Accounts.create_api_token(user)

      assert :ok = Accounts.revoke_api_token(user, entry.id)
      refute Accounts.get_user_by_api_token(entry.token)
    end

    test "finds nothing for another user's token, a token of another kind, or a revoked one" do
      user = insert(:user)
      {:ok, theirs} = Accounts.create_api_token(insert(:user))
      Accounts.generate_user_session_token(user)
      session = Repo.get_by!(UserToken, user_id: user.id, context: "session")
      {:ok, revoked} = Accounts.create_api_token(user)
      :ok = Accounts.revoke_api_token(user, revoked.id)

      for id <- [theirs.id, session.id, revoked.id] do
        assert {:error, :not_found} = Accounts.revoke_api_token(user, id)
      end

      assert Repo.get(UserToken, theirs.id)
      assert Repo.get(UserToken, session.id)
    end
  end
end
