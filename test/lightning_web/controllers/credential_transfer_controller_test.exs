defmodule LightningWeb.CredentialTransferControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  alias Lightning.Accounts.UserToken
  alias Lightning.Repo

  setup do
    owner = insert(:user)
    receiver = insert(:user)
    credential = insert(:credential, user: owner)

    {token, user_token} =
      UserToken.build_email_token(owner, "credential_transfer", owner.email)

    {:ok, _token} = Repo.insert(user_token)

    %{
      owner: owner,
      receiver: receiver,
      credential: credential,
      token: token
    }
  end

  describe "GET /credentials/transfer/:credential_id/:receiver_id/:token" do
    test "requires user authentication", %{
      conn: conn,
      receiver: %{id: receiver_id},
      credential: %{id: credential_id},
      token: token
    } do
      conn =
        get(
          conn,
          ~p"/credentials/transfer/#{credential_id}/#{receiver_id}/#{token}"
        )

      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "confirms credential transfer with valid data", %{
      conn: conn,
      owner: owner,
      receiver: %{id: receiver_id},
      credential: %{id: credential_id},
      token: token
    } do
      conn =
        conn
        |> log_in_user(owner)
        |> get(
          ~p"/credentials/transfer/#{credential_id}/#{receiver_id}/#{token}"
        )

      assert redirected_to(conn) == ~p"/projects"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Credential transfer confirmed successfully."

      updated_credential = Lightning.Credentials.get_credential!(credential_id)
      assert updated_credential.user_id == receiver_id
    end

    test "returns error when user is not the owner", %{
      conn: conn,
      receiver: %{id: receiver_id},
      credential: %{id: credential_id},
      token: token
    } do
      non_owner = insert(:user)

      conn =
        conn
        |> log_in_user(non_owner)
        |> get(
          ~p"/credentials/transfer/#{credential_id}/#{receiver_id}/#{token}"
        )

      assert redirected_to(conn) == ~p"/projects"
      assert Phoenix.Flash.get(conn.assigns.flash, :nav) == :no_access_no_back

      updated_credential = Lightning.Credentials.get_credential!(credential_id)
      refute updated_credential.user_id == receiver_id
    end

    test "returns error with invalid token", %{
      conn: conn,
      owner: owner,
      receiver: %{id: receiver_id},
      credential: %{id: credential_id}
    } do
      conn =
        conn
        |> log_in_user(owner)
        |> get(
          ~p"/credentials/transfer/#{credential_id}/#{receiver_id}/invalid-token"
        )

      assert redirected_to(conn) == ~p"/projects"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Credential transfer couldn't be confirmed."

      updated_credential = Lightning.Credentials.get_credential!(credential_id)
      refute updated_credential.user_id == receiver_id
    end

    test "returns error with non-existent credential", %{
      conn: conn,
      owner: owner,
      receiver: %{id: receiver_id},
      token: token
    } do
      non_existent_credential_id = Ecto.UUID.generate()

      conn =
        conn
        |> log_in_user(owner)
        |> get(
          ~p"/credentials/transfer/#{non_existent_credential_id}/#{receiver_id}/#{token}"
        )

      assert redirected_to(conn) == ~p"/projects"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Credential transfer couldn't be confirmed."
    end

    test "returns error with non-existent receiver", %{
      conn: conn,
      owner: owner,
      credential: %{id: credential_id},
      token: token
    } do
      non_existent_receiver_id = Ecto.UUID.generate()

      conn =
        conn
        |> log_in_user(owner)
        |> get(
          ~p"/credentials/transfer/#{credential_id}/#{non_existent_receiver_id}/#{token}"
        )

      assert redirected_to(conn) == ~p"/projects"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Credential transfer couldn't be confirmed."

      updated_credential = Lightning.Credentials.get_credential!(credential_id)
      refute updated_credential.user_id == non_existent_receiver_id
    end
  end
end
