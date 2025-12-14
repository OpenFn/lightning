defmodule LightningWeb.InitAssignsTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Lightning.Accounts
  alias LightningWeb.InitAssigns

  describe "on_mount/4" do
    test "defaults sidebar_collapsed to false when no user" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}},
        private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}}
      }

      {:cont, socket} = InitAssigns.on_mount(:default, %{}, %{}, socket)

      assert socket.assigns.sidebar_collapsed == false
      assert socket.assigns.current_user == nil
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

  describe "handle_sidebar_toggle/3 edge cases" do
    setup :register_and_log_in_user

    test "toggle still updates local state when preference save fails", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/projects")

      # Delete the user after LiveView mounts to cause preference update to fail
      Lightning.Repo.delete!(user)

      # Toggle should still work locally even though DB update will fail
      view |> render_hook("toggle_sidebar", %{})

      # Local state should be updated despite DB error
      assert %{sidebar_collapsed: true} = :sys.get_state(view.pid).socket.assigns

      # Toggle again - should still work
      view |> render_hook("toggle_sidebar", %{})

      assert %{sidebar_collapsed: false} =
               :sys.get_state(view.pid).socket.assigns
    end
  end
end
