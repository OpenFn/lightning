defmodule LightningWeb.CredentialTransferControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  setup do
    owner = insert(:user)
    receiver = insert(:user)
    credential = insert(:credential, user: owner)

    :ok =
      Lightning.Credentials.initiate_credential_transfer(
        owner,
        receiver,
        credential
      )

    # Pull the signed JWT out of the confirmation email delivered by
    # initiate_credential_transfer/3 (single-segment /transfer/:token route).
    assert_received {:email, email}

    [token] =
      Regex.run(~r{/transfer/([^\s\n/]+)}, email.text_body,
        capture: :all_but_first
      )

    %{
      owner: owner,
      receiver: receiver,
      credential: credential,
      token: token
    }
  end

  describe "GET /credentials/transfer/:token" do
    test "requires user authentication", %{conn: conn, token: token} do
      conn = get(conn, ~p"/credentials/transfer/#{token}")

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
        |> get(~p"/credentials/transfer/#{token}")

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
        |> get(~p"/credentials/transfer/#{token}")

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
        |> get(~p"/credentials/transfer/invalid-token")

      assert redirected_to(conn) == ~p"/projects"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Credential transfer couldn't be confirmed."

      updated_credential = Lightning.Credentials.get_credential!(credential_id)
      refute updated_credential.user_id == receiver_id
    end

    test "returns error once the transfer has been revoked", %{
      conn: conn,
      owner: owner,
      receiver: %{id: receiver_id},
      credential: credential,
      token: token
    } do
      assert {:ok, _} =
               Lightning.Credentials.revoke_transfer(credential.id, owner)

      conn =
        conn
        |> log_in_user(owner)
        |> get(~p"/credentials/transfer/#{token}")

      assert redirected_to(conn) == ~p"/projects"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Credential transfer couldn't be confirmed."

      updated_credential = Lightning.Credentials.get_credential!(credential.id)
      refute updated_credential.user_id == receiver_id
    end
  end
end
