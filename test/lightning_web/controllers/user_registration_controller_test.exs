defmodule LightningWeb.UserRegistrationControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.AccountsFixtures

  describe "GET /users/register" do
    test "renders registration page", %{conn: conn} do
      conn = get(conn, Routes.user_registration_path(conn, :new))
      response = html_response(conn, 200)
      assert response =~ "Register"
      assert response =~ "Log in"
      assert response =~ "Register"
    end

    test "redirects if already logged in", %{conn: conn} do
      conn =
        conn
        |> log_in_user(user_fixture())
        |> get(Routes.user_registration_path(conn, :new))

      assert redirected_to(conn) == "/"
    end
  end

  describe "POST /users/register" do
    @tag :capture_log
    test "creates account and logs the user in", %{conn: conn} do
      email = unique_user_email()

      conn =
        post(conn, Routes.user_registration_path(conn, :create), %{
          "user" => valid_user_attributes(email: email)
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == "/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, "/")
      response = html_response(conn, 200)
      # assert response =~ email

      assert response =~ "Log out</span>"
    end

    test "creates account and initial project and logs the user in", %{
      conn: conn
    } do
      Application.put_env(:lightning, :init_project_for_new_user, true)

      conn =
        get(
          post(conn, Routes.user_registration_path(conn, :create), %{
            "user" => valid_user_attributes(email: unique_user_email())
          }),
          "/"
        )

      assert conn.assigns.current_user
             |> Ecto.assoc(:projects)
             |> Lightning.Repo.one!()
             |> Map.get(:name) == "openhie-project"
    end

    test "render errors for invalid data", %{conn: conn} do
      conn =
        post(conn, Routes.user_registration_path(conn, :create), %{
          "user" => %{"email" => "with spaces"}
        })

      response = html_response(conn, 200)
      assert response =~ "Register"
      assert response =~ "must have the @ sign and no spaces"
    end
  end
end
