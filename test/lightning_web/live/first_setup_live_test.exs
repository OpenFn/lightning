defmodule LightningWeb.FirstSetupLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "First setup" do
    @tag create_initial_user: false
    test "requires a user to create an initial superuser", %{conn: conn} do
      {:ok, show_live, _html} =
        live(conn, Routes.first_setup_superuser_path(conn, :show),
          on_error: :raise
        )

      assert show_live |> element("h2", "Setup")

      assert show_live
             |> form("#superuser-registration-form",
               superuser_registration: %{password: "123"}
             )
             |> render_change() =~ "does not match confirmation"

      assert show_live
             |> form("#superuser-registration-form",
               superuser_registration: %{
                 password: "123",
                 password_confirmation: "123"
               }
             )
             |> render_change() =~ "Password minimum length is 8 characters"

      {:ok, conn} =
        show_live
        |> form("#superuser-registration-form",
          superuser_registration: %{
            password: "1234567890ab",
            password_confirmation: "1234567890ab",
            first_name: "Test",
            last_name: "McTest",
            email: "foo@example.com"
          }
        )
        |> render_submit()
        |> follow_redirect(conn)

      assert "/projects" = redirected_path = redirected_to(conn, 302)

      html =
        get(recycle(conn), redirected_path)
        |> html_response(200)

      assert html =~ "Superuser account created."
      assert html =~ "Projects"
    end

    @tag create_initial_user: false
    test "refuses a superuser without a first and last name", %{conn: conn} do
      {:ok, show_live, _html} =
        live(conn, Routes.first_setup_superuser_path(conn, :show),
          on_error: :raise
        )

      form =
        form(show_live, "#superuser-registration-form",
          superuser_registration: %{
            password: "1234567890ab",
            password_confirmation: "1234567890ab",
            first_name: " ",
            last_name: "",
            email: "nameless@example.com"
          }
        )

      assert render_change(form) =~ "can&#39;t be blank"
      assert has_element?(show_live, "button[type=submit][disabled]")

      assert render_submit(form) =~ "can&#39;t be blank"
      refute Lightning.Accounts.get_user_by_email("nameless@example.com")
      refute Lightning.Accounts.has_one_superuser?()
    end

    @tag create_initial_user: false
    test "refuses a superuser with a control character in their name", %{
      conn: conn
    } do
      {:ok, show_live, _html} =
        live(conn, Routes.first_setup_superuser_path(conn, :show),
          on_error: :raise
        )

      form =
        form(show_live, "#superuser-registration-form",
          superuser_registration: %{
            password: "1234567890ab",
            password_confirmation: "1234567890ab",
            first_name: "Ann\u0007",
            last_name: "Smith",
            email: "bell@example.com"
          }
        )

      assert render_submit(form) =~ "can&#39;t contain control characters"
      refute Lightning.Accounts.get_user_by_email("bell@example.com")
      refute Lightning.Accounts.has_one_superuser?()
    end

    test "will redirect with a warning when a user already exists", %{conn: conn} do
      assert {:error, {:redirect, %{flash: %{}, to: "/projects"}}} ==
               live(conn, Routes.first_setup_superuser_path(conn, :show),
                 on_error: :raise
               )
    end
  end

  describe "while a service account is registered" do
    setup do
      Mox.stub(Lightning.MockConfig, :check_flag?, fn
        :allow_first_setup -> false
        flag -> Lightning.Config.API.check_flag?(flag)
      end)

      :ok
    end

    @tag create_initial_user: false
    test "does not redirect to first setup", %{conn: conn} do
      refute get(conn, "/") |> redirected_to() == "/first_setup"
    end

    @tag create_initial_user: false
    test "refuses first setup when there is no superuser", %{conn: conn} do
      assert get(conn, "/first_setup") |> response(404) =~
               "First setup is disabled"
    end

    @tag create_initial_user: false
    test "refuses first setup reached by live navigation", context do
      %{conn: conn} = register_and_log_in_user(context)
      {:ok, view, _html} = live(conn, "/credentials")

      assert {:error, {:redirect, %{to: "/projects"}}} =
               live_redirect(view, to: "/first_setup")
    end

    test "refuses first setup when a superuser exists", %{conn: conn} do
      assert get(conn, "/first_setup") |> response(404) =~
               "First setup is disabled"
    end
  end
end
