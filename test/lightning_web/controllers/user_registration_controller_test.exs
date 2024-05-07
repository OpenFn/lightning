defmodule LightningWeb.UserRegistrationControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.AccountsFixtures
  import Mox

  setup :verify_on_exit!

  Mox.stub_with(Lightning.MockConfig, Lightning.Config.API)

  describe "GET /users/register" do
    setup do
      expect(Lightning.MockConfig, :check_access?, fn _flag ->
        true
      end)

      :ok
    end

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
    setup do
      expect(Lightning.MockConfig, :check_access?, fn _flag ->
        true
      end)

      :ok
    end

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

      assert response =~ "User Profile"
      assert response =~ "No projects found."
      assert response =~ "User created successfully."
    end

    test "creates account and initial project and logs the user in", %{
      conn: conn
    } do
      # Modify the env so that we created new projects for new users
      Application.put_env(:lightning, :init_project_for_new_user, true)

      # conn
      # |> post(~p"/users/confirm",
      #   user: valid_user_attributes(first_name: "Emory")
      # )
      # |> get("/")
      conn =
        conn
        |> post(~p"/users/register",
          user: valid_user_attributes(first_name: "Emory")
        )
        |> get("/")

      project =
        conn.assigns.current_user
        |> Ecto.assoc(:projects)
        |> Lightning.Repo.one!()

      assert project
             |> Map.get(:name) == "emory-demo"

      assert project
             |> Lightning.Projects.project_workorders_query()
             |> Lightning.Repo.aggregate(:count, :id) == 0

      project
      |> Lightning.Projects.project_steps_query()
      |> Lightning.Repo.all()

      assert project
             |> Lightning.Projects.project_steps_query()
             |> Lightning.Repo.aggregate(:count, :id) == 0

      # Set this back to the default "false" before finishing the test
      Application.put_env(:lightning, :init_project_for_new_user, false)
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
