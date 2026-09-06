defmodule LightningWeb.Live.AccountRevocationTeardownTest do
  @moduledoc """
  Revoking an account has to reach the pages that account already has open.

  `test/lightning/accounts_test.exs` already covers every revocation entry
  point, but it works out the topic by calling `UserAuth.live_socket_topic/1`,
  the same function the broadcast calls, so it stays green through a rename
  that stops disconnecting every real browser. Here the topic comes out of the
  session, where `fetch_current_user/2` wrote it during a login that goes
  through the production code path.

  `Phoenix.LiveViewTest` never starts a transport process, so nothing here can
  watch a page die. Subscribing to the topic a browser's transport would be
  keyed by is as close as this suite gets.
  """
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import Phoenix.LiveViewTest

  alias Lightning.Accounts
  alias LightningWeb.UserAuth

  # The broadcast is dispatched synchronously from the revoking call, so this
  # window only has to cover a local PubSub hop.
  @disconnect_window 500

  describe "revocation of an account with pages already open" do
    test "reaches the transport topic the session was built with", %{conn: conn} do
      user = confirmed_user()
      conn = log_in_browser(conn, user)
      session_token = get_session(conn, :user_token)
      live_socket_id = watch_transport(conn)

      {:ok, _view, _html} = live(conn, ~p"/projects", on_error: :raise)

      {:ok, _user} = Accounts.update_user_details(user, %{"disabled" => true})

      # Pins the database half of the revocation, so the assertion below is only
      # ever about the other half: the page that was already open.
      refute Accounts.get_user_by_session_token(session_token)

      assert_transport_told_to_disconnect(live_socket_id)
    end

    test "reaches every browser the user is logged in on", %{conn: conn} do
      user = confirmed_user()

      # Both sessions carry the same topic, because the topic is keyed per user.
      # Phoenix's own generator keys it per session token instead, which would
      # leave the second browser running after the first was disconnected.
      conn_a = log_in_browser(conn, user)
      conn_b = log_in_browser(build_conn(), user)

      assert get_session(conn_a, :live_socket_id) ==
               get_session(conn_b, :live_socket_id)

      live_socket_id = watch_transport(conn_a)

      {:ok, _view_a, _html} = live(conn_a, ~p"/projects", on_error: :raise)
      {:ok, _view_b, _html} = live(conn_b, ~p"/projects", on_error: :raise)

      {:ok, _user} = Accounts.update_user_details(user, %{"disabled" => true})

      assert_transport_told_to_disconnect(live_socket_id)
    end
  end

  describe "reconnecting after a revocation" do
    test "a client that reconnects after teardown lands on the login page",
         %{conn: conn} do
      # Narrower than it looks, and kept anyway. `live/2` always issues the HTTP
      # GET first, so `:require_authenticated_user` redirects there and this
      # only pins the full-page-reload path. `Phoenix.LiveViewTest` cannot
      # perform the websocket-only mount a real client reconnect takes, so
      # nothing here observes the nil-user halt in
      # `LightningWeb.InitAssigns.on_mount/4`; that is pinned by unit tests on
      # the hook itself.
      user = confirmed_user()
      conn = log_in_browser(conn, user)

      {:ok, _view, _html} = live(conn, ~p"/projects", on_error: :raise)

      {:ok, _user} = Accounts.update_user_details(user, %{"disabled" => true})

      assert {:error, {redirect, %{to: "/users/log_in"}}} =
               live(conn, ~p"/projects")

      assert redirect in [:redirect, :live_redirect]
    end
  end

  ## Helpers

  defp confirmed_user(attrs \\ []) do
    attrs
    |> Keyword.put_new(
      :confirmed_at,
      DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> then(&insert(:user, &1))
  end

  # The suite's own `log_in_user/2` writes only :user_token, and these tests are
  # about what else a real browser session carries. This goes through the
  # production login and then `fetch_current_user/2`, which is where
  # `:live_socket_id` is written.
  defp log_in_browser(conn, user) do
    conn
    |> browser_conn()
    |> UserAuth.log_in_user(user)
    |> UserAuth.fetch_current_user([])
  end

  # Stands in for one browser's `/live` transport. Phoenix keys that transport
  # by `Phoenix.LiveView.Socket.id/1`, which reads `session["live_socket_id"]`,
  # so subscribing to the same topic is the closest this suite can get to
  # holding a real transport open.
  defp watch_transport(conn) do
    assert live_socket_id = get_session(conn, :live_socket_id)
    LightningWeb.Endpoint.subscribe(live_socket_id)
    live_socket_id
  end

  defp assert_transport_told_to_disconnect(live_socket_id) do
    assert_receive %Phoenix.Socket.Broadcast{
                     event: "disconnect",
                     topic: ^live_socket_id
                   },
                   @disconnect_window
  end
end
