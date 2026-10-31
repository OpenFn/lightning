defmodule LightningWeb.InitAssignsTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  alias Lightning.Accounts
  alias LightningWeb.InitAssigns

  describe "on_mount/4" do
    test "halts a mount whose session token no longer resolves" do
      user = insert(:user)
      token = Accounts.generate_user_session_token(user)
      Accounts.delete_session_token(token)

      assert {:halt, halted} =
               InitAssigns.on_mount(
                 :default,
                 %{},
                 %{"user_token" => token},
                 bare_socket()
               )

      assert {:redirect, %{to: "/users/log_in"}} = halted.redirected
      assert Phoenix.Flash.get(halted.assigns.flash, :error) == nil
    end

    test "halts a mount carrying no session token at all" do
      assert {:halt, halted} =
               InitAssigns.on_mount(:default, %{}, %{}, bare_socket())

      assert {:redirect, %{to: "/users/log_in"}} = halted.redirected
      refute Map.has_key?(halted.assigns, :current_user)
    end

    test "continues a mount whose session token resolves" do
      user = insert(:user)
      session = %{"user_token" => Accounts.generate_user_session_token(user)}

      assert {:cont, socket} =
               InitAssigns.on_mount(:default, %{}, session, bare_socket())

      assert %{current_user: %{id: id}, sidebar_collapsed: false} =
               socket.assigns

      assert id == user.id
    end

    # Unit coverage of this callback, not a claim about where the block lives.
    # On any initial HTTP mount the request is refused before a hook runs, so
    # this halt only ever fires on a websocket mount — which is why it cannot
    # be reached through `live/2`. The behavioural claims are made without
    # naming a module, in confirmation_lockout_live_test.exs.
    test "halts a mount for an account locked out pending email confirmation" do
      Mox.stub(Lightning.MockConfig, :check_flag?, fn
        :require_email_verification -> true
        flag -> Lightning.Config.API.check_flag?(flag)
      end)

      user =
        insert(:user,
          confirmed_at: nil,
          inserted_at: DateTime.utc_now() |> Timex.shift(hours: -50)
        )

      session = %{"user_token" => Accounts.generate_user_session_token(user)}

      assert {:halt, halted} =
               InitAssigns.on_mount(:default, %{}, session, bare_socket())

      assert {:redirect, %{to: "/users/confirm-required"}} = halted.redirected

      assert Phoenix.Flash.get(halted.assigns.flash, :error) =~
               "blocked pending email confirmation"

      # Inside the grace period the same account mounts normally.
      fresh = insert(:user, confirmed_at: nil, inserted_at: DateTime.utc_now())

      fresh_session = %{
        "user_token" => Accounts.generate_user_session_token(fresh)
      }

      assert {:cont, _socket} =
               InitAssigns.on_mount(:default, %{}, fresh_session, bare_socket())
    end
  end

  describe "sidebar toggle" do
    setup :register_and_log_in_user

    test "toggle_sidebar event toggles sidebar_collapsed state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/projects")

      # Initially not collapsed
      assert view |> element("#sidebar:not(.collapsed)") |> has_element?() or
               not (view |> element("#sidebar.collapsed") |> has_element?())

      # Toggle sidebar
      view |> render_hook("toggle_sidebar", %{})

      # Should now be collapsed
      assert %{sidebar_collapsed: true} = :sys.get_state(view.pid).socket.assigns
    end

    test "toggle_sidebar persists preference for logged-in user", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/projects")

      # Toggle sidebar
      view |> render_hook("toggle_sidebar", %{})

      # Verify preference was persisted
      updated_user = Accounts.get_user!(user.id)
      assert Accounts.get_preference(updated_user, "sidebar_collapsed") == true

      # Toggle again
      view |> render_hook("toggle_sidebar", %{})

      updated_user = Accounts.get_user!(user.id)
      assert Accounts.get_preference(updated_user, "sidebar_collapsed") == false
    end

    test "sidebar state is loaded from user preferences on mount", %{
      conn: conn,
      user: user
    } do
      # Set preference before mounting
      {:ok, _user} =
        Accounts.update_user_preference(user, "sidebar_collapsed", true)

      {:ok, view, _html} = live(conn, ~p"/projects")

      # Should be collapsed based on saved preference
      assert %{sidebar_collapsed: true} = :sys.get_state(view.pid).socket.assigns
    end
  end

  defp bare_socket do
    %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, flash: %{}},
      private: %{live_temp: %{}, lifecycle: %Phoenix.LiveView.Lifecycle{}}
    }
  end
end
