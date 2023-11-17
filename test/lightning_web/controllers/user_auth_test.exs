defmodule LightningWeb.UserAuthTest do
  use LightningWeb.ConnCase, async: true

  alias Lightning.Accounts
  alias LightningWeb.UserAuth
  import Lightning.AccountsFixtures

  @remember_me_cookie "_lightning_web_user_remember_me"

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(
        :secret_key_base,
        LightningWeb.Endpoint.config(:secret_key_base)
      )
      |> init_test_session(%{})
      |> Phoenix.Controller.accepts(["html", "json"])

    %{user: user_fixture(), conn: conn}
  end

  describe "log_in_user/2" do
    test "stores the user token in the session", %{conn: conn, user: user} do
      conn = UserAuth.log_in_user(conn, user)
      assert token = get_session(conn, :user_token)

      assert get_session(conn, :live_socket_id) ==
               "users_sessions:#{Base.url_encode64(token)}"

      assert Accounts.get_user_by_session_token(token)
    end

    test "clears everything previously stored in the session", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> put_session(:to_be_removed, "value")
        |> UserAuth.log_in_user(user)

      refute get_session(conn, :to_be_removed)
    end

    test "does not clear the configured redirect path", %{conn: conn, user: user} do
      conn =
        conn
        |> put_session(:user_return_to, "/hello")
        |> UserAuth.log_in_user(user)

      assert get_session(conn, :user_return_to)
    end
  end

  describe "redirect_with_return_to/2" do
    test "redirects to / by default", %{conn: conn} do
      assert conn
             |> UserAuth.redirect_with_return_to()
             |> redirected_to() == "/"
    end

    test "redirects to the configured path", %{conn: conn} do
      conn =
        conn
        |> put_session(:user_return_to, "/hello")
        |> UserAuth.redirect_with_return_to()

      assert redirected_to(conn) == "/hello"
      refute get_session(conn, :user_return_to)
    end

    test "writes a cookie if remember_me is configured", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> fetch_cookies()
        |> UserAuth.log_in_user(user)
        |> UserAuth.redirect_with_return_to(%{
          "remember_me" => "true"
        })

      assert get_session(conn, :user_token) == conn.cookies[@remember_me_cookie]

      assert %{value: signed_token, max_age: max_age} =
               conn.resp_cookies[@remember_me_cookie]

      assert signed_token != get_session(conn, :user_token)
      assert max_age == 5_184_000
    end
  end

  describe "logout_user/1" do
    test "erases session and cookies", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_session(:user_token, user_token)
        |> put_req_cookie(@remember_me_cookie, user_token)
        |> fetch_cookies()
        |> UserAuth.log_out_user()

      refute get_session(conn, :user_token)
      refute conn.cookies[@remember_me_cookie]
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == "/users/log_in"
      refute Accounts.get_user_by_session_token(user_token)
    end

    test "broadcasts to the given live_socket_id", %{conn: conn} do
      live_socket_id = "users_sessions:abcdef-token"
      LightningWeb.Endpoint.subscribe(live_socket_id)

      conn
      |> put_session(:live_socket_id, live_socket_id)
      |> UserAuth.log_out_user()

      assert_receive %Phoenix.Socket.Broadcast{
        event: "disconnect",
        topic: ^live_socket_id
      }
    end

    test "works even if user is already logged out", %{conn: conn} do
      conn = conn |> fetch_cookies() |> UserAuth.log_out_user()
      refute get_session(conn, :user_token)
      assert %{max_age: 0} = conn.resp_cookies[@remember_me_cookie]
      assert redirected_to(conn) == "/users/log_in"
    end
  end

  describe "fetch_current_user/2" do
    test "authenticates user from session", %{conn: conn, user: user} do
      user_token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_session(:user_token, user_token)
        |> UserAuth.fetch_current_user([])

      assert conn.assigns.current_user.id == user.id
    end

    test "authenticates user from cookies", %{conn: conn, user: user} do
      logged_in_conn =
        conn
        |> fetch_cookies()
        |> UserAuth.log_in_user(user)
        |> UserAuth.redirect_with_return_to(%{
          "remember_me" => "true"
        })

      user_token = logged_in_conn.cookies[@remember_me_cookie]
      %{value: signed_token} = logged_in_conn.resp_cookies[@remember_me_cookie]

      conn =
        conn
        |> put_req_cookie(@remember_me_cookie, signed_token)
        |> UserAuth.fetch_current_user([])

      assert get_session(conn, :user_token) == user_token
      assert conn.assigns.current_user.id == user.id
    end

    test "does not authenticate if data is missing", %{conn: conn, user: user} do
      _ = Accounts.generate_user_session_token(user)
      conn = UserAuth.fetch_current_user(conn, [])
      refute get_session(conn, :user_token)
      refute conn.assigns.current_user
    end
  end

  describe "redirect_if_user_is_authenticated/2" do
    test "redirects if user is authenticated", %{conn: conn, user: user} do
      conn =
        conn
        |> assign(:current_user, user)
        |> UserAuth.redirect_if_user_is_authenticated([])

      assert conn.halted
      assert redirected_to(conn) == "/"
    end

    test "does not redirect if user is not authenticated", %{conn: conn} do
      conn = UserAuth.redirect_if_user_is_authenticated(conn, [])
      refute conn.halted
      refute conn.status
    end
  end

  describe "require_authenticated_user/2" do
    test "redirects if user is not authenticated", %{conn: conn} do
      conn = conn |> fetch_flash() |> UserAuth.require_authenticated_user([])
      assert conn.halted
      assert redirected_to(conn) == Routes.user_session_path(conn, :new)

      # flash message disabled
      assert Phoenix.Flash.get(conn.assigns.flash, :error) |> is_nil()
    end

    test "returns a 401 on json requests if user is not authenticated", %{
      conn: conn
    } do
      conn =
        conn
        |> Phoenix.Controller.put_format("json")
        |> UserAuth.require_authenticated_user([])

      assert conn.halted
      assert conn.status == 401
      assert conn.resp_body |> Jason.decode!() == %{"error" => "Unauthorized"}
    end

    test "stores the path to redirect to on GET", %{conn: conn} do
      halted_conn =
        %{conn | path_info: ["foo"], query_string: ""}
        |> fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      assert get_session(halted_conn, :user_return_to) == "/foo"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar=baz"}
        |> fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      assert get_session(halted_conn, :user_return_to) == "/foo?bar=baz"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar", method: "POST"}
        |> fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert halted_conn.halted
      refute get_session(halted_conn, :user_return_to)
    end

    test "does not redirect if user is authenticated", %{conn: conn, user: user} do
      conn =
        conn
        |> assign(:current_user, user)
        |> UserAuth.require_authenticated_user([])

      refute conn.halted
      refute conn.status
    end

    test "redirects if user is authenticated but pending totp", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> assign(:current_user, user)
        |> UserAuth.mark_totp_pending()
        |> UserAuth.require_authenticated_user([])

      assert conn.halted
      assert redirected_to(conn) == Routes.user_totp_path(conn, :new)
    end
  end

  describe "reauth_sudo_mode/2" do
    test "sets sudo mode from session", %{conn: conn, user: user} do
      sudo_token = Accounts.generate_sudo_session_token(user)

      conn =
        conn
        |> assign(:current_user, user)
        |> put_session(:sudo_token, Base.encode64(sudo_token))
        |> UserAuth.reauth_sudo_mode([])

      assert conn.assigns.sudo_mode? == true
    end

    test "sets sudo mode from query params", %{conn: conn, user: user} do
      sudo_token = Accounts.generate_sudo_session_token(user)

      conn = %{conn | query_params: %{"sudo_token" => Base.encode64(sudo_token)}}
      conn = assign(conn, :current_user, user)

      refute conn.assigns[:sudo_mode?]
      refute get_session(conn, :sudo_token)

      conn = UserAuth.reauth_sudo_mode(conn, [])

      assert conn.assigns.sudo_mode? == true
      assert get_session(conn, :sudo_token) == Base.encode64(sudo_token)
    end

    test "does not reauthenticate if current_user assign is missing", %{
      conn: conn,
      user: user
    } do
      sudo_token = Accounts.generate_sudo_session_token(user)
      conn = %{conn | query_params: %{"sudo_token" => Base.encode64(sudo_token)}}
      conn = UserAuth.reauth_sudo_mode(conn, [])

      refute conn.assigns.sudo_mode?
    end

    test "does not reauthenticate if sudo_token session is missing", %{
      conn: conn,
      user: user
    } do
      refute get_session(conn, :sudo_token)

      Accounts.generate_sudo_session_token(user)

      conn = UserAuth.reauth_sudo_mode(conn, [])

      refute conn.assigns.sudo_mode?
    end
  end

  describe "require_sudo_user/2" do
    test "redirects if sudo mode is not set", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)
      conn = conn |> fetch_flash() |> UserAuth.require_sudo_user([])
      assert conn.halted
      assert redirected_to(conn) == ~p"/auth/confirm_access"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "You must verify yourself again in order to access this page."
    end

    test "stores the path to redirect to on GET", %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      halted_conn =
        %{conn | path_info: ["foo"], query_string: ""}
        |> fetch_flash()
        |> UserAuth.require_sudo_user([])

      assert halted_conn.halted
      assert get_session(halted_conn, :user_return_to) == "/foo"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar=baz"}
        |> fetch_flash()
        |> UserAuth.require_sudo_user([])

      assert halted_conn.halted
      assert get_session(halted_conn, :user_return_to) == "/foo?bar=baz"

      halted_conn =
        %{conn | path_info: ["foo"], query_string: "bar", method: "POST"}
        |> fetch_flash()
        |> UserAuth.require_sudo_user([])

      assert halted_conn.halted
      refute get_session(halted_conn, :user_return_to)
    end

    test "does not redirect if sudo mode is already set", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)

      conn =
        conn
        |> assign(:sudo_mode?, true)
        |> UserAuth.require_sudo_user([])

      refute conn.halted
      refute conn.status
    end
  end

  describe "on_mount: ensure_sudo" do
    setup %{user: user} do
      socket =
        %Phoenix.LiveView.Socket{
          endpoint: LightningWeb.Endpoint,
          assigns: %{__changed__: %{}, flash: %{}}
        }
        |> Phoenix.Component.assign_new(:current_user, fn -> user end)

      %{socket: socket}
    end

    test "reauthenticates current_user based on a valid sudo_token ", %{
      conn: conn,
      socket: socket,
      user: user
    } do
      sudo_token =
        user |> Accounts.generate_sudo_session_token() |> Base.encode64()

      session = conn |> put_session(:sudo_token, sudo_token) |> get_session()

      {:cont, updated_socket} =
        UserAuth.on_mount(
          :ensure_sudo,
          %{},
          session,
          socket
        )

      assert updated_socket.assigns.sudo_mode? == true
    end

    test "redirects to confirm access page if there isn't a valid sudo_token ",
         %{
           conn: conn,
           socket: socket
         } do
      sudo_token = Base.encode64("invalid_token")
      session = conn |> put_session(:sudo_token, sudo_token) |> get_session()

      {:halt, updated_socket} =
        UserAuth.on_mount(:ensure_sudo, %{}, session, socket)

      assert updated_socket.assigns.sudo_mode? == false

      assert {:redirect, %{to: ~p"/auth/confirm_access"}} ==
               updated_socket.redirected
    end

    test "redirects to confirm access page if there isn't a sudo_token ", %{
      conn: conn,
      socket: socket
    } do
      session = conn |> get_session()

      {:halt, updated_socket} =
        UserAuth.on_mount(:ensure_sudo, %{}, session, socket)

      assert updated_socket.assigns.sudo_mode? == nil

      assert {:redirect, %{to: ~p"/auth/confirm_access"}} ==
               updated_socket.redirected
    end
  end

  describe "require_superuser/2" do
    test "redirects and halts if user is not a superuser", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> assign(:current_user, user)
        |> fetch_flash()
        |> UserAuth.require_superuser([])

      assert conn.halted
      assert Phoenix.Flash.get(conn.assigns.flash, :nav) == :no_access_no_back
      assert conn |> redirected_to() == "/"
    end

    test "returns 403 if user is not superuser and json request ", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> assign(:current_user, user)
        |> Phoenix.Controller.put_format("json")
        |> UserAuth.require_superuser([])

      assert conn.halted
      assert conn.status == 403
      assert conn.resp_body |> Jason.decode!() == %{"error" => "Forbidden"}
    end

    test "allows the request to proceed if user is a superuser", %{conn: conn} do
      user = superuser_fixture()

      conn =
        conn
        |> assign(:current_user, user)
        |> fetch_flash()
        |> UserAuth.require_superuser([])

      refute conn.halted
      refute conn.status
      assert Phoenix.Flash.get(conn.assigns.flash, :nav) == nil
    end
  end
end
