defmodule LightningWeb.ProjectLiveTest do
  use LightningWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Lightning.ProjectsFixtures
  import Lightning.AccountsFixtures
  import Lightning.Factories
  import LightningWeb.CredentialLiveHelpers

  import Lightning.ApplicationHelpers,
    only: [put_temporary_env: 3]

  import Mox

  alias Lightning.Name
  alias Lightning.Projects
  alias Lightning.Repo

  setup :stub_usage_limiter_ok

  @public_key """
  -----BEGIN PUBLIC KEY-----
  MIIBITANBgkqhkiG9w0BAQEFAAOCAQ4AMIIBCQKCAQB1ZtDWukVcNcnMLXUsi8Mw
  6WK5pri2sXuNZpT8lMf2fXcEmsJdvEhP3DASDykLyusJp9fV17BzM8JmzC9zNMIc
  OdLhwsl8rKoVrwYjFXXRvPn+5QzpwT/JprymE54lbFJ/lMefkfkJcaSl5khyHNpl
  rGH5g7+zGiMfs+kXItjhW41xEsy552kff3Wq/33R2sdizIDDJjEC/6J942jLpMJe
  HgYaZXZRKsc9b6CSjZS/nVh0OA/bE4deNrSDesyytcMmN3/+l9XYbQqJOgVs/sWl
  TNPEVQabXsPxzIwVGcH+iDRhV31nqe6YoQ/gvNTRnESnC1KRrTB7eCwZP0kHLshX
  AgMBAAE=
  -----END PUBLIC KEY-----
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

    test "renders a banner when run limit has been reached", %{
      conn: conn,
      project: %{id: project_id}
    } do
      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :check_limits,
        &Lightning.Extensions.StubUsageLimiter.check_limits/1
      )

      {:ok, _live, html} =
        live(conn, ~p"/projects/#{project_id}/settings")

      assert html =~ "Some banner text"
    end

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
      user = insert(:user, first_name: "1st", last_name: "user")

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

      user_index = find_user_index_in_list(index_live, user)

      index_live
      |> form("#project-users-form",
        project: %{
          "project_users" => %{
            user_index => %{"user_id" => user.id, "role" => "editor"}
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
      user1 = insert(:user, first_name: "2")
      user2 = insert(:user, first_name: "3")
      project = insert(:project)

      {:ok, view, _html} = live(conn, ~p"/settings/projects/#{project.id}")

      view
      |> form("#project-users-form",
        project: %{
          "project_users" => %{
            find_user_index_in_list(view, user1) => %{
              "user_id" => user1.id,
              "role" => "editor"
            },
            find_user_index_in_list(view, user2) => %{
              "user_id" => user2.id,
              "role" => "viewer"
            }
          }
        }
      )
      |> render_submit()

      assert_patch(view, ~p"/settings/projects")
      assert render(view) =~ "Project updated successfully"

      updated_project =
        Repo.preload(project, [:project_users], force: true)

      assert Enum.count(updated_project.project_users) == 2

      for p_user <- updated_project.project_users do
        assert p_user.user_id in [user1.id, user2.id]
        refute p_user.user_id == superuser.id
      end
    end
  end

  describe "download exported project" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    setup %{project: project} do
      {:ok, workflow: insert(:simple_workflow, project: project)}
    end

    test "having edge with condition_type=always", %{
      conn: conn,
      project: project,
      workflow: %{edges: [edge]}
    } do
      edge
      |> Ecto.Changeset.change(%{condition_type: :always})
      |> Lightning.Repo.update!()

      response = get(conn, "/download/yaml?id=#{project.id}") |> response(200)

      assert response =~ ~S[condition_type: always]
    end

    test "having edge with condition_type=on_job_success", %{
      conn: conn,
      project: project,
      workflow: %{edges: [edge]}
    } do
      edge
      |> Ecto.Changeset.change(%{condition_type: :on_job_success})
      |> Lightning.Repo.update!()

      response = get(conn, "/download/yaml?id=#{project.id}") |> response(200)

      assert response =~ ~S[condition_type: on_job_success]
    end

    test "having edge with condition_type=on_job_failure", %{
      conn: conn,
      project: project,
      workflow: %{edges: [edge]}
    } do
      edge
      |> Ecto.Changeset.change(%{condition_type: :on_job_failure})
      |> Lightning.Repo.update!()

      response = get(conn, "/download/yaml?id=#{project.id}") |> response(200)

      assert response =~ ~S[condition_type: on_job_failure]
    end

    test "having edge with condition_type=js_expression", %{
      conn: conn,
      project: project,
      workflow: %{edges: [edge]}
    } do
      edge
      |> Ecto.Changeset.change(%{
        condition_type: :js_expression,
        condition_label: "not underaged",
        condition_expression: "state.data.age > 18"
      })
      |> Lightning.Repo.update!()

      response = get(conn, "/download/yaml?id=#{project.id}") |> response(200)

      assert response =~ ~S[condition_type: js_expression]
      assert response =~ ~S[condition_label: not underaged]
      assert response =~ ~S[condition_expression: state.data.age > 18]
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

      assert view
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

    test "access project settings page", %{conn: conn, project: project} do
      {:ok, _view, html} =
        live(
          conn,
          Routes.project_project_settings_path(conn, :index, project.id)
        )

      assert html =~ "Project settings"
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
        |> element("footer button", "Cancel")
        |> render_click()
        |> follow_redirect(
          conn,
          ~p"/projects/#{project}/settings#credentials"
        )

      refute html =~ credential_name
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

    test "all project users can view project security page",
         %{
           conn: conn
         } do
      project = insert(:project)

      # project editor and viewer cannot see the settings page

      [:admin, :owner, :editor, :viewer]
      |> Enum.each(fn role ->
        {conn, _user} = setup_project_user(conn, project, role)

        {:ok, view, html} =
          live(
            conn,
            Routes.project_project_settings_path(conn, :index, project.id)
          )

        assert has_element?(view, "#tab-item-security")
        assert html =~ "Multi-Factor Authentication"
      end)
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

    test "project editors and viewers cannot toggle MFA requirement", %{
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

        toggle_button = element(view, "#toggle-mfa-switch")

        assert render(toggle_button) =~
                 "You do not have permission to perform this action"

        assert render_click(toggle_button) =~
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

    test "all project users can see the project webhook auth methods" do
      project = insert(:project)
      auth_methods = insert_list(4, :webhook_auth_method, project: project)

      for conn <-
            build_project_user_conns(project, [:editor, :admin, :owner, :viewer]) do
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

    test "owners/admins can add a new project webhook auth method, editors/viewers can't",
         %{
           conn: conn
         } do
      project = insert(:project)

      settings_path =
        Routes.project_project_settings_path(conn, :index, project.id)

      for conn <- build_project_user_conns(project, [:owner, :admin]) do
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

        credential_name = Name.generate()

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

      for conn <- build_project_user_conns(project, [:editor, :viewer]) do
        {:ok, view, _html} =
          live(
            conn,
            settings_path
          )

        assert view
               |> element("button#add_new_auth_method:disabled")
               |> has_element?()

        modal_id = "new_auth_method_modal"

        refute view |> element("##{modal_id}") |> has_element?()
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

    test "owners/admins can add edit a project webhook auth method, editors/viewers can't",
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

      for conn <- build_project_user_conns(project, [:owner, :admin]) do
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

        credential_name = Name.generate()

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

      for conn <- build_project_user_conns(project, [:editor, :viewer]) do
        {:ok, view, _html} =
          live(
            conn,
            settings_path
          )

        assert view
               |> element(
                 "a#edit_auth_method_link_#{auth_method.id}.cursor-not-allowed"
               )
               |> has_element?()

        modal_id = "edit_auth_#{auth_method.id}_modal"

        refute view |> element("##{modal_id}") |> has_element?()
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
             |> element(
               "a#edit_auth_method_link_#{auth_method.id}.cursor-not-allowed"
             )
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
          role: :admin,
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
          role: :admin,
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

  test "owners and admins can delete a project webhook auth method",
       %{conn: conn} do
    project = insert(:project)

    for role <- [:owner, :admin] do
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

      assert view
             |> element("#delete_auth_method_#{modal_id}_#{auth_method.id}")
             |> has_element?()

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

    for role <- [:editor, :viewer] do
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

      refute view
             |> element("a#delete_auth_method_link_#{auth_method.id}")
             |> has_element?()

      modal_id = "delete_auth_#{auth_method.id}_modal"

      refute view
             |> element("#delete_auth_method_#{modal_id}_#{auth_method.id}")
             |> has_element?()
    end
  end

  describe "data-storage" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    @tag role: :owner
    test "project owner can view these settings", %{conn: conn, project: project} do
      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#data-storage"
        )

      assert html =~ "Input/Output Data Storage Policy"
    end

    @tag role: :admin
    test "project admin can view these settings", %{conn: conn, project: project} do
      {:ok, view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#data-storage"
        )

      assert html =~ "Input/Output Data Storage Policy"
      assert html =~ "Should OpenFn store input/output data for workflow runs?"

      # retain_all is the default
      assert ["checked"] ==
               view
               |> element("#retain_all")
               |> render()
               |> Floki.parse_fragment!()
               |> Floki.attribute("input", "checked")

      # TODO - this will be implemented in https://github.com/OpenFn/Lightning/issues/1694
      # refute ["checked"] ==
      #          view
      #          |> element("#retain_with_errors")
      #          |> render()
      #          |> Floki.parse_fragment!()
      #          |> Floki.attribute("input", "checked")

      refute ["checked"] ==
               view
               |> element("#erase_all")
               |> render()
               |> Floki.parse_fragment!()
               |> Floki.attribute("input", "checked")

      # heads up not shown for retain all
      refute html =~ "heads-up-description"

      # 3 radio buttons descriptions
      assert "Retain input/output data for all workflow runs" =
               view
               |> element(~s{label#[for="retain_all"]})
               |> render()
               |> Floki.parse_fragment!()
               |> Floki.text()
               |> String.trim()

      # TODO - this will be implemented in https://github.com/OpenFn/Lightning/issues/1694
      # assert "Only retain input/output data when a run fails" =
      #          view
      #          |> element(~s{label#[for="retain_with_errors"]})
      #          |> render()
      #          |> Floki.parse_fragment!()
      #          |> Floki.text()
      #          |> String.trim()

      assert "Never retain input/output data (zero-persistence)" =
               view
               |> element(~s{label#[for="erase_all"]})
               |> render()
               |> Floki.parse_fragment!()
               |> Floki.text()
               |> String.trim()

      # TODO - this will be implemented in https://github.com/OpenFn/Lightning/issues/1694
      # show heads up for retain_with_errors
      # view
      # |> form("#retention-settings-form",
      #   project: %{
      #     retention_policy: "retain_with_errors"
      #   }
      # )
      # |> render_change()

      # assert ["checked"] ==
      #          view
      #          |> element("#retain_with_errors")
      #          |> render()
      #          |> Floki.parse_fragment!()
      #          |> Floki.attribute("input", "checked")

      # assert "When enabled, you will no longer be able to retry workflow runs as no data will be stored." =
      #          view
      #          |> element("#heads-up-description")
      #          |> render()
      #          |> Floki.parse_fragment!()
      #          |> Floki.find("p")
      #          |> Floki.text()
      #          |> String.trim()

      # show heads up for erase all
      view
      |> form("#retention-settings-form",
        project: %{
          retention_policy: "erase_all"
        }
      )
      |> render_change()

      assert ["checked"] ==
               view
               |> element("#erase_all")
               |> render()
               |> Floki.parse_fragment!()
               |> Floki.attribute("input", "checked")

      assert "When enabled, you will no longer be able to retry workflow runs as no data will be stored." =
               view
               |> element("#heads-up-description")
               |> render()
               |> Floki.parse_fragment!()
               |> Floki.find("p")
               |> Floki.text()
               |> String.trim()
    end

    @tag role: :editor
    test "project editor does not have permission", %{
      conn: conn,
      project: project
    } do
      {:ok, view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#data-storage"
        )

      assert html =~ "Input/Output Data Storage Policy"
      assert html =~ "You cannot modify this project&#39;s data storage"

      html =
        render_submit(view, "save_retention_settings", %{
          project: %{
            retention_policy: "retain_all",
            history_retention_period: 14,
            dataclip_retention_period: 7
          }
        })

      assert html =~ "You are not authorized to perform this action."
    end

    @tag role: :viewer
    test "project viewer does not have permission", %{
      conn: conn,
      project: project
    } do
      {:ok, view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#data-storage"
        )

      assert html =~ "Input/Output Data Storage Policy"
      assert html =~ "You cannot modify this project&#39;s data storage"

      html =
        render_submit(view, "save_retention_settings", %{
          project: %{
            retention_policy: "retain_all",
            history_retention_period: 14,
            dataclip_retention_period: 7
          }
        })

      assert html =~ "You are not authorized to perform this action."
    end

    @tag role: :admin
    test "project admin can change the Input/Output Data Storage Policy", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#data-storage"
        )

      # save, navigate to other page and saved option is checked when come back
      Enum.reduce(
        # TODO - this will be implemented in https://github.com/OpenFn/Lightning/issues/1694
        # ["retain_with_errors", "erase_all", "retain_all"],
        ["erase_all", "retain_all"],
        view,
        fn policy, view ->
          view
          |> form("#retention-settings-form",
            project: %{
              retention_policy: policy
            }
          )
          |> render_change()

          assert ["checked"] ==
                   view
                   |> element("#" <> policy)
                   |> render()
                   |> Floki.parse_fragment!()
                   |> Floki.attribute("input", "checked")

          html =
            view
            |> form("#retention-settings-form")
            |> render_submit()

          assert html =~ "Project updated successfully"
          assert html =~ "Input/Output Data Storage Policy"

          assert policy ==
                   project.id
                   |> Projects.get_project!()
                   |> Map.get(:retention_policy)
                   |> Atom.to_string()

          live(conn, ~p"/projects/#{project.id}/w")

          {:ok, view, _html} =
            live(conn, ~p"/projects/#{project.id}/settings#data-storage")

          assert ["checked"] ==
                   view
                   |> element("#" <> policy)
                   |> render()
                   |> Floki.parse_fragment!()
                   |> Floki.attribute("input", "checked")

          view
        end
      )
    end

    @tag role: :admin
    test "dataclip retention period is disabled if the history period has not been set",
         %{
           conn: conn,
           project: project
         } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#data-storage"
        )

      # dataclip retention period is disabled if the history period has not been set
      assert is_nil(project.history_retention_period)

      assert has_element?(
               view,
               "#retention-settings-form_dataclip_retention_period:disabled"
             )

      view
      |> form("#retention-settings-form",
        project: %{
          history_retention_period: 7
        }
      )
      |> render_change()

      refute has_element?(
               view,
               "#retention-settings-form_dataclip_retention_period:disabled"
             )

      assert has_element?(
               view,
               "#retention-settings-form_dataclip_retention_period"
             )
    end

    @tag role: :admin
    test "dataclip retention period is disabled if the retention_policy has been set to erase_all",
         %{
           conn: conn,
           project: project
         } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#data-storage"
        )

      selected_dataclip_option =
        element(
          view,
          "#retention-settings-form_dataclip_retention_period option[selected]"
        )

      # nothing has been selected for the dataclip period
      refute has_element?(selected_dataclip_option)

      # let us enable it first by setting the history retention period
      view
      |> form("#retention-settings-form")
      |> render_change(%{
        project: %{
          history_retention_period: 14,
          dataclip_retention_period: 7
        }
      })

      refute has_element?(
               view,
               "#retention-settings-form_dataclip_retention_period:disabled"
             )

      # 7 Days has been selected for the dataclip period
      assert render(selected_dataclip_option) =~ "7 Days"

      # now let's set the retention policy to erase_all
      view
      |> form("#retention-settings-form",
        project: %{
          retention_policy: "erase_all"
        }
      )
      |> render_change()

      assert has_element?(
               view,
               "#retention-settings-form_dataclip_retention_period:disabled"
             )

      # 7 days gets cleared. Nothing is now selected
      refute has_element?(selected_dataclip_option)
    end

    @tag role: :admin
    test "project admin can change the retention periods", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#data-storage"
        )

      # let's first set the history retention period

      view
      |> form("#retention-settings-form",
        project: %{
          history_retention_period: 7
        }
      )
      |> render_change()

      # trying to set the dataclip retention period more than the history period shows error
      refute render(view) =~
               "must be less or equal to the history retention period"

      html =
        view
        |> form("#retention-settings-form",
          project: %{
            dataclip_retention_period: 14
          }
        )
        |> render_change()

      assert html =~ "must be less or equal to the history retention period"

      # the project gets updated successfully

      html =
        view
        |> form("#retention-settings-form",
          project: %{
            dataclip_retention_period: 7
          }
        )
        |> render_submit()

      assert html =~ "Project updated successfully"
    end
  end

  describe "projects settings:collaboration" do
    setup :register_and_log_in_user

    test "only authorized users can access the add collaborators modal", %{
      conn: conn
    } do
      project = insert(:project)

      for {conn, _user} <- setup_project_users(conn, project, [:viewer, :editor]) do
        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collaboration"
          )

        button = element(view, "#show_collaborators_modal_button")
        assert has_element?(button)

        # modal is not present
        refute has_element?(view, "#add_collaborators_modal")

        # try clicking the button
        assert_raise ArgumentError, ~r/is disabled/, fn ->
          render_click(button)
        end

        # send event either way
        refute render_click(view, "toggle_collaborators_modal") =~
                 "Enter the email address and role of new collaborator"

        # modal is still not present
        refute has_element?(view, "#add_collaborators_modal")
      end

      for {conn, _user} <- setup_project_users(conn, project, [:owner, :admin]) do
        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collaboration"
          )

        button = element(view, "#show_collaborators_modal_button")
        assert has_element?(button)

        # modal is not present
        refute has_element?(view, "#add_collaborators_modal")

        # try clicking the button
        assert render_click(button) =~
                 "Enter the email address and role of new collaborator"

        # modal is now present
        assert has_element?(view, "#add_collaborators_modal")
      end
    end

    test "user can add and remove inputs for adding collaborators", %{
      conn: conn
    } do
      project = insert(:project)

      for {conn, _user} <- setup_project_users(conn, project, [:owner, :admin]) do
        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collaboration"
          )

        # Open Modal
        view
        |> element("#show_collaborators_modal_button")
        |> render_click()

        modal = element(view, "#add_collaborators_modal")

        html = modal |> render() |> Floki.parse_fragment!()

        # we only have 1 email input by default
        assert Floki.find(html, "[type='text'][name$='[email]']") |> Enum.count() ==
                 1

        # we dont have any button to remove the input
        assert Floki.find(html, "button[name$='[collaborators_drop][]']")
               |> Enum.count() == 0

        # lets click to add another row
        view
        |> form("#add_collaborators_modal_form")
        |> render_change(project: %{"collaborators_sort" => [0, "new"]})

        html = modal |> render() |> Floki.parse_fragment!()

        # we now have 2 email inputs and 2 buttons to remove the inputs
        assert Floki.find(html, "[type='text'][name$='[email]']") |> Enum.count() ==
                 2

        assert Floki.find(html, "button[name$='[collaborators_drop][]']")
               |> Enum.count() == 2

        # lets click to remove the first row
        view
        |> form("#add_collaborators_modal_form")
        |> render_change(project: %{"collaborators_drop" => [0]})

        html = modal |> render() |> Floki.parse_fragment!()

        # we now have 1 email input and we dont have any button to remove the input
        assert Floki.find(html, "[type='text'][name$='[email]']") |> Enum.count() ==
                 1

        assert Floki.find(html, "button[name$='[collaborators_drop][]']")
               |> Enum.count() == 0
      end
    end

    test "adding a non existent user displays an appropriate error message", %{
      conn: conn
    } do
      project = insert(:project)

      for {conn, _user} <- setup_project_users(conn, project, [:owner, :admin]) do
        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collaboration"
          )

        # Open Modal
        view
        |> element("#show_collaborators_modal_button")
        |> render_click()

        modal = element(view, "#add_collaborators_modal")

        refute render(modal) =~ "There is no account connected this email"
        email = "nonexists@localtests.com"
        refute Lightning.Accounts.get_user_by_email(email)

        # lets submit the form

        view
        |> form("#add_collaborators_modal_form",
          project: %{
            "collaborators" => %{"0" => %{"email" => email, "role" => "editor"}}
          }
        )
        |> render_submit()

        assert render(modal) =~ "There is no account connected this email"
      end
    end

    test "adding an existing project user displays an appropriate error message",
         %{
           conn: conn
         } do
      project = insert(:project)

      for {conn, user} <- setup_project_users(conn, project, [:owner, :admin]) do
        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collaboration"
          )

        # Open Modal
        view
        |> element("#show_collaborators_modal_button")
        |> render_click()

        modal = element(view, "#add_collaborators_modal")

        refute render(modal) =~ "This account is already part of this project"

        # lets submit the form

        view
        |> form("#add_collaborators_modal_form",
          project: %{
            "collaborators" => %{
              "0" => %{"email" => user.email, "role" => "editor"}
            }
          }
        )
        |> render_submit()

        assert render(modal) =~ "This account is already part of this project"
      end
    end

    test "adding an owner project user is not allowed",
         %{
           conn: conn
         } do
      project = insert(:project)

      for {conn, _user} <- setup_project_users(conn, project, [:owner, :admin]) do
        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collaboration"
          )

        # Open Modal
        view
        |> element("#show_collaborators_modal_button")
        |> render_click()

        modal = element(view, "#add_collaborators_modal")

        refute render(modal) =~ "is invalid"

        # lets submit the form
        view
        |> form("#add_collaborators_modal_form")
        |> render_submit(
          project: %{
            "collaborators" => %{
              "0" => %{"email" => "dummy@email.com", "role" => "owner"}
            }
          }
        )

        assert render(modal) =~ "is invalid"
      end
    end

    test "user can add collaborators successfully",
         %{
           conn: conn
         } do
      project = insert(:project)

      for {conn, _user} <- setup_project_users(conn, project, [:owner, :admin]) do
        {:ok, view, html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collaboration"
          )

        [admin, editor, viewer] = insert_list(3, :user)

        # user is not shown in the page
        for new_user <- [admin, editor, viewer] do
          refute html =~ new_user.last_name
        end

        # Open Modal
        view
        |> element("#show_collaborators_modal_button")
        |> render_click()

        # lets click to add 2 more rows
        view
        |> form("#add_collaborators_modal_form")
        |> render_change(project: %{"collaborators_sort" => [0, "new", "new"]})

        # lets submit the form
        view
        |> form("#add_collaborators_modal_form",
          project: %{
            "collaborators" => %{
              "0" => %{"email" => admin.email, "role" => "admin"},
              "1" => %{"email" => editor.email, "role" => "editor"},
              "2" => %{"email" => viewer.email, "role" => "viewer"}
            }
          }
        )
        |> render_submit()

        updated_html = render(view)
        # users are shown in the page
        for new_user <- [admin, editor, viewer] do
          assert updated_html =~ new_user.last_name
        end
      end
    end

    test "only authorized users can remove a collaborator", %{
      conn: conn
    } do
      project = insert(:project)

      for {conn, _user} <- setup_project_users(conn, project, [:viewer, :editor]) do
        project_user =
          insert(:project_user,
            project: project,
            user: build(:user),
            role: :viewer
          )

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collaboration"
          )

        tooltip =
          element(view, "#remove_project_user_#{project_user.id}_button-tooltip")

        assert has_element?(tooltip)
        assert render(tooltip) =~ "You do not have permission to remove a user"

        # modal is not present
        refute has_element?(view, "#remove_#{project_user.id}_modal")

        # try sending the event either way
        html =
          render_click(view, "remove_project_user", %{
            "project_user_id" => project_user.id
          })

        assert html =~ "You are not authorized to perform this action"

        # project user still exists
        assert Repo.get(Lightning.Projects.ProjectUser, project_user.id)
      end

      for {conn, _user} <- setup_project_users(conn, project, [:owner, :admin]) do
        project_user =
          insert(:project_user,
            project: project,
            user: build(:user),
            role: :viewer
          )

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collaboration"
          )

        tooltip =
          element(view, "#remove_project_user_#{project_user.id}_button-tooltip")

        refute has_element?(tooltip)

        # modal is present
        assert has_element?(view, "#remove_#{project_user.id}_modal")

        # try clicking the confirm button
        html =
          view
          |> element("#remove_#{project_user.id}_modal_confirm_button")
          |> render_click()

        refute html =~ "You are not authorized to perform this action"
        assert html =~ "Collaborator removed successfully!"

        # project user is removed
        refute Repo.get(Lightning.Projects.ProjectUser, project_user.id)
        # user is not deleted
        assert Repo.get(Lightning.Accounts.User, project_user.user_id)
      end
    end

    test "removing an owner project user is not allowed",
         %{
           conn: conn
         } do
      project = insert(:project)

      for {conn, _user} <- setup_project_users(conn, project, [:owner, :admin]) do
        project_user =
          insert(:project_user,
            project: project,
            user: build(:user),
            role: :owner
          )

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collaboration"
          )

        tooltip =
          element(view, "#remove_project_user_#{project_user.id}_button-tooltip")

        assert has_element?(tooltip)
        assert render(tooltip) =~ "You cannot remove an owner"

        # modal is not present
        refute has_element?(view, "#remove_#{project_user.id}_modal")

        # try sending the event either way
        html =
          render_click(view, "remove_project_user", %{
            "project_user_id" => project_user.id
          })

        assert html =~ "You are not authorized to perform this action"

        # project user still exists
        assert Repo.get(Lightning.Projects.ProjectUser, project_user.id)
      end
    end

    test "users cannot remove themselves",
         %{
           conn: conn
         } do
      project = insert(:project)

      for {conn, user} <- setup_project_users(conn, project, [:owner, :admin]) do
        project_user =
          Repo.get_by(Lightning.Projects.ProjectUser, user_id: user.id)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#collaboration"
          )

        tooltip =
          element(view, "#remove_project_user_#{project_user.id}_button-tooltip")

        assert has_element?(tooltip)
        assert render(tooltip) =~ "You cannot remove yourself"

        # modal is not present
        refute has_element?(view, "#remove_#{project_user.id}_modal")

        # try sending the event either way
        html =
          render_click(view, "remove_project_user", %{
            "project_user_id" => project_user.id
          })

        assert html =~ "You are not authorized to perform this action"

        # project user still exists
        assert Repo.get(Lightning.Projects.ProjectUser, project_user.id)
      end
    end
  end

  describe "project settings:version control" do
    setup :verify_on_exit!

    test "users see appropriate message if version control is not enabled", %{
      conn: conn
    } do
      # Version control is disabled by NOT setting up config
      put_temporary_env(:lightning, :github_app,
        cert: nil,
        app_id: nil,
        app_name: nil,
        client_id: nil,
        client_secret: nil
      )

      project = insert(:project)

      for {conn, _user} <-
            setup_project_users(conn, project, [:viewer, :editor, :admin, :owner]) do
        {:ok, _view, html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        assert html =~
                 "Version Control is not configured for this Lightning instance"
      end
    end

    test "authorized users get option to connect their github account if they havent done so",
         %{conn: conn} do
      project = insert(:project)

      # unauthorized users don't get any option at all
      for {conn, _user} <-
            setup_project_users(conn, project, [:viewer, :editor]) do
        {:ok, view, html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        refute html =~
                 "Version Control is not configured for this Lightning instance"

        refute html =~ "Connect your OpenFn account to GitHub"
        refute has_element?(view, "#connect-github-link")
      end

      # authorized users
      for {conn, _user} <-
            setup_project_users(conn, project, [:admin, :owner]) do
        {:ok, view, html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        refute html =~
                 "Version Control is not configured for this Lightning instance"

        assert html =~ "Connect your OpenFn account to GitHub"
        assert has_element?(view, "#connect-github-link")
      end
    end

    test "authorized users see form to connect branch if they have already connected their github account",
         %{conn: conn} do
      project = insert(:project)

      # unauthorized users don't see the form at all
      for {conn, user} <-
            setup_project_users(conn, project, [:viewer, :editor]) do
        set_valid_github_oauth_token!(user)

        {:ok, _view, html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        refute html =~
                 "Version Control is not configured for this Lightning instance"

        refute html =~ "Create/update GitHub installations"
      end

      # authorized users
      for {conn, user} <-
            setup_project_users(conn, project, [:admin, :owner]) do
        set_valid_github_oauth_token!(user)

        {:ok, _view, html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        refute html =~
                 "Version Control is not configured for this Lightning instance"

        refute html =~ "Connect your OpenFn account to GitHub"
        assert html =~ "Create/update GitHub installations"
      end
    end

    test "users get updated after successfully connecting to github", %{
      conn: conn
    } do
      Mox.expect(Lightning.Tesla.Mock, :call, 2, fn
        %{url: "https://github.com/login/oauth/access_token"}, _opts ->
          {:ok, %Tesla.Env{body: %{"access_token" => "1234567"}}}

        # gets called after successful installation
        %{url: "https://api.github.com/user/installations"}, _opts ->
          {:ok, %Tesla.Env{status: 200, body: %{"installations" => []}}}
      end)

      project = insert(:project)

      {conn, _user} = setup_project_user(conn, project, :admin)

      {:ok, view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      assert has_element?(view, "#connect-github-link")
      refute html =~ "Create/update GitHub installations"

      # mock redirect from github
      get(conn, ~p"/oauth/github/callback?code=123456")

      flash = assert_redirect(view, ~p"/projects/#{project.id}/settings#vcs")

      assert flash["info"] == "Github account linked successfully"

      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/settings#vcs")

      refute has_element?(view, "#connect-github-link")
      assert html =~ "Create/update GitHub installations"
    end

    test "users get updated after failing to connect to github", %{
      conn: conn
    } do
      expected_resp = %{"error" => "something happened"}

      Mox.expect(Lightning.Tesla.Mock, :call, fn
        %{url: "https://github.com/login/oauth/access_token"}, _opts ->
          {:ok, %Tesla.Env{body: expected_resp}}
      end)

      project = insert(:project)

      {conn, _user} = setup_project_user(conn, project, :admin)

      {:ok, view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      assert has_element?(view, "#connect-github-link")
      refute html =~ "Create/update GitHub installations"

      # mock redirect from github
      get(conn, ~p"/oauth/github/callback?code=123456")

      :ok = refute_redirected(view, ~p"/projects/#{project.id}/settings#vcs")

      assert render(view) =~
               "Oops! Github account failed to link. Please try again"

      # button to connect is still available
      assert has_element?(view, "#connect-github-link")
      refute render(view) =~ "Create/update GitHub installations"
    end

    test "github installations get listed properly when an error occurs", %{
      conn: conn
    } do
      Mox.expect(Lightning.Tesla.Mock, :call, 1, fn
        %{url: "https://api.github.com/user/installations"}, _opts ->
          {:ok,
           %Tesla.Env{status: 400, body: %{"error" => "something terrible"}}}
      end)

      project = insert(:project)

      {conn, user} = setup_project_user(conn, project, :admin)
      set_valid_github_oauth_token!(user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      # things dont crash
      html = view |> element("#select-installations-input") |> render_async()

      # we only have one option listed
      floki_fragment = Floki.parse_fragment!(html)
      options = Floki.find(floki_fragment, "#select-installations-input option")
      assert Enum.count(options) == 1
      options |> hd() |> Floki.raw_html() =~ "Select an installation"

      # let us try refreshing the installation
      expected_installation = %{
        "id" => 1234,
        "account" => %{
          "type" => "User",
          "login" => "username"
        }
      }

      expected_access_token_endpoint =
        "https://api.github.com/app/installations/#{expected_installation["id"]}/access_tokens"

      Mox.expect(Lightning.Tesla.Mock, :call, 3, fn
        # list installations
        %{url: "https://api.github.com/user/installations"}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{"installations" => [expected_installation]}
           }}

        # get installation access token. This is called when fetching repos
        %{url: ^expected_access_token_endpoint}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 201,
             body: %{"token" => "some-token"}
           }}

        # list repos
        %{url: "https://api.github.com/installation/repositories"}, _opts ->
          {:ok, %Tesla.Env{status: 200, body: %{"repositories" => []}}}
      end)

      view |> element("#refresh-installation-button") |> render_click()

      html = view |> element("#select-installations-input") |> render_async()

      # we now have 2 options listed
      floki_fragment = Floki.parse_fragment!(html)

      [installations_input] =
        Floki.find(floki_fragment, "#select-installations-input")

      options = Floki.children(installations_input)
      assert Enum.count(options) == 2
      [default_option, installation_option] = options
      Floki.raw_html(default_option) =~ "Select an installation"

      Floki.raw_html(installation_option) =~
        "#{expected_installation["account"]["type"]}: #{expected_installation["account"]["login"]}"
    end

    test "branches list can be refreshed successfully", %{
      conn: conn
    } do
      expected_installation = %{
        "id" => "1234",
        "account" => %{
          "type" => "User",
          "login" => "username"
        }
      }

      expected_access_token_endpoint =
        "https://api.github.com/app/installations/#{expected_installation["id"]}/access_tokens"

      expected_repo = %{
        "full_name" => "someaccount/somerepo"
      }

      expected_branch_endpoint =
        "https://api.github.com/repos/#{expected_repo["full_name"]}/branches"

      expected_branch = %{"name" => "somebranch"}

      Mox.expect(Lightning.Tesla.Mock, :call, 5, fn
        # list installations
        %{url: "https://api.github.com/user/installations"}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{"installations" => [expected_installation]}
           }}

        # get installation access token. This is called when fetching repos and branches
        %{url: ^expected_access_token_endpoint}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 201,
             body: %{"token" => "some-token"}
           }}

        # list repos
        %{url: "https://api.github.com/installation/repositories"}, _opts ->
          {:ok,
           %Tesla.Env{status: 200, body: %{"repositories" => [expected_repo]}}}

        # list branches
        %{url: ^expected_branch_endpoint}, _opts ->
          {:ok, %Tesla.Env{status: 200, body: [expected_branch]}}
      end)

      project = insert(:project)

      {conn, user} = setup_project_user(conn, project, :admin)
      set_valid_github_oauth_token!(user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      render_async(view)

      # lets select the installation
      view
      |> form("#project-repo-connection-form",
        connection: %{github_installation_id: expected_installation["id"]}
      )
      |> render_change()

      selected_installation =
        view
        |> element("#select-installations-input")
        |> render_async()
        |> find_selected_option("#select-installations-input option")

      assert selected_installation =~ expected_installation["id"]

      # lets select the repo
      view
      |> form("#project-repo-connection-form",
        connection: %{
          github_installation_id: expected_installation["id"],
          repo: expected_repo["full_name"]
        }
      )
      |> render_change()

      selected_repo =
        view
        |> element("#select-repos-input")
        |> render_async()
        |> find_selected_option("#select-repos-input option")

      assert selected_repo =~ expected_repo["full_name"]

      # lets select the branch
      view
      |> form("#project-repo-connection-form",
        connection: %{
          github_installation_id: expected_installation["id"],
          repo: expected_repo["full_name"],
          branch: expected_branch["name"]
        }
      )
      |> render_change()

      selected_branch =
        view
        |> element("#select-branches-input")
        |> render_async()
        |> find_selected_option("#select-branches-input option")

      assert selected_branch =~ expected_branch["name"]

      # deselecting the installation deselects the repo and branch
      view
      |> form("#project-repo-connection-form",
        connection: %{github_installation_id: ""}
      )
      |> render_change()

      html = render_async(view)

      refute find_selected_option(html, "#select-repos-input option")

      refute find_selected_option(html, "#select-branches-input option")

      # let us list the branches again by following the ritual again
      view
      |> form("#project-repo-connection-form",
        connection: %{github_installation_id: expected_installation["id"]}
      )
      |> render_change()

      Mox.expect(Lightning.Tesla.Mock, :call, 2, fn
        # get installation access token.
        %{url: ^expected_access_token_endpoint}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 201,
             body: %{"token" => "some-token"}
           }}

        # list branches
        %{url: ^expected_branch_endpoint}, _opts ->
          {:ok, %Tesla.Env{status: 200, body: [expected_branch]}}
      end)

      view
      |> form("#project-repo-connection-form",
        connection: %{
          github_installation_id: expected_installation["id"],
          repo: expected_repo["full_name"]
        }
      )
      |> render_change()

      # we should now have 2 options listed for the branches
      # The default and the expected
      options =
        view
        |> element("#select-branches-input")
        |> render_async()
        |> Floki.parse_fragment!()
        |> Floki.find("#select-branches-input option")

      assert Enum.count(options) == 2

      # now let us refresh the branches
      new_branch = %{"name" => "newbranch"}

      Mox.expect(Lightning.Tesla.Mock, :call, 2, fn
        # get installation access token.
        %{url: ^expected_access_token_endpoint}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 201,
             body: %{"token" => "some-token"}
           }}

        # list branches
        %{url: ^expected_branch_endpoint}, _opts ->
          {:ok, %Tesla.Env{status: 200, body: [expected_branch, new_branch]}}
      end)

      view |> element("#refresh-branches-button") |> render_click()

      # we should now have 3 options listed for the branches
      # The default, the expected and the new branch
      options =
        view
        |> element("#select-branches-input")
        |> render_async()
        |> Floki.parse_fragment!()
        |> Floki.find("#select-branches-input option")

      assert Enum.count(options) == 3
    end

    test "authorized users can save repo connection successfully",
         %{
           conn: conn
         } do
      expected_installation = %{
        "id" => 1234,
        "account" => %{
          "type" => "User",
          "login" => "username"
        }
      }

      expected_access_token_endpoint =
        "https://api.github.com/app/installations/#{expected_installation["id"]}/access_tokens"

      expected_repo = %{
        "full_name" => "someaccount/somerepo"
      }

      expected_branch_endpoint =
        "https://api.github.com/repos/#{expected_repo["full_name"]}/branches"

      expected_branch = %{"name" => "somebranch"}

      project = insert(:project)

      {conn, user} = setup_project_user(conn, project, :admin)
      set_valid_github_oauth_token!(user)

      Mox.expect(Lightning.Tesla.Mock, :call, 3, fn
        # list installations
        %{url: "https://api.github.com/user/installations"}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{"installations" => [expected_installation]}
           }}

        # get installation access token. This is called when fetching repos
        %{url: ^expected_access_token_endpoint}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 201,
             body: %{"token" => "some-token"}
           }}

        # list repos
        %{url: "https://api.github.com/installation/repositories"}, _opts ->
          {:ok,
           %Tesla.Env{status: 200, body: %{"repositories" => [expected_repo]}}}
      end)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/settings#vcs"
        )

      # we have 2 options listed for installations
      floki_fragment = view |> render_async() |> Floki.parse_fragment!()

      [installations_input] =
        Floki.find(floki_fragment, "#select-installations-input")

      options = Floki.children(installations_input)
      assert Enum.count(options) == 2
      [default_option, installation_option] = options
      Floki.raw_html(default_option) =~ "Select an installation"

      Floki.raw_html(installation_option) =~
        "#{expected_installation["account"]["type"]}: #{expected_installation["account"]["login"]}"

      # before selecting any installation the repos are not listed.
      # We just have the default option
      floki_fragment = view |> render_async() |> Floki.parse_fragment!()
      [repos_input] = Floki.find(floki_fragment, "#select-repos-input")
      options = Floki.children(repos_input)
      assert Enum.count(options) == 1
      options |> hd() |> Floki.raw_html() =~ "Select a repo"

      # lets select the installation
      view
      |> form("#project-repo-connection-form",
        connection: %{github_installation_id: expected_installation["id"]}
      )
      |> render_change()

      # we should now have the repos listed
      floki_fragment = view |> render_async() |> Floki.parse_fragment!()
      [repos_input] = Floki.find(floki_fragment, "#select-repos-input")
      options = Floki.children(repos_input)
      assert Enum.count(options) == 2
      [default_option, repo_option] = options
      Floki.raw_html(default_option) =~ "Select a repo"
      Floki.raw_html(repo_option) =~ expected_repo["full_name"]

      # before selecting any repo, the branches are not listed.
      # We just have the default option

      floki_fragment = view |> render_async() |> Floki.parse_fragment!()
      [branches_input] = Floki.find(floki_fragment, "#select-branches-input")
      options = Floki.children(branches_input)
      assert Enum.count(options) == 1
      options |> hd() |> Floki.raw_html() =~ "Select a branch"

      # lets select the repo
      Mox.expect(Lightning.Tesla.Mock, :call, 2, fn
        # get installation access token. This is called when fetching branches
        %{url: ^expected_access_token_endpoint}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 201,
             body: %{"token" => "some-token"}
           }}

        # list branches
        %{url: ^expected_branch_endpoint}, _opts ->
          {:ok, %Tesla.Env{status: 200, body: [expected_branch]}}
      end)

      view
      |> form("#project-repo-connection-form",
        connection: %{
          github_installation_id: expected_installation["id"],
          repo: expected_repo["full_name"]
        }
      )
      |> render_change()

      # we should now have the branches listed
      floki_fragment = view |> render_async() |> Floki.parse_fragment!()
      [branches_input] = Floki.find(floki_fragment, "#select-branches-input")
      options = Floki.children(branches_input)
      assert Enum.count(options) == 2
      [default_option, branch_option] = options
      Floki.raw_html(default_option) =~ "Select a branch"
      Floki.raw_html(branch_option) =~ expected_branch["name"]

      # try submitting without selecting branch
      error_msg = "This field can&#39;t be blank"
      refute render(view) =~ error_msg

      html =
        view
        |> form("#project-repo-connection-form")
        |> render_submit()

      assert html =~ error_msg

      # let us submit with the branch

      github_connection_expectations(
        expected_installation["id"],
        expected_repo["full_name"],
        expected_branch["name"]
      )

      view
      |> form("#project-repo-connection-form")
      |> render_submit(connection: %{branch: expected_branch["name"]})

      flash = assert_redirected(view, ~p"/projects/#{project.id}/settings#vcs")
      assert flash["info"] == "Connection made successfully"
    end

    test "all users can see a saved repo connection", %{conn: conn} do
      project = insert(:project)

      repo_connection =
        insert(:project_repo_connection,
          project: project,
          repo: "someaccount/somerepo",
          branch: "somebranch",
          github_installation_id: "1234"
        )

      expected_access_token_endpoint =
        "https://api.github.com/app/installations/#{repo_connection.github_installation_id}/access_tokens"

      for {conn, _user} <-
            setup_project_users(conn, project, [:viewer, :editor, :admin, :owner]) do
        # we are returning 404 for the access token so that we halt the pipeline for verifying the connection
        Mox.expect(Lightning.Tesla.Mock, :call, 1, fn
          %{url: ^expected_access_token_endpoint}, _opts ->
            {:ok,
             %Tesla.Env{status: 404, body: %{"error" => "something terrible"}}}
        end)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        html = render_async(view)

        refute has_element?(view, "#project-repo-connection-form")

        assert html =~ repo_connection.repo
        assert html =~ repo_connection.branch
        assert html =~ repo_connection.github_installation_id
      end
    end

    test "unauthorized users cannot reconnect project even if they have access to the installation",
         %{conn: conn} do
      project = insert(:project)

      repo_connection =
        insert(:project_repo_connection,
          project: project,
          repo: "someaccount/somerepo",
          branch: "somebranch",
          github_installation_id: "1234"
        )

      expected_installation = %{
        "id" => repo_connection.github_installation_id,
        "account" => %{
          "type" => "User",
          "login" => "username"
        }
      }

      expected_access_token_endpoint =
        "https://api.github.com/app/installations/#{repo_connection.github_installation_id}/access_tokens"

      for {conn, user} <- setup_project_users(conn, project, [:viewer, :editor]) do
        set_valid_github_oauth_token!(user)

        Mox.expect(Lightning.Tesla.Mock, :call, 5, fn
          # list installations for checking if the user has access to the intallation.
          %{url: "https://api.github.com/user/installations"}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{"installations" => [expected_installation]}
             }}

          # get installation access token. This is called twice.
          # When fetching repos and when verifying connection
          %{url: ^expected_access_token_endpoint}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 201,
               body: %{"token" => "some-token"}
             }}

          # list repos
          %{url: "https://api.github.com/installation/repositories"}, _opts ->
            {:ok, %Tesla.Env{status: 200, body: %{"repositories" => []}}}

          # another call for verifying connection. Probably for checking if a file exists
          # ignoring to halt the pipeline
          %{url: _url}, _opts ->
            {:error, "something unexpected happened"}
        end)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        html = render_async(view)

        refute has_element?(view, "#reconnect-project-button")

        assert html =~
                 "Reach out to the admin who made this installation to reconnect"

        # try sending the event either way
        view
        |> with_target("#github-sync-component")
        |> render_click("reconnect", %{})

        # a flash is rendered
        # I'm unable to get the flash in the tests even though it actually appears in the page
        # assert html =~ "You are not authorized to perform this action"

        assert render(view) =~
                 "Reach out to the admin who made this installation to reconnect"
      end
    end

    test "authorized users cannot reconnect project if they don't have access to the installation",
         %{conn: conn} do
      project = insert(:project)

      repo_connection =
        insert(:project_repo_connection,
          project: project,
          repo: "someaccount/somerepo",
          branch: "somebranch",
          github_installation_id: "1234",
          access_token: "someaccesstoken"
        )

      expected_access_token_endpoint =
        "https://api.github.com/app/installations/#{repo_connection.github_installation_id}/access_tokens"

      for {conn, user} <-
            setup_project_users(conn, project, [:admin, :owner]) do
        set_valid_github_oauth_token!(user)

        Mox.expect(Lightning.Tesla.Mock, :call, 2, fn
          # list installations for checking if the user has access to the intallation.
          # in this we return an empty list to simulate user not having access to the installation
          %{url: "https://api.github.com/user/installations"}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{"installations" => []}
             }}

          # get installation access token. This is called when verifying connection
          %{url: ^expected_access_token_endpoint}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 404,
               body: %{"error" => "something bad"}
             }}
        end)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        html = render_async(view)

        refute has_element?(view, "#reconnect-project-button")

        assert html =~
                 "Reach out to the admin who made this installation to reconnect"
      end
    end

    test "authorized users can reconnect project if they have access to the installation",
         %{conn: conn} do
      project = insert(:project)

      repo_connection =
        insert(:project_repo_connection,
          project: project,
          repo: "someaccount/somerepo",
          branch: "somebranch",
          github_installation_id: "1234",
          access_token: "someaccesstoken"
        )

      expected_installation = %{
        "id" => repo_connection.github_installation_id,
        "account" => %{
          "type" => "User",
          "login" => "username"
        }
      }

      expected_access_token_endpoint =
        "https://api.github.com/app/installations/#{repo_connection.github_installation_id}/access_tokens"

      for {conn, user} <-
            setup_project_users(conn, project, [:admin, :owner]) do
        set_valid_github_oauth_token!(user)

        Mox.expect(Lightning.Tesla.Mock, :call, 5, fn
          # list installations for checking if the user has access to the intallation.
          %{url: "https://api.github.com/user/installations"}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{"installations" => [expected_installation]}
             }}

          # get installation access token. This is called twice.
          # When fetching repos and when verifying connection
          %{url: ^expected_access_token_endpoint}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 201,
               body: %{"token" => "some-token"}
             }}

          # list repos
          %{url: "https://api.github.com/installation/repositories"}, _opts ->
            {:ok, %Tesla.Env{status: 200, body: %{"repositories" => []}}}

          # another call for verifying connection. Probably for checking if a file exists
          # ignoring to halt the pipeline
          %{url: _url}, _opts ->
            {:error, "something unexpected happened"}
        end)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        html = render_async(view)

        assert has_element?(view, "#reconnect-project-button")

        refute html =~
                 "Reach out to the admin who made this installation to reconnect"

        github_connection_expectations(
          repo_connection.github_installation_id,
          repo_connection.repo,
          repo_connection.branch
        )

        view |> element("#reconnect-project-button") |> render_click()

        flash = assert_redirected(view, ~p"/projects/#{project.id}/settings#vcs")

        assert flash["info"] == "Connection made successfully!"
      end
    end

    test "reconnect button does not show if everything checks out",
         %{conn: conn} do
      project = insert(:project)

      repo_connection =
        insert(:project_repo_connection,
          project: project,
          repo: "someaccount/somerepo",
          branch: "somebranch",
          github_installation_id: "1234",
          access_token: "someaccesstoken"
        )

      repo_name = repo_connection.repo

      expected_installation = %{
        "id" => repo_connection.github_installation_id,
        "account" => %{
          "type" => "User",
          "login" => "username"
        }
      }

      expected_access_token_endpoint =
        "https://api.github.com/app/installations/#{repo_connection.github_installation_id}/access_tokens"

      for {conn, user} <-
            setup_project_users(conn, project, [:viewer, :editor, :admin, :owner]) do
        set_valid_github_oauth_token!(user)

        Mox.expect(Lightning.Tesla.Mock, :call, 9, fn
          # list installations for checking if the user has access to the intallation.
          %{url: "https://api.github.com/user/installations"}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{"installations" => [expected_installation]}
             }}

          # get installation access token. This is called twice.
          # When fetching repos and when verifying connection
          %{url: ^expected_access_token_endpoint}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 201,
               body: %{"token" => "some-token"}
             }}

          # list repos. This goes hand in hand installations
          %{url: "https://api.github.com/installation/repositories"}, _opts ->
            {:ok, %Tesla.Env{status: 200, body: %{"repositories" => []}}}

          # check if pull yml exists
          %{
            method: :get,
            url:
              "https://api.github.com/repos/" <>
                  ^repo_name <> "/contents/.github/workflows/pull.yml"
          },
          _opts ->
            {:ok, %Tesla.Env{status: 200, body: %{"sha" => "somesha"}}}

          # check if deploy yml exists
          %{
            method: :get,
            url:
              "https://api.github.com/repos/" <>
                  ^repo_name <> "/contents/.github/workflows/deploy.yml"
          },
          _opts ->
            {:ok, %Tesla.Env{status: 200, body: %{"sha" => "somesha"}}}

          # check if project yml exists
          %{
            method: :get,
            url:
              "https://api.github.com/repos/" <>
                  ^repo_name <> "/contents/project.yaml"
          },
          _opts ->
            {:ok, %Tesla.Env{status: 200, body: %{"sha" => "somesha"}}}

          # check if project state exists
          %{
            method: :get,
            url:
              "https://api.github.com/repos/" <>
                  ^repo_name <> "/contents/.state.json"
          },
          _opts ->
            {:ok, %Tesla.Env{status: 200, body: %{"sha" => "somesha"}}}

          # check if api key secret exists
          %{
            method: :get,
            url:
              "https://api.github.com/repos/" <>
                  ^repo_name <> "/actions/secrets/OPENFN_API_KEY"
          },
          _opts ->
            {:ok, %Tesla.Env{status: 200, body: %{}}}
        end)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        html = render_async(view)

        refute has_element?(view, "#reconnect-project-button")

        refute html =~
                 "Reach out to the admin who made this installation to reconnect"

        assert html =~ "Your project is all setup"
      end
    end

    test "unauthorized users cannot remove github connection", %{conn: conn} do
      project = insert(:project)

      repo_connection =
        insert(:project_repo_connection,
          project: project,
          repo: "someaccount/somerepo",
          branch: "somebranch",
          github_installation_id: "1234",
          access_token: "someaccesstoken"
        )

      for {conn, user} <- setup_project_users(conn, project, [:viewer, :editor]) do
        # giving the user a valid token
        set_valid_github_oauth_token!(user)

        Mox.expect(Lightning.Tesla.Mock, :call, 2, fn
          # list installations for checking if the user has access to the installation.
          # we return 400 to halt the pipeline
          %{url: "https://api.github.com/user/installations"}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 400,
               body: %{"something" => "bad"}
             }}

          # get access token. Gets called when verifying connection
          %{
            url: "https://api.github.com/app/installations/" <> _installation_id
          },
          _opts ->
            {:ok,
             %Tesla.Env{
               status: 404,
               body: %{"something" => "not right"}
             }}
        end)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        html = render_async(view)

        refute has_element?(view, "#remove_connection_modal")

        refute html =~ "Remove Integration"

        # try sending the delete event either way
        view
        |> with_target("#github-sync-component")
        |> render_click("delete-connection", %{})

        assert Lightning.Repo.reload(repo_connection)
      end
    end

    test "authorized users who have not setup github accounts can remove github connection",
         %{conn: conn} do
      project = insert(:project)

      for {conn, user} <- setup_project_users(conn, project, [:owner, :admin]) do
        repo_connection =
          insert(:project_repo_connection,
            project: project,
            repo: "someaccount/somerepo",
            branch: "somebranch",
            github_installation_id: "1234",
            access_token: "someaccesstoken"
          )

        assert is_nil(user.github_oauth_token)

        Mox.expect(Lightning.Tesla.Mock, :call, 1, fn
          # get access token. Gets called when verifying connection
          # we return 400 to halt the pipeline
          %{
            url: "https://api.github.com/app/installations/" <> _installation_id
          },
          _opts ->
            {:ok,
             %Tesla.Env{
               status: 404,
               body: %{"something" => "not right"}
             }}
        end)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        html = render_async(view)

        assert has_element?(view, "#remove_connection_modal")
        assert has_element?(view, "#remove_connection_modal_confirm_button")
        assert html =~ "Remove Integration"

        # click the confirm button
        view
        |> element("#remove_connection_modal_confirm_button")
        |> render_click()

        flash = assert_redirected(view, ~p"/projects/#{project.id}/settings#vcs")

        assert flash["info"] == "Connection removed successfully"

        refute Lightning.Repo.reload(repo_connection)
      end
    end

    test "authorized users with valid github oauth can remove github connection even when undoing some github actions fail",
         %{conn: conn} do
      project = insert(:project)

      for {conn, user} <- setup_project_users(conn, project, [:owner, :admin]) do
        user = set_valid_github_oauth_token!(user)

        repo_connection =
          insert(:project_repo_connection,
            project: project,
            repo: "someaccount/somerepo",
            branch: "somebranch",
            github_installation_id: "1234",
            access_token: "someaccesstoken"
          )

        repo_name = repo_connection.repo

        assert is_map(user.github_oauth_token)

        Mox.expect(Lightning.Tesla.Mock, :call, 2, fn
          # get access token. Gets called when verifying connection
          # we return 400 to halt the pipeline
          %{url: "https://api.github.com/app/installations/" <> _rest}, _opts ->
            {:ok, %Tesla.Env{status: 404, body: %{"something" => "not right"}}}

          # check if user has access to the installation
          %{url: "https://api.github.com/user/installations"}, _opts ->
            {:ok, %Tesla.Env{status: 404, body: %{"something" => "not right"}}}
        end)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/settings#vcs"
          )

        html = render_async(view)

        assert has_element?(view, "#remove_connection_modal")
        assert has_element?(view, "#remove_connection_modal_confirm_button")
        assert html =~ "Remove Integration"

        Mox.expect(Lightning.Tesla.Mock, :call, 4, fn env, _opts ->
          case env do
            # check if pull yml exists for deletion
            %{
              method: :get,
              url:
                "https://api.github.com/repos/" <>
                    ^repo_name <> "/contents/.github/workflows/pull.yml"
            } ->
              {:ok, %Tesla.Env{status: 200, body: %{"sha" => "somesha"}}}

            # delete pull yml
            %{
              method: :delete,
              url:
                "https://api.github.com/repos/" <>
                    ^repo_name <> "/contents/.github/workflows/pull.yml"
            } ->
              {:ok, %Tesla.Env{status: 200, body: %{"sha" => "somesha"}}}

            # check if deploy yml exists for deletion
            %{
              method: :get,
              url:
                "https://api.github.com/repos/" <>
                    ^repo_name <> "/contents/.github/workflows/deploy.yml"
            } ->
              {:ok, %Tesla.Env{status: 200, body: %{"sha" => "somesha"}}}

            # delete deploy yml.
            %{
              method: :delete,
              url:
                "https://api.github.com/repos/" <>
                    ^repo_name <> "/contents/.github/workflows/deploy.yml"
            } ->
              {:ok, %Tesla.Env{status: 400, body: %{"something" => "happened"}}}
          end
        end)

        # click the confirm button
        view
        |> element("#remove_connection_modal_confirm_button")
        |> render_click()

        flash = assert_redirected(view, ~p"/projects/#{project.id}/settings#vcs")

        assert flash["info"] == "Connection removed successfully"

        refute Lightning.Repo.reload(repo_connection)
      end
    end

    test "unauthorized users cannot initiate github sync", %{conn: conn} do
      project = insert(:project)

      insert(:project_repo_connection,
        project: project,
        repo: "someaccount/somerepo",
        branch: "somebranch",
        github_installation_id: "1234",
        access_token: "someaccesstoken"
      )

      for {conn, user} <- setup_project_users(conn, project, [:viewer]) do
        # giving the user a valid token
        set_valid_github_oauth_token!(user)

        Mox.expect(Lightning.Tesla.Mock, :call, 2, fn
          # list installations for checking if the user has access to the installation.
          # we return 400 to halt the pipeline
          %{url: "https://api.github.com/user/installations"}, _opts ->
            {:ok, %Tesla.Env{status: 400, body: %{"something" => "bad"}}}

          # get access token. Gets called when verifying connection
          %{url: "https://api.github.com/app/installations/" <> _rest}, _opts ->
            {:ok, %Tesla.Env{status: 404, body: %{"something" => "not right"}}}
        end)

        {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/settings#vcs")

        html = render_async(view)

        assert html =~ "Contact an editor or admin to sync."
        assert has_element?(view, "#initiate-sync-button:disabled")

        # try sending the sync event either way
        view
        |> with_target("#github-sync-component")
        |> render_click("initiate-sync", %{})

        # a flash is rendered
        # I'm unable to get the flash in the tests even though it actually appears in the page
        # assert html =~ "You are not authorized to perform this action"

        assert render(view) =~ "Contact an editor or admin to sync."
      end
    end

    test "authorized users cannot initiate github sync successfully", %{
      conn: conn
    } do
      project = insert(:project)

      repo_connection =
        insert(:project_repo_connection,
          project: project,
          repo: "someaccount/somerepo",
          branch: "somebranch",
          github_installation_id: "1234",
          access_token: "someaccesstoken"
        )

      repo_name = repo_connection.repo
      installation_id = repo_connection.github_installation_id

      for {conn, user} <-
            setup_project_users(conn, project, [:editor, :admin, :owner]) do
        # users dont need the oauth token in order to initialize sync
        assert is_nil(user.github_oauth_token)

        Mox.expect(Lightning.Tesla.Mock, :call, 1, fn
          # get access token. Gets called when verifying connection
          %{url: "https://api.github.com/app/installations/" <> _rest}, _opts ->
            {:ok, %Tesla.Env{status: 404, body: %{"something" => "not right"}}}
        end)

        {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/settings#vcs")

        html = render_async(view)

        refute html =~ "Contact an editor or admin to sync."

        button = element(view, "#initiate-sync-button")
        assert has_element?(button)

        # try clicking the button
        Mox.expect(Lightning.Tesla.Mock, :call, 2, fn
          # get access token.for dispatching event
          %{
            url:
              "https://api.github.com/app/installations/" <>
                  ^installation_id <> "/access_tokens"
          },
          _opts ->
            {:ok, %Tesla.Env{status: 201, body: %{"token" => "sometoken"}}}

          # dispatch event
          %{url: "https://api.github.com/repos/" <> ^repo_name <> "/dispatches"},
          _opts ->
            {:ok, %Tesla.Env{status: 204, body: ""}}
        end)

        render_click(button)

        flash = assert_redirected(view, ~p"/projects/#{project.id}/settings#vcs")

        assert flash["info"] == "Github sync initiated successfully!"
      end
    end
  end

  defp find_selected_option(html, selector) do
    html
    |> Floki.parse_fragment!()
    |> Floki.find(selector)
    |> Enum.map(&Floki.raw_html/1)
    |> Enum.find(fn el -> el =~ "selected=\"selected\"" end)
  end

  defp find_user_index_in_list(view, user) do
    Floki.parse_fragment!(render(view))
    |> Floki.find("#project-users-form tbody tr")
    |> Enum.find_index(fn el ->
      Floki.find(el, "td:first-child()") |> Floki.text() =~
        "#{user.first_name} #{user.last_name}"
    end)
    |> to_string()
  end

  defp set_valid_github_oauth_token!(user) do
    active_token = %{
      "access_token" => "access-token",
      "refresh_token" => "refresh-token",
      "expires_at" => DateTime.utc_now() |> DateTime.add(500),
      "refresh_token_expires_at" => DateTime.utc_now() |> DateTime.add(500)
    }

    user
    |> Ecto.Changeset.change(%{github_oauth_token: active_token})
    |> Repo.update!()
  end

  defp github_connection_expectations(
         installation_id,
         expected_repo_name,
         expected_branch_name
       ) do
    installation_id = to_string(installation_id)

    Mox.expect(Lightning.Tesla.Mock, :call, 10, fn env, _opts ->
      case env.url do
        # create blob. called twice (for push.yml and deploy.yml)
        "https://api.github.com/repos/" <> ^expected_repo_name <> "/git/blobs" ->
          {:ok,
           %Tesla.Env{
             status: 201,
             body: %{"sha" => "3a0f86fb8db8eea7ccbb9a95f325ddbedfb25e15"}
           }}

        # get commit on selected branch
        "https://api.github.com/repos/" <>
            ^expected_repo_name <>
            "/commits/heads/" <>
            ^expected_branch_name ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "sha" => "6dcb09b5b57875f334f61aebed695e2e4193db5e",
               "commit" => %{
                 "tree" => %{
                   "sha" => "6dcb09b5b57875f334f61aebed695e2e4193db5e"
                 }
               }
             }
           }}

        # create commit
        "https://api.github.com/repos/" <> ^expected_repo_name <> "/git/commits" ->
          {:ok,
           %Tesla.Env{
             status: 201,
             body: %{"sha" => "7638417db6d59f3c431d3e1f261cc637155684cd"}
           }}

        # create tree
        "https://api.github.com/repos/" <> ^expected_repo_name <> "/git/trees" ->
          {:ok,
           %Tesla.Env{
             status: 201,
             body: %{"sha" => "cd8274d15fa3ae2ab983129fb037999f264ba9a7"}
           }}

        # update a reference on the selected branch
        "https://api.github.com/repos/" <>
            ^expected_repo_name <>
            "/git/refs/heads/" <>
            ^expected_branch_name ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{"ref" => "refs/heads/master"}
           }}

        # get repo public key
        "https://api.github.com/repos/" <>
            ^expected_repo_name <> "/actions/secrets/public-key" ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "key" => Base.encode64(@public_key),
               "key_id" => "012345678912345678"
             }
           }}

        # create the OPENFN_API_KEY repo secret
        "https://api.github.com/repos/" <>
            ^expected_repo_name <> "/actions/secrets/OPENFN_API_KEY" ->
          {:ok, %Tesla.Env{status: 201, body: ""}}

        # token for sync
        "https://api.github.com/app/installations/" <>
            ^installation_id <> "/access_tokens" ->
          {:ok,
           %Tesla.Env{
             status: 201,
             body: %{"token" => "some-token"}
           }}

        # initialize sync
        "https://api.github.com/repos/" <>
            ^expected_repo_name <> "/dispatches" ->
          {:ok, %Tesla.Env{status: 204, body: ""}}
      end
    end)
  end
end
