defmodule LightningWeb.ProjectLiveTest do
  use LightningWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Lightning.ProjectsFixtures
  import Lightning.AccountsFixtures
  import Lightning.Factories
  import LightningWeb.CredentialLiveHelpers

  import Lightning.ApplicationHelpers,
    only: [dynamically_absorb_delay: 1, put_temporary_env: 3]

  @cert """
  -----BEGIN RSA PRIVATE KEY-----
  MIICWwIBAAKBgQDdlatRjRjogo3WojgGHFHYLugdUWAY9iR3fy4arWNA1KoS8kVw33cJibXr8bvwUAUparCwlvdbH6dvEOfou0/gCFQsHUfQrSDv+MuSUMAe8jzKE4qW+jK+xQU9a03GUnKHkkle+Q0pX/g6jXZ7r1/xAK5Do2kQ+X5xK9cipRgEKwIDAQABAoGAD+onAtVye4ic7VR7V50DF9bOnwRwNXrARcDhq9LWNRrRGElESYYTQ6EbatXS3MCyjjX2eMhu/aF5YhXBwkppwxg+EOmXeh+MzL7Zh284OuPbkglAaGhV9bb6/5CpuGb1esyPbYW+Ty2PC0GSZfIXkXs76jXAu9TOBvD0ybc2YlkCQQDywg2R/7t3Q2OE2+yo382CLJdrlSLVROWKwb4tb2PjhY4XAwV8d1vy0RenxTB+K5Mu57uVSTHtrMK0GAtFr833AkEA6avx20OHo61Yela/4k5kQDtjEf1N0LfI+BcWZtxsS3jDM3i1Hp0KSu5rsCPb8acJo5RO26gGVrfAsDcIXKC+bQJAZZ2XIpsitLyPpuiMOvBbzPavd4gY6Z8KWrfYzJoI/Q9FuBo6rKwl4BFoToD7WIUS+hpkagwWiz+6zLoX1dbOZwJACmH5fSSjAkLRi54PKJ8TFUeOP15h9sQzydI8zJU+upvDEKZsZc/UhT/SySDOxQ4G/523Y0sz/OZtSWcol/UMgQJALesy++GdvoIDLfJX5GBQpuFgFenRiRDabxrE9MNUZ2aPFaFp+DyAe+b4nDwuJaW2LURbr8AEZga7oQj0uYxcYw==
  -----END RSA PRIVATE KEY-----
  """

  @create_attrs %{
    raw_name: "some name"
  }
  @invalid_attrs %{raw_name: nil}

  describe "Index as a regular user" do
    setup :register_and_log_in_user

    test "cannot access the index page", %{conn: conn} do
      {:ok, _index_live, html} =
        live(conn, ~p"/settings/projects") |> follow_redirect(conn, "/")

      assert html =~ "Sorry, you don&#39;t have access to that."
    end

    test "cannot access the new page", %{conn: conn} do
      {:ok, _index_live, html} =
        live(conn, ~p"/settings/projects/new")
        |> follow_redirect(conn, "/")

      assert html =~ "Sorry, you don&#39;t have access to that."
    end
  end

  describe "Index as a super user" do
    setup [:register_and_log_in_superuser, :create_project_for_current_user]

    test "lists all projects", %{conn: conn, project: project} do
      {:ok, _index_live, html} =
        live(conn, Routes.project_index_path(conn, :index))

      assert html =~ "Projects"
      assert html =~ project.name
    end

    test "saves new project with no members", %{conn: conn} do
      {:ok, index_live, _html} =
        live(conn, Routes.project_index_path(conn, :index))

      assert index_live |> element("a", "New Project") |> render_click() =~
               "Projects"

      assert_patch(index_live, Routes.project_index_path(conn, :new))

      index_live
      |> form("#project-form", project: @create_attrs)
      |> render_change()

      index_live
      |> form("#project-users-form")
      |> render_submit()

      assert_patch(index_live, Routes.project_index_path(conn, :index))
      assert render(index_live) =~ "Project created successfully"
    end

    test "saves new project", %{conn: conn} do
      # this makes it first in the list
      user = insert(:user, first_name: "1")

      {:ok, index_live, _html} =
        live(conn, Routes.project_index_path(conn, :index))

      assert index_live |> element("a", "New Project") |> render_click() =~
               "Projects"

      assert_patch(index_live, Routes.project_index_path(conn, :new))

      assert index_live
             |> form("#project-form", project: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      index_live
      |> form("#project-form", project: @create_attrs)
      |> render_change()

      index_live
      |> form("#project-users-form",
        project: %{
          "project_users" => %{
            "0" => %{"user_id" => user.id, "role" => "editor"}
          }
        }
      )
      |> render_submit()

      assert_patch(index_live, Routes.project_index_path(conn, :index))
      assert render(index_live) =~ "Project created successfully"
    end

    test "project owners can delete a project from the settings page",
         %{
           conn: conn,
           project: project
         } do
      {conn, _user} = setup_project_user(conn, project, :owner)
      {:ok, index_live, html} = live(conn, ~p"/projects/#{project.id}/settings")

      assert html =~ "Deleting your project is irreversible"
      assert index_live |> element("button", "Delete project") |> has_element?()

      {:ok, delete_project_modal, html} =
        live(conn, ~p"/projects/#{project.id}/settings/delete")

      assert html =~ "Enter the project name to confirm it&#39;s deletion"

      {:ok, _delete_project_modal, html} =
        delete_project_modal
        |> form("#scheduled_deletion_form",
          project: %{
            name_confirmation: project.name
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/")

      assert html =~ "Project scheduled for deletion"
    end

    test "project members can export a project", %{conn: conn, project: project} do
      {:ok, index_live, html} = live(conn, ~p"/projects/#{project.id}/settings")

      assert html =~
               "Export your project as code, to save this version or edit your project locally"

      assert index_live
             |> element(~s{a[target="_blank"]}, "Export project")
             |> has_element?()

      assert index_live
             |> element(~s{a[target="_blank"]}, "Export project")
             |> render_click()
             |> follow_redirect(conn, "/download/yaml?id=#{project.id}")
    end

    test "project members with role other than owner can't delete a project from the settings page",
         %{
           conn: conn,
           project: project
         } do
      ~w(editor admin viewer)a
      |> Enum.each(fn role ->
        {conn, _user} = setup_project_user(conn, project, role)

        {:ok, index_live, html} =
          live(conn, ~p"/projects/#{project.id}/settings")

        refute html =~ "Deleting your project is irreversible"

        refute index_live
               |> element("button", "Delete project")
               |> has_element?()

        {:ok, _delete_project_modal, html} =
          live(conn, ~p"/projects/#{project.id}/settings/delete")
          |> follow_redirect(conn, ~p"/projects/#{project.id}/settings")

        assert html =~ "You are not authorize to perform this action"
      end)
    end

    test "allows a superuser to schedule projects for deletion in the projects list",
         %{
           conn: conn,
           project: project
         } do
      {:ok, index_live, html} =
        live(conn, Routes.project_index_path(conn, :index))

      assert html =~ "Projects"

      {:ok, form_live, _} =
        index_live
        |> element("#delete-#{project.id}", "Delete")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.project_index_path(conn, :delete, project)
        )

      assert form_live
             |> form("#scheduled_deletion_form",
               project: %{name_confirmation: "invalid name"}
             )
             |> render_change() =~
               "Enter the project name to confirm it&#39;s deletion"

      {:ok, _index_live, html} =
        form_live
        |> form("#scheduled_deletion_form",
          project: %{
            name_confirmation: project.name
          }
        )
        |> render_submit()
        |> follow_redirect(conn, Routes.project_index_path(conn, :index))

      assert html =~ "Project scheduled for deletion"
    end

    test "allows superuser to click cancel for closing user deletion modal", %{
      conn: conn,
      project: project
    } do
      {:ok, index_live, html} =
        live(conn, Routes.project_index_path(conn, :index))

      assert html =~ "Projects"

      {:ok, form_live, _} =
        index_live
        |> element("#delete-#{project.id}", "Delete")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.project_index_path(conn, :delete, project)
        )

      {:ok, index_live, _html} =
        form_live
        |> element("button", "Cancel")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.project_index_path(conn, :index)
        )

      assert has_element?(index_live, "#project-#{project.id}")
    end

    test "allows a superuser to cancel scheduled deletion on a project", %{
      conn: conn
    } do
      project =
        project_fixture(scheduled_deletion: Timex.now() |> Timex.shift(days: 7))

      {:ok, index_live, _html} =
        live(conn, Routes.project_index_path(conn, :index))

      assert index_live
             |> element("#project-#{project.id} a", "Cancel deletion")
             |> render_click() =~ "Project deletion canceled"
    end

    test "allows a superuser to perform delete now action on a scheduled for deletion project",
         %{
           conn: conn
         } do
      project =
        project_fixture(scheduled_deletion: Timex.now() |> Timex.shift(days: 7))

      {:ok, index_live, _html} =
        live(conn, Routes.project_index_path(conn, :index))

      {:ok, form_live, _html} =
        index_live
        |> element("#project-#{project.id} a", "Delete now")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.project_index_path(conn, :delete, project)
        )

      {:ok, index_live, html} =
        form_live
        |> form("#scheduled_deletion_form",
          project: %{
            name_confirmation: project.name
          }
        )
        |> render_submit()
        |> follow_redirect(conn, Routes.project_index_path(conn, :index))

      assert html =~ "Project deleted"

      refute index_live |> element("project-#{project.id}") |> has_element?()
    end

    test "Edits a project", %{conn: conn, user: superuser} do
      # the alphabetical order here is important. In the page, the users are ordered alphabeticaly
      superuser
      |> Ecto.Changeset.change(%{first_name: "1"})
      |> Lightning.Repo.update!()

      user1 = insert(:user, first_name: "2")
      user2 = insert(:user, first_name: "3")
      project = insert(:project)

      {:ok, view, _html} = live(conn, ~p"/settings/projects/#{project.id}")

      # notice the order. We've skipped `0` who's the superadmin. Changing this order will fail the test
      view
      |> form("#project-users-form",
        project: %{
          "project_users" => %{
            "1" => %{"user_id" => user1.id, "role" => "editor"},
            "2" => %{"user_id" => user2.id, "role" => "viewer"}
          }
        }
      )
      |> render_submit()

      assert_patch(view, ~p"/settings/projects")
      assert render(view) =~ "Project updated successfully"

      updated_project =
        Lightning.Repo.preload(project, [:project_users], force: true)

      assert Enum.count(updated_project.project_users) == 2

      for p_user <- updated_project.project_users do
        assert p_user.user_id in [user1.id, user2.id]
        refute p_user.user_id == superuser.id
      end
    end
  end

  describe "projects picker dropdown" do
    setup :register_and_log_in_user

    test "Access project settings page", %{conn: conn, user: user} do
      another_user = insert(:user)

      project_1 =
        insert(:project,
          name: "project-1",
          project_users: [%{user_id: user.id}]
        )

      project_2 =
        insert(:project,
          name: "project-2",
          project_users: [%{user_id: user.id}]
        )

      project_3 =
        insert(:project,
          name: "project-3",
          project_users: [%{user_id: another_user.id}]
        )

      {:ok, view, _html} = live(conn, ~p"/projects/#{project_1}/w")

      refute view
             |> element(
               ~s{a[href="#{~p"/projects/#{project_1.id}/w"}"]},
               ~r/project-1/
             )
             |> has_element?()

      assert view
             |> element(
               ~s{a[href="#{~p"/projects/#{project_2.id}/w"}"]},
               ~r/project-2/
             )
             |> has_element?()

      refute view
             |> element(
               ~s{a[href="#{~p"/projects/#{project_3.id}/w"}"]},
               ~r/project-3/
             )
             |> has_element?()

      {:ok, view, html} = live(conn, ~p"/projects/#{project_1}/w")

      assert html =~ project_1.name
      assert view |> element("button", "#{project_1.name}") |> has_element?()

      assert view
             |> element("a[href='#{~p"/projects/#{project_2.id}/w"}']")
             |> has_element?()

      refute view
             |> element("a[href='#{~p"/projects/#{project_3.id}/w"}']")
             |> has_element?()

      {:ok, view, html} = live(conn, ~p"/projects/#{project_2}/w")

      assert html =~ project_2.name
      assert view |> element("button", "#{project_2.name}") |> has_element?()

      assert view
             |> element("a[href='#{~p"/projects/#{project_1.id}/w"}']")
             |> has_element?()

      refute view
             |> element("a[href='#{~p"/projects/#{project_3.id}/w"}']")
             |> has_element?()

      assert live(conn, ~p"/projects/#{project_3}/w") ==
               {:error, {:redirect, %{flash: %{"nav" => :not_found}, to: "/"}}}
    end
  end

  describe "projects settings page" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    setup do
      Tesla.Mock.mock_global(fn env ->
        case env.url do
          "https://api.github.com/app/installations/bad-id/access_tokens" ->
            %Tesla.Env{status: 404, body: %{}}

          "https://api.github.com/app/installations/wrong-cert/access_tokens" ->
            %Tesla.Env{status: 401, body: %{}}

          "https://api.github.com/app/installations/some-id/access_tokens" ->
            %Tesla.Env{status: 201, body: %{"token" => "some-token"}}

          "https://api.github.com/installation/repositories" ->
            %Tesla.Env{
              status: 200,
              body: %{"repositories" => [%{"full_name" => "org/repo"}]}
            }

          "https://api.github.com/repos/some/repo/branches" ->
            %Tesla.Env{status: 200, body: [%{"name" => "master"}]}

          "https://api.github.com/repos/some/repo/dispatches" ->
            %Tesla.Env{status: 204}
        end
      end)

      :ok
    end

    test "access project settings page", %{conn: conn, project: project} do
      {:ok, _view, html} =
        live(
          conn,
          Routes.project_project_settings_path(conn, :index, project.id)
        )

      assert html =~ "Project settings"
    end

    @tag role: :admin
    test "project admin can view github sync page", %{
      conn: conn,
      project: project
    } do
      put_temporary_env(:lightning, :github_app,
        cert: @cert,
        app_id: "111111",
        app_name: "test-github"
      )

      {:ok, _view, html} =
        live(
          conn,
          Routes.project_project_settings_path(conn, :index, project.id)
        )

      assert html =~ "Install Github App to get started"
    end

    @tag role: :admin
    test "project admin can view github setup", %{
      conn: conn,
      project: project,
      user: user
    } do
      put_temporary_env(:lightning, :github_app,
        cert: @cert,
        app_id: "111111",
        app_name: "test-github"
      )

      insert(:project_repo_connection, %{
        project: project,
        user: user,
        repo: nil,
        branch: nil
      })

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      assert html =~ "Repository"
    end

    @tag role: :admin
    test "Flashes an error when APP ID is wrong", %{
      conn: conn,
      project: project,
      user: user
    } do
      put_temporary_env(:lightning, :github_app,
        cert: @cert,
        app_id: "111111",
        app_name: "test-github"
      )

      insert(:project_repo_connection, %{
        project: project,
        user: user,
        repo: nil,
        branch: nil,
        github_installation_id: "bad-id"
      })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      dynamically_absorb_delay(fn ->
        render(view) =~ "ID has not been properly"
      end)

      assert render(view) =~
               "Sorry, it seems that the GitHub App ID has not been properly configured for this instance of Lightning. Please contact the instance administrator"
    end

    @tag role: :admin
    test "Flashes an error when PEM CERT is corrupt", %{
      conn: conn,
      project: project,
      user: user
    } do
      put_temporary_env(:lightning, :github_app,
        cert: @cert,
        app_id: "111111",
        app_name: "test-github"
      )

      insert(:project_repo_connection, %{
        project: project,
        user: user,
        repo: "some-repo",
        branch: "some-branch",
        github_installation_id: "wrong-cert"
      })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      dynamically_absorb_delay(fn ->
        render(view) =~ "cert has not been properly"
      end)

      assert render(view) =~
               "Sorry, it seems that the GitHub cert has not been properly configured for this instance of Lightning. Please contact the instance administrator"
    end

    @tag role: :admin
    test "can view github sync", %{
      conn: conn,
      project: project,
      user: user
    } do
      put_temporary_env(:lightning, :github_app,
        cert: @cert,
        app_id: "111111",
        app_name: "test-github"
      )

      repository = "some-repo"

      insert(:project_repo_connection, %{
        project: project,
        user: user,
        repo: repository,
        branch: "some-branch"
      })

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      assert html =~ repository
    end

    @tag role: :admin
    test "can install github app", %{
      conn: conn,
      project: project
    } do
      put_temporary_env(:lightning, :github_app,
        cert: @cert,
        app_id: "111111",
        app_name: "test-github"
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      assert view |> render_click("install_app", %{})
    end

    @tag role: :admin
    test "Flashes an error when APP Name is missing during installation", %{
      conn: conn,
      project: project
    } do
      put_temporary_env(:lightning, :github_app,
        cert: @cert,
        app_id: nil,
        app_name: nil
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      assert view |> render_click("install_app", %{}) =~
               "Sorry, it seems that the GitHub App Name has not been properly configured for this instance of Lighting. Please contact the instance administrator"
    end

    @tag role: :admin
    test "can reinstall github app", %{
      conn: conn,
      project: project
    } do
      put_temporary_env(:lightning, :github_app,
        cert: @cert,
        app_id: "111111",
        app_name: "test-github"
      )

      insert(:project_repo_connection, %{project_id: project.id, project: nil})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      assert view |> render_click("reinstall_app", %{})
    end

    @tag role: :admin
    test "Flashes an error when APP Name is missing during reinstallation", %{
      conn: conn,
      project: project
    } do
      put_temporary_env(:lightning, :github_app,
        cert: @cert,
        app_id: nil,
        app_name: nil
      )

      insert(:project_repo_connection, %{project_id: project.id, project: nil})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      assert view |> render_click("reinstall_app", %{}) =~
               "Sorry, it seems that the GitHub App Name has not been properly configured for this instance of Lighting. Please contact the instance administrator"
    end

    @tag role: :admin
    test "can delete github repo connection", %{
      conn: conn,
      project: project
    } do
      put_temporary_env(:lightning, :github_app,
        cert: @cert,
        app_id: "111111",
        app_name: "test-github"
      )

      insert(:project_repo_connection, %{project_id: project.id, project: nil})

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      assert view |> render_click("delete_repo_connection", %{}) =~
               "Install Github"
    end

    @tag role: :admin
    test "can save github repo connection", %{
      conn: conn,
      project: project
    } do
      put_temporary_env(:lightning, :github_app,
        cert: @cert,
        app_id: "111111",
        app_name: "test-github"
      )

      insert(:project_repo_connection, %{
        project_id: project.id,
        project: nil,
        branch: nil,
        repo: nil
      })

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      assert view
             |> render_click("save_repo", %{branch: "b", repo: "r"}) =~
               "Repository:\n                            <a href=\"https://www.github.com/r\" target=\"_blank\" class=\"hover:underline text-primary-600\">\nr"
    end

    @tag role: :admin
    test "project admin can view project collaboration page", %{
      conn: conn,
      project: project
    } do
      project_user =
        Lightning.Projects.get_project_users!(project.id)
        |> List.first()

      {:ok, _view, html} =
        live(
          conn,
          Routes.project_project_settings_path(conn, :index, project.id)
        )

      assert html =~ "Collaborator"
      assert html =~ "Role"

      assert html =~
               "#{project_user.user.first_name} #{project_user.user.last_name}"
               |> Phoenix.HTML.Safe.to_iodata()
               |> to_string()

      assert html =~ project_user.role |> Atom.to_string() |> String.capitalize()

      assert html =~
               "#{project_user.user.first_name} #{project_user.user.last_name}"
    end

    test "project admin can view project credentials page",
         %{
           conn: conn,
           user: user
         } do
      {:ok, project} =
        Lightning.Projects.create_project(%{
          name: "project-1",
          project_users: [%{user_id: user.id, role: :admin}]
        })

      {:ok, credential} =
        Lightning.Credentials.create_credential(%{
          body: %{},
          name: "some name",
          user_id: user.id,
          schema: "raw",
          project_credentials: [
            %{project_id: project.id}
          ]
        })

      credential = Lightning.Repo.preload(credential, :user)

      {:ok, _view, html} =
        live(
          conn,
          Routes.project_project_settings_path(conn, :index, project.id) <>
            "#credentials"
        )

      assert html =~ "Name"
      assert html =~ "Type"
      assert html =~ "Owner"
      assert html =~ "Production"

      assert html =~
               credential.name |> Phoenix.HTML.Safe.to_iodata() |> to_string()

      assert html =~ credential.schema
      assert html =~ credential.name
      assert html =~ credential.user.email
    end

    test "authorized project users can create new credentials in the project credentials page",
         %{
           conn: conn,
           user: user
         } do
      [:admin, :editor]
      |> Enum.each(fn role ->
        {:ok, project} =
          Lightning.Projects.create_project(%{
            name: "project-1",
            project_users: [%{user_id: user.id, role: role}]
          })

        {:ok, view, html} =
          live(
            conn,
            Routes.project_project_settings_path(conn, :index, project.id) <>
              "#credentials"
          )

        credential_name = "My Credential"

        refute html =~ credential_name

        view |> select_credential_type("http")
        view |> click_continue()

        assert view
               |> fill_credential(%{
                 name: credential_name,
                 body: %{
                   username: "foo",
                   password: "bar",
                   baseUrl: "http://localhost"
                 }
               })

        {:ok, _view, html} =
          view
          |> click_save()
          |> follow_redirect(
            conn,
            ~p"/projects/#{project}/settings#credentials"
          )

        assert html =~ credential_name
      end)
    end

    test "non authorized project users can't create new credentials in the project credentials page",
         %{
           conn: conn,
           user: user
         } do
      {:ok, project} =
        Lightning.Projects.create_project(%{
          name: "project-1",
          project_users: [%{user_id: user.id, role: :viewer}]
        })

      {:ok, view, html} =
        live(
          conn,
          Routes.project_project_settings_path(conn, :index, project.id) <>
            "#credentials"
        )

      credential_name = "My Credential"

      refute html =~ credential_name

      view |> select_credential_type("http")
      view |> click_continue()

      assert view
             |> fill_credential(%{
               name: credential_name,
               body: %{
                 username: "foo",
                 password: "bar",
                 baseUrl: "http://localhost"
               }
             })

      {:ok, _view, html} =
        view
        |> click_save()
        |> follow_redirect(
          conn,
          ~p"/projects/#{project}/settings#credentials"
        )

      assert html =~ "You are not authorized to perform this action."
      refute html =~ credential_name
    end

    test "click on cancel button to close credential creation modal", %{
      conn: conn,
      user: user
    } do
      {:ok, project} =
        Lightning.Projects.create_project(%{
          name: "project-1",
          project_users: [%{user_id: user.id, role: :viewer}]
        })

      credential_name = "My Credential"

      {:ok, view, html} =
        live(
          conn,
          Routes.project_project_settings_path(conn, :index, project.id) <>
            "#credentials"
        )

      refute html =~ credential_name

      {:ok, _view, html} =
        view
        |> element("button", "Cancel")
        |> render_click()
        |> follow_redirect(
          conn,
          ~p"/projects/#{project}/settings#credentials"
        )

      refute html =~ credential_name
    end

    test "project admin can view project security page",
         %{
           conn: conn,
           user: user
         } do
      project = insert(:project, project_users: [%{user: user, role: :admin}])

      {:ok, _view, html} =
        live(
          conn,
          Routes.project_project_settings_path(conn, :index, project.id) <>
            "#security"
        )

      assert html =~ "Multi-Factor Authentication"
    end

    test "project admin can't edit project name and description with invalid data",
         %{
           conn: conn,
           user: user
         } do
      {:ok, project} =
        Lightning.Projects.create_project(%{
          name: "project-1",
          project_users: [%{user_id: user.id, role: :admin}]
        })

      {:ok, view, html} =
        live(
          conn,
          Routes.project_project_settings_path(conn, :index, project.id)
        )

      assert html =~ "Project settings"

      invalid_project_name = %{
        name: "some name"
      }

      invalid_project_description = %{
        description:
          Enum.map(1..250, fn _ ->
            Enum.random(Enum.to_list(?a..?z) ++ Enum.to_list(?0..?9))
          end)
          |> to_string()
      }

      assert view
             |> form("#project-settings-form", project: invalid_project_name)
             |> render_change() =~ "has invalid format"

      assert view
             |> form("#project-settings-form",
               project: invalid_project_description
             )
             |> render_change() =~ "should be at most 240 character(s)"

      assert view |> has_element?("button[disabled][type=submit]")
    end

    test "project admin can edit project name and description with valid data",
         %{
           conn: conn,
           user: user
         } do
      {:ok, project} =
        Lightning.Projects.create_project(%{
          name: "project-1",
          project_users: [%{user_id: user.id, role: :admin}]
        })

      {:ok, view, html} =
        live(
          conn,
          Routes.project_project_settings_path(conn, :index, project.id)
        )

      assert html =~ "Project settings"

      valid_project_attrs = %{
        name: "somename",
        description: "some description"
      }

      assert view
             |> form("#project-settings-form", project: valid_project_attrs)
             |> render_submit() =~ "Project updated successfully"
    end

    test "only users with admin level on project can edit project details", %{
      conn: conn,
      user: user
    } do
      {:ok, project} =
        Lightning.Projects.create_project(%{
          name: "project-1",
          project_users: [%{user_id: user.id, role: :viewer}]
        })

      {:ok, view, html} =
        live(
          conn,
          Routes.project_project_settings_path(conn, :index, project.id)
        )

      assert html =~ "Project settings"

      assert view
             |> has_element?(
               "input[disabled='disabled'][id='project-settings-form_name']"
             )

      assert view
             |> has_element?(
               "textarea[disabled='disabled'][id='project-settings-form_description']"
             )

      assert view |> has_element?("button[disabled][type=submit]")

      assert view |> render_click("save", %{"project" => %{}}) =~
               "You are not authorized to perform this action."
    end

    test "project members can edit their own digest frequency and failure alert settings",
         %{conn: conn, user: authenticated_user} do
      unauthenticated_user = user_fixture(first_name: "Bob")

      {:ok, project} =
        Lightning.Projects.create_project(%{
          name: "project-1",
          project_users: [
            %{
              user_id: authenticated_user.id,
              digest: :never,
              failure_alert: false
            },
            %{
              user_id: unauthenticated_user.id,
              digest: :daily,
              failure_alert: true
            }
          ]
        })

      {:ok, view, _html} =
        live(
          conn,
          Routes.project_project_settings_path(conn, :index, project.id) <>
            "#collaboration"
        )

      authenticated_user_project_user =
        project.project_users
        |> Enum.find(fn pu -> pu.user_id == authenticated_user.id end)

      unauthenticated_user_project_user =
        project.project_users
        |> Enum.find(fn pu -> pu.user_id == unauthenticated_user.id end)

      assert_raise ArgumentError, fn ->
        view
        |> element("#project_user-#{unauthenticated_user_project_user.id}")
        |> render_click()
      end

      form_id = "#failure-alert-#{authenticated_user_project_user.id}"

      assert view |> has_element?("#{form_id} option[selected]", "Disabled")

      refute view
             |> form(form_id, %{"failure_alert" => "false"})
             |> render_change() =~ "Project user updated successfuly"

      assert view
             |> form(form_id, %{"failure_alert" => "true"})
             |> render_change() =~ "Project user updated successfuly"

      assert view
             |> has_element?(
               "#failure-alert-#{authenticated_user_project_user.id} option[selected]",
               "Enabled"
             )

      view
      |> element("#flash")
      |> render_hook("lv:clear-flash")

      form_id = "#digest-#{authenticated_user_project_user.id}"

      assert view |> has_element?("#{form_id} option[selected]", "Never")

      refute view
             |> element(form_id)
             |> render_change(%{"digest" => "never"}) =~
               "Project user updated successfuly"

      assert view
             |> form(form_id, %{"digest" => "daily"})
             |> render_change() =~ "Project user updated successfuly"

      assert view |> has_element?("#{form_id} option[selected]", "Daily")
    end

    test "project admin can toggle MFA requirement",
         %{
           conn: conn,
           user: user
         } do
      project =
        insert(:project,
          project_users: [%{user: user, role: :admin}]
        )

      {:ok, view, html} =
        live(
          conn,
          Routes.project_project_settings_path(conn, :index, project.id)
        )

      assert html =~ "Project settings"

      assert view
             |> element("#toggle-mfa-switch")
             |> render_click() =~ "Project MFA requirement updated successfully"
    end

    test "only users with admin level role can toggle MFA requirement", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project,
          project_users: [%{user: user, role: :admin}]
        )

      ~w(editor viewer)a
      |> Enum.each(fn role ->
        {conn, _user} = setup_project_user(conn, project, role)

        {:ok, view, html} =
          live(
            conn,
            Routes.project_project_settings_path(conn, :index, project.id)
          )

        assert html =~ "Project settings"

        refute has_element?(view, "#toggle-mfa-switch")

        assert render_click(view, "toggle-mfa") =~
                 "You are not authorized to perform this action."
      end)
    end

    test "only users with MFA enabled can access settings for a project with MFA requirement",
         %{
           conn: conn
         } do
      user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))
      conn = log_in_user(conn, user)

      project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: user, role: :admin}]
        )

      {:ok, _view, html} =
        live(
          conn,
          Routes.project_project_settings_path(conn, :index, project.id)
        )

      assert html =~ "Project settings"

      ~w(editor viewer admin)a
      |> Enum.each(fn role ->
        {conn, _user} = setup_project_user(conn, project, role)

        assert {:error, {:redirect, %{to: "/mfa_required"}}} =
                 live(
                   conn,
                   Routes.project_project_settings_path(conn, :index, project.id)
                 )
      end)
    end

    test "all project users can see the project webhook auth methods", %{
      conn: conn
    } do
      project = insert(:project)
      auth_methods = insert_list(4, :webhook_auth_method, project: project)

      for project_user <-
            Enum.map([:editor, :admin, :owner, :viewer], fn role ->
              insert(:project_user,
                role: role,
                project: project,
                user: build(:user)
              )
            end) do
        conn = log_in_user(conn, project_user.user)

        {:ok, _view, html} =
          live(
            conn,
            Routes.project_project_settings_path(conn, :index, project.id)
          )

        for auth_method <- auth_methods do
          assert html =~ auth_method.name
        end
      end
    end

    test "authorized project users can add a new project webhook auth method",
         %{
           conn: conn
         } do
      project = insert(:project)

      settings_path =
        Routes.project_project_settings_path(conn, :index, project.id)

      for project_user <-
            Enum.map([:editor, :admin, :owner], fn role ->
              insert(:project_user,
                role: role,
                project: project,
                user: build(:user)
              )
            end) do
        conn = log_in_user(conn, project_user.user)

        {:ok, view, _html} =
          live(
            conn,
            settings_path
          )

        assert view |> element("button#add_new_auth_method") |> has_element?()

        refute view
               |> element("button#add_new_auth_method:disabled")
               |> has_element?()

        modal_id = "new_auth_method_modal"

        assert view |> element("##{modal_id}") |> has_element?()

        view
        |> form("#choose_auth_type_form_#{modal_id}",
          webhook_auth_method: %{auth_type: "basic"}
        )
        |> render_submit() =~ "Create credential"

        refute view
               |> element("form#choose_auth_type_form_#{modal_id}")
               |> has_element?()

        credential_name = "#{project_user.role}credentialname"

        refute render(view) =~ credential_name

        view
        |> form("#form_#{modal_id}_new_webhook_auth_method",
          webhook_auth_method: %{
            name: credential_name,
            username: "testusername",
            password: "testpassword123"
          }
        )
        |> render_submit()

        flash =
          assert_redirect(
            view,
            settings_path <> "#webhook_security"
          )

        assert flash["info"] == "Webhook auth method created successfully"

        {:ok, _view, html} =
          live(
            conn,
            settings_path
          )

        assert html =~ credential_name
      end
    end

    test "project viewers cannot add a new project webhook auth method", %{
      conn: conn
    } do
      project = insert(:project)

      project_user =
        insert(:project_user,
          role: :viewer,
          project: project,
          user: build(:user)
        )

      conn = log_in_user(conn, project_user.user)

      {:ok, view, _html} =
        live(
          conn,
          Routes.project_project_settings_path(conn, :index, project.id)
        )

      assert view
             |> element("button#add_new_auth_method:disabled")
             |> has_element?()

      refute view |> element("#new_auth_method_modal") |> has_element?()
    end

    test "authorized project users can add edit a project webhook auth method",
         %{
           conn: conn
         } do
      project = insert(:project)

      auth_method =
        insert(:webhook_auth_method,
          project: project,
          auth_type: :basic
        )

      settings_path =
        Routes.project_project_settings_path(conn, :index, project.id)

      for project_user <-
            Enum.map([:editor, :admin, :owner], fn role ->
              insert(:project_user,
                role: role,
                project: project,
                user: build(:user)
              )
            end) do
        conn = log_in_user(conn, project_user.user)

        {:ok, view, _html} =
          live(
            conn,
            settings_path
          )

        assert view
               |> element("a#edit_auth_method_link_#{auth_method.id}")
               |> has_element?()

        modal_id = "edit_auth_#{auth_method.id}_modal"

        assert view |> element("##{modal_id}") |> has_element?()

        credential_name = "#{project_user.role}credentialname"

        refute render(view) =~ credential_name

        view
        |> form("#form_#{modal_id}_#{auth_method.id}",
          webhook_auth_method: %{name: credential_name}
        )
        |> render_submit()

        flash =
          assert_redirect(
            view,
            settings_path <> "#webhook_security"
          )

        assert flash["info"] == "Webhook auth method updated successfully"

        {:ok, _view, html} =
          live(
            conn,
            settings_path
          )

        assert html =~ credential_name
      end
    end

    test "project viewers cannot edit a project webhook auth method", %{
      conn: conn
    } do
      project = insert(:project)

      auth_method =
        insert(:webhook_auth_method,
          project: project,
          auth_type: :basic
        )

      project_user =
        insert(:project_user,
          role: :viewer,
          project: project,
          user: build(:user)
        )

      conn = log_in_user(conn, project_user.user)

      {:ok, view, _html} =
        live(
          conn,
          Routes.project_project_settings_path(conn, :index, project.id)
        )

      assert view
             |> element("a#edit_auth_method_link_#{auth_method.id}")
             |> has_element?()

      refute view
             |> element("#edit_auth_#{auth_method.id}_modal")
             |> has_element?()
    end

    test "password is required before displaying the API KEY of a project webhook auth method",
         %{conn: conn} do
      project = insert(:project)

      auth_method =
        insert(:webhook_auth_method,
          project: project,
          auth_type: :api,
          api_key: "someverystrongapikey1234",
          username: nil,
          password: nil
        )

      project_user =
        insert(:project_user,
          role: :editor,
          project: project,
          user: build(:user)
        )

      conn = log_in_user(conn, project_user.user)

      {:ok, view, _html} =
        live(
          conn,
          Routes.project_project_settings_path(conn, :index, project.id)
        )

      assert view
             |> element("a#edit_auth_method_link_#{auth_method.id}")
             |> has_element?()

      modal_id = "edit_auth_#{auth_method.id}_modal"

      assert view |> element("##{modal_id}") |> has_element?()

      form_id = "form_#{modal_id}_#{auth_method.id}"

      assert view |> has_element?("##{form_id}_api_key_action_button", "Show")
      refute view |> has_element?("##{form_id}_api_key_action_button", "Copy")
      # API KEY not in DOM
      refute render(view) =~ auth_method.api_key

      refute view |> has_element?("#reauthentication-form")

      view |> element("##{form_id}_api_key_action_button") |> render_click()

      assert view |> has_element?("#reauthentication-form")

      # test wrong password
      refute render(view) =~ "Invalid! Please try again"

      view
      |> form("#reauthentication-form",
        user: %{password: "wrongpass"}
      )
      |> render_submit()

      assert render(view) =~ "Invalid! Please try again"
      # form still exists
      assert view |> has_element?("#reauthentication-form")

      # correct password
      view
      |> form("#reauthentication-form",
        user: %{password: project_user.user.password}
      )
      |> render_submit()

      refute render(view) =~ "Invalid! Please try again"
      refute view |> has_element?("#reauthentication-form")

      refute view |> has_element?("##{form_id}_api_key_action_button", "Show")
      assert view |> has_element?("##{form_id}_api_key_action_button", "Copy")
      assert render(view) =~ auth_method.api_key
    end

    test "password is required before displaying the password of a project webhook auth method",
         %{conn: conn} do
      project = insert(:project)

      auth_method =
        insert(:webhook_auth_method,
          project: project,
          auth_type: :basic,
          api_key: nil,
          username: "testusername",
          password: "someveryverystrongpassword1234"
        )

      project_user =
        insert(:project_user,
          role: :editor,
          project: project,
          user: build(:user)
        )

      conn = log_in_user(conn, project_user.user)

      {:ok, view, _html} =
        live(
          conn,
          Routes.project_project_settings_path(conn, :index, project.id)
        )

      assert view
             |> element("a#edit_auth_method_link_#{auth_method.id}")
             |> has_element?()

      modal_id = "edit_auth_#{auth_method.id}_modal"

      assert view |> element("##{modal_id}") |> has_element?()

      form_id = "form_#{modal_id}_#{auth_method.id}"

      assert view |> has_element?("##{form_id}_password_action_button", "Show")
      refute view |> has_element?("##{form_id}_password_action_button", "Copy")
      # password not in DOM
      refute render(view) =~ auth_method.password

      refute view |> has_element?("#reauthentication-form")

      view |> element("##{form_id}_password_action_button") |> render_click()

      assert view |> has_element?("#reauthentication-form")

      # test wrong password
      refute render(view) =~ "Invalid! Please try again"

      view
      |> form("#reauthentication-form",
        user: %{password: "wrongpass"}
      )
      |> render_submit()

      assert render(view) =~ "Invalid! Please try again"
      # form still exists
      assert view |> has_element?("#reauthentication-form")

      # correct password
      view
      |> form("#reauthentication-form",
        user: %{password: project_user.user.password}
      )
      |> render_submit()

      refute render(view) =~ "Invalid! Please try again"
      refute view |> has_element?("#reauthentication-form")

      refute view |> has_element?("##{form_id}_password_action_button", "Show")
      assert view |> has_element?("##{form_id}_password_action_button", "Copy")
      assert render(view) =~ auth_method.password
    end
  end

  test "authorized project users can delete a project webhook auth method",
       %{conn: conn} do
    project = insert(:project)

    for role <- [:owner, :admin, :editor] do
      auth_method =
        insert(:webhook_auth_method,
          project: project,
          auth_type: :basic
        )

      project_user =
        insert(:project_user,
          role: role,
          project: project,
          user: build(:user)
        )

      settings_path =
        Routes.project_project_settings_path(conn, :index, project.id)

      conn = log_in_user(conn, project_user.user)

      {:ok, view, _html} =
        live(
          conn,
          settings_path
        )

      assert view
             |> element("a#delete_auth_method_link_#{auth_method.id}")
             |> has_element?()

      modal_id = "delete_auth_#{auth_method.id}_modal"

      view
      |> form("#delete_auth_method_#{modal_id}_#{auth_method.id}",
        delete_confirmation_changeset: %{confirmation: "DELETE"}
      )
      |> render_submit()

      flash =
        assert_redirect(
          view,
          settings_path <> "#webhook_security"
        )

      assert flash["info"] ==
               "Your Webhook Authentication method has been deleted."
    end
  end
end
