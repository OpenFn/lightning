defmodule LightningWeb.UserSocketTest do
  # Not async: joining a collaboration channel starts a supervised SharedDoc
  # that reads the database from outside the test process, which needs the
  # sandbox in shared mode.
  use LightningWeb.ChannelCase

  import Lightning.CollaborationHelpers
  import Lightning.Factories

  alias Lightning.Accounts
  alias LightningWeb.UserSocket

  defp socket_token(session_token) do
    Phoenix.Token.encrypt(@endpoint, "user socket", session_token)
  end

  defp require_email_verification(value) do
    Mox.stub(Lightning.MockConfig, :check_flag?, fn
      :require_email_verification -> value
      flag -> Lightning.Config.API.check_flag?(flag)
    end)
  end

  defp hours_ago(hours) do
    DateTime.utc_now()
    |> DateTime.add(-hours, :hour)
    |> DateTime.truncate(:second)
  end

  defp move_inserted_at(user, hours) do
    user
    |> Ecto.Changeset.change(inserted_at: hours_ago(hours))
    |> Repo.update!()
  end

  defp confirm(user) do
    user
    |> Ecto.Changeset.change(
      confirmed_at: DateTime.truncate(DateTime.utc_now(), :second)
    )
    |> Repo.update!()
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

    test "refuses an account locked out pending confirmation" do
      require_email_verification(true)

      user = insert(:user, confirmed_at: nil, inserted_at: hours_ago(50))
      session_token = Accounts.generate_user_session_token(user)

      assert :error =
               connect(UserSocket, %{"token" => socket_token(session_token)})
    end

    test "connects while the lockout does not apply" do
      require_email_verification(true)

      # Unconfirmed, but inside the 48-hour grace period.
      user = insert(:user, confirmed_at: nil, inserted_at: hours_ago(1))
      token = socket_token(Accounts.generate_user_session_token(user))

      assert {:ok, _socket} = connect(UserSocket, %{"token" => token})

      # Same account, now past the deadline but with a confirmed address.
      user = user |> move_inserted_at(50) |> confirm()

      assert {:ok, _socket} = connect(UserSocket, %{"token" => token})

      # Same account, unconfirmed and past the deadline, on an instance that
      # does not require verification.
      require_email_verification(false)

      user |> Ecto.Changeset.change(confirmed_at: nil) |> Repo.update!()

      assert {:ok, _socket} = connect(UserSocket, %{"token" => token})
    end

    test "the connection refusal is what closes every channel on this socket" do
      require_email_verification(true)

      user = insert(:user, confirmed_at: nil, inserted_at: hours_ago(50))
      project = insert(:project, project_users: [%{user: user, role: :owner}])
      workflow = insert(:workflow, project: project)
      token = socket_token(Accounts.generate_user_session_token(user))

      # There is no socket, so there is no join to refuse. Asserting it here
      # covers every channel routed off /socket, present and future.
      assert :error = connect(UserSocket, %{"token" => token})

      confirm(user)

      assert {:ok, socket} = connect(UserSocket, %{"token" => token})

      assert {:ok, _reply, _joined} =
               subscribe_and_join(
                 socket,
                 "workflow:collaborate:#{workflow.id}",
                 %{"project_id" => project.id, "action" => "edit"}
               )

      on_exit(fn -> ensure_doc_supervisor_stopped(workflow.id) end)
    end

    test "a socket opened before the deadline keeps joining channels after it" do
      require_email_verification(true)

      user = insert(:user, confirmed_at: nil, inserted_at: hours_ago(1))
      project = insert(:project, project_users: [%{user: user, role: :owner}])
      workflow = insert(:workflow, project: project)
      token = socket_token(Accounts.generate_user_session_token(user))

      assert {:ok, socket} = connect(UserSocket, %{"token" => token})

      # The account crosses its deadline while the socket is open.
      move_inserted_at(user, 50)

      # This is the gap we accept, not a feature: connect/3 is the only place
      # the lockout is consulted, and it does not run again on a socket that is
      # already up, so a new join on it still succeeds. Reconnecting refuses it.
      # Closing this properly means evicting live connections on an
      # account-state change, which is the epoch check in phase 3 of the auth
      # overhaul. When that lands this assertion is wrong and this test fails.
      assert {:ok, _reply, _joined} =
               subscribe_and_join(
                 socket,
                 "workflow:collaborate:#{workflow.id}",
                 %{"project_id" => project.id, "action" => "edit"}
               )

      on_exit(fn -> ensure_doc_supervisor_stopped(workflow.id) end)
    end
  end
end
