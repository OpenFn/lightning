defmodule LightningWeb.UserRegistrationControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.AccountsFixtures
  import Mox

  setup do
    verify_on_exit!()
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

      assert response =~ "User Profile"
      assert response =~ "No projects found."
      assert response =~ "User created successfully."
    end

    test "creates account and initial project and logs the user in", %{
      conn: conn
    } do
      expect(Lightning.MockConfig, :init_project_for_new_user, fn -> true end)

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

  describe "POST /api/users/register" do
    test "creates account successfully", %{conn: conn} do
      email = unique_user_email()

      conn =
        post(conn, ~p"/api/users/register", %{
          "user" => valid_user_attributes(email: email)
        })

      assert json_response(conn, 200)
    end

    test "creates account and initial project", %{
      conn: conn
    } do
      expect(Lightning.MockConfig, :init_project_for_new_user, fn -> true end)

      user_name = "Emory"

      conn =
        conn
        |> post(~p"/api/users/register",
          user: valid_user_attributes(first_name: user_name)
        )

      assert %{"data" => %{"id" => user_id}} = json_response(conn, 200)

      expected_project_name = "#{String.downcase(user_name)}-demo"

      assert project =
               Lightning.Repo.get_by(Lightning.Projects.Project,
                 name: expected_project_name
               )

      assert Lightning.Repo.get_by(Lightning.Projects.ProjectUser,
               user_id: user_id,
               role: :owner,
               project_id: project.id
             )
    end

    test "render errors for invalid data", %{conn: conn} do
      conn =
        post(conn, ~p"/api/users/register", %{
          "user" => %{"email" => "with spaces"}
        })

      assert %{"errors" => errors} = json_response(conn, 400)

      assert errors["email"] == ["Email address not valid."]
    end

    test "render errors for terms and conditions not accepted", %{conn: conn} do
      conn =
        post(conn, ~p"/api/users/register", %{
          "user" => %{"terms_accepted" => false}
        })

      assert %{"errors" => errors} = json_response(conn, 400)

      assert errors["terms_accepted"] ==
               ["Please accept the terms and conditions to register."]
    end
  end
end
