defmodule LightningWeb.FirstSetupLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "show" do
    @tag create_initial_user: false
    test "requires a user to create an initial superuser", %{conn: conn} do
      {:ok, show_live, _html} =
        live(conn, Routes.first_setup_superuser_path(conn, :show))

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
            password: "aaaaaaaa",
            password_confirmation: "aaaaaaaa",
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

    test "will redirect with a warning when a user already exists", %{conn: conn} do
      assert {:error, {:redirect, %{flash: %{}, to: "/projects"}}} ==
               live(conn, Routes.first_setup_superuser_path(conn, :show))
    end
  end
end
