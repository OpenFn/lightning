defmodule LightningWeb.UserSocketTest do
  use LightningWeb.ChannelCase, async: true

  import Lightning.Factories

  alias Lightning.Accounts
  alias LightningWeb.UserSocket

  defp socket_token(session_token) do
    Phoenix.Token.encrypt(@endpoint, "user socket", session_token)
  end

  describe "connect/3" do
    test "connects with a token bound to a live session" do
      user = insert(:user)
      session_token = Accounts.generate_user_session_token(user)

      assert {:ok, socket} =
               connect(UserSocket, %{"token" => socket_token(session_token)})

      assert socket.assigns.current_user.id == user.id
    end

    test "refuses connection once the session is revoked" do
      user = insert(:user)
      session_token = Accounts.generate_user_session_token(user)
      token = socket_token(session_token)

      assert {:ok, _socket} = connect(UserSocket, %{"token" => token})

      # Logout / password reset / disable all delete the session token.
      Accounts.delete_session_token(session_token)

      assert :error = connect(UserSocket, %{"token" => token})
    end

    test "refuses a token that does not wrap a valid session" do
      assert :error = connect(UserSocket, %{"token" => "not-a-token"})
    end

    test "refuses a legacy signed (unencrypted) token" do
      user = insert(:user)
      legacy = Phoenix.Token.sign(@endpoint, "user socket", user.id)

      assert :error = connect(UserSocket, %{"token" => legacy})
    end

    test "refuses a disabled user" do
      user = insert(:user, disabled: true)
      session_token = Accounts.generate_user_session_token(user)

      assert :error =
               connect(UserSocket, %{"token" => socket_token(session_token)})
    end

    test "refuses a user scheduled for deletion" do
      user =
        insert(:user,
          scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      session_token = Accounts.generate_user_session_token(user)

      assert :error =
               connect(UserSocket, %{"token" => socket_token(session_token)})
    end
  end
end
