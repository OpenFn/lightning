defmodule LightningWeb.UserRegistrationControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.AccountsFixtures
  import Mox

  setup do
    verify_on_exit!()

    Mox.stub(Lightning.MockConfig, :check_flag?, fn
      :allow_signup -> true
      :init_project_for_new_user -> false
      :require_email_verification -> true
    end)

    :ok
  end

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

      assert redirected_to(conn) == "/projects"
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
      assert redirected_to(conn) == "/projects"

      # Now do a logged in request and assert on the menu
      conn = get(conn, "/projects")
      response = html_response(conn, 200)
      # assert response =~ email

      assert response =~ "User Profile"
      assert response =~ "No projects found."
      assert response =~ "User created successfully."
    end

    test "creates account and initial project and logs the user in", %{
      conn: conn
    } do
      # Modify the env so that we created new projects for new users
      Lightning.MockConfig
      |> expect(:check_flag?, fn :allow_signup -> true end)
      |> expect(:check_flag?, fn :init_project_for_new_user -> true end)
      |> expect(:check_flag?, fn :require_email_verification -> true end)

      conn =
        conn
        |> post(~p"/users/register",
          user:
            valid_user_attributes(
              first_name: " Emory H   ",
              last_name: " McLasterson "
            )
        )
        |> get("/")

      assert conn.assigns.current_user.first_name == "Emory H"
      assert conn.assigns.current_user.last_name == "McLasterson"

      project =
        conn.assigns.current_user
        |> Ecto.assoc(:projects)
        |> Lightning.Repo.one!()

      assert project
             |> Map.get(:name) == "emory-h-demo"

      assert project
             |> Lightning.Projects.project_workorders_query()
             |> Lightning.Repo.aggregate(:count, :id) == 0

      project
      |> Lightning.Projects.project_steps_query()
      |> Lightning.Repo.all()

      assert project
             |> Lightning.Projects.project_steps_query()
             |> Lightning.Repo.aggregate(:count, :id) == 0
    end

    test "render errors for invalid data", %{conn: conn} do
      conn =
        post(conn, Routes.user_registration_path(conn, :create), %{
          "user" => %{"email" => "with spaces"}
        })

      response = html_response(conn, 200)
      assert response =~ "Register"
      assert response =~ "Email address not valid."
    end

    test "render errors for terms and conditions not accepted", %{conn: conn} do
      conn =
        post(conn, Routes.user_registration_path(conn, :create), %{
          "user" => %{"terms_accepted" => false}
        })

      response = html_response(conn, 200)
      assert response =~ "Register"
      assert response =~ "Please accept the terms and conditions to register."
    end
  end
end
