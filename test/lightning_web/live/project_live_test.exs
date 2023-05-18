defmodule LightningWeb.ProjectLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.ProjectsFixtures
  import Lightning.AccountsFixtures

  @create_attrs %{
    raw_name: "some name"
  }
  @invalid_attrs %{raw_name: nil}

  defp create_project(_) do
    project = project_fixture()
    %{project: project}
  end

  describe "Index as a regular user" do
    setup :register_and_log_in_user

    test "cannot access the index page", %{conn: conn} do
      {:ok, _index_live, html} =
        live(conn, ~p"/settings/projects") |> follow_redirect(conn, "/")

      assert html =~ "You can&#39;t access that page"
    end

    test "cannot access the new page", %{conn: conn} do
      {:ok, _index_live, html} =
        live(conn, ~p"/settings/projects/new")
        |> follow_redirect(conn, "/")

      assert html =~ "You can&#39;t access that page"
    end
  end

  describe "Index" do
    setup [:register_and_log_in_superuser, :create_project]

    test "lists all projects", %{conn: conn, project: project} do
      {:ok, _index_live, html} =
        live(conn, Routes.project_index_path(conn, :index))

      assert html =~ "Projects"
      assert html =~ project.name
    end

    test "saves new project", %{conn: conn} do
      user = user_fixture()

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
      |> element("#member_list")
      |> render_hook("select_item", %{"id" => user.id})

      assert index_live
             |> element("button", "Add")
             |> render_click() =~ "editor"

      index_live
      |> form("#project-form")
      |> render_submit()

      assert_patch(index_live, Routes.project_index_path(conn, :index))
      assert render(index_live) =~ "Project created successfully"
    end

    # test "Only superuser can delete projects", %{
    #   conn: conn,
    #   project: project
    # } do
    #   delete_button = "#delete-#{project.id}"
    #   schedule_delete_button = "#schedule-delete-#{project.id}"
    #   cancel_delete_button = "#cancel-delete-#{project.id}"

    #   conn =
    #     setup_project_user(
    #       conn,
    #       project,
    #       Lightning.AccountsFixtures.superuser_fixture(),
    #       :editor
    #     )

    #   {:ok, view, _html} = live(conn, Routes.project_index_path(conn, :index))

    #   refute view |> element(delete_button) |> has_element?(),
    #          "Should not show delete button"

    #   refute view |> element(cancel_delete_button) |> has_element?(),
    #          "Should not show cancel deletion button"

    #   assert view |> element(schedule_delete_button) |> has_element?(),
    #          "Should show schedule delete button"

    #   conn =
    #     setup_project_user(
    #       conn,
    #       project,
    #       Lightning.AccountsFixtures.superuser_fixture(),
    #       :owner
    #     )

    #   {:ok, view, _html} = live(conn, Routes.project_index_path(conn, :index))

    #   assert view
    #          |> element(schedule_delete_button)
    #          |> render_click() =~ "Project scheduled for deletion"

    #   assert has_element?(view, delete_button), "Should show delete now button"

    #   assert has_element?(view, cancel_delete_button),
    #          "Should show cancel deletion button"

    #   refute view |> element(schedule_delete_button) |> has_element?(),
    #          "Should not show schedule delete button"

    #   assert view
    #          |> element(cancel_delete_button)
    #          |> render_click() =~ "Canceled project deletion schedule"

    #   refute view |> element(delete_button) |> has_element?(),
    #          "Should not show delete now button"

    #   refute view |> element(cancel_delete_button) |> has_element?(),
    #          "Should not show cancel deletion button"

    #   assert view |> element(schedule_delete_button) |> has_element?(),
    #          "Should show schedule delete button"

    #   {:ok, view, _html} = live(conn, Routes.project_index_path(conn, :index))

    #   assert view
    #          |> element(schedule_delete_button)
    #          |> render_click() =~ "Project scheduled for deletion"

    #   assert has_element?(view, delete_button), "Should show delete now button"

    #   assert has_element?(view, cancel_delete_button),
    #          "Should show cancel deletion button"

    #   refute view |> element(schedule_delete_button) |> has_element?(),
    #          "Should not show schedule delete button"

    #   assert view
    #          |> element(delete_button)
    #          |> render_click() =~ "Project deleted successfully"

    #   refute view |> element(schedule_delete_button) |> has_element?(),
    #          "Should not show schedule delete button"

    #   refute view |> element(cancel_delete_button) |> has_element?(),
    #          "Should not show cancel deletion button"

    #   project = project_fixture(scheduled_deletion: nil)

    #   assert view
    #          |> render_click("delete_now", %{
    #            "id" => project.id
    #          }) =~
    #            "You are not authorized to perform this action."

    #   assert_patched(view, ~p"/settings/projects")
    # end

    test "Edits a project", %{conn: conn} do
      user = user_fixture()
      project = project_fixture()

      {:ok, view, _html} = live(conn, ~p"/settings/projects/#{project.id}")

      view
      |> element("#member_list")
      |> render_hook("select_item", %{"id" => user.id})

      assert view
             |> element("button", "Add")
             |> render_click() =~ "editor"

      view
      |> form("#project-form")
      |> render_submit()

      assert_patch(view, ~p"/settings/projects")
      assert render(view) =~ "Project updated successfully"
    end
  end

  describe "projects picker dropdown" do
    setup :register_and_log_in_user

    test "Access project settings page", %{conn: conn, user: user} do
      another_user = user_fixture()

      {:ok, project_1} =
        Lightning.Projects.create_project(%{
          name: "project-1",
          project_users: [%{user_id: user.id}]
        })

      {:ok, project_2} =
        Lightning.Projects.create_project(%{
          name: "project-2",
          project_users: [%{user_id: user.id}]
        })

      {:ok, project_3} =
        Lightning.Projects.create_project(%{
          name: "project-3",
          project_users: [%{user_id: another_user.id}]
        })

      {:ok, view, _html} =
        live(conn, Routes.project_workflow_path(conn, :index, project_1))

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

      {:ok, view, html} =
        live(
          conn,
          Routes.project_workflow_path(conn, :index, project_1.id)
        )

      assert html =~ project_1.name
      assert view |> element("button", "#{project_1.name}") |> has_element?()

      assert view
             |> element(
               "a[href='#{Routes.project_workflow_path(conn, :index, project_2.id)}']"
             )
             |> has_element?()

      refute view
             |> element(
               "a[href='#{Routes.project_workflow_path(conn, :index, project_3.id)}']"
             )
             |> has_element?()

      {:ok, view, html} =
        live(
          conn,
          Routes.project_workflow_path(conn, :index, project_2.id)
        )

      assert html =~ project_2.name
      assert view |> element("button", "#{project_2.name}") |> has_element?()

      assert view
             |> element(
               "a[href='#{Routes.project_workflow_path(conn, :index, project_1.id)}']"
             )
             |> has_element?()

      refute view
             |> element(
               "a[href='#{Routes.project_workflow_path(conn, :index, project_3.id)}']"
             )
             |> has_element?()

      assert live(
               conn,
               Routes.project_workflow_path(conn, :index, project_3.id)
             ) ==
               {:error, {:redirect, %{flash: %{"nav" => :no_access}, to: "/"}}}
    end
  end

  describe "projects settings page" do
    setup :register_and_log_in_user

    test "access project settings page", %{conn: conn, user: user} do
      {:ok, project} =
        Lightning.Projects.create_project(%{
          name: "project-1",
          project_users: [%{user_id: user.id}]
        })

      {:ok, _view, html} =
        live(
          conn,
          Routes.project_project_settings_path(conn, :index, project.id)
        )

      assert html =~ "Project settings"
    end

    test "project admin can view project collaboration page",
         %{
           conn: conn,
           user: user
         } do
      {:ok, project} =
        Lightning.Projects.create_project(%{
          name: "project-1",
          project_users: [%{user_id: user.id, role: :admin}]
        })

      project_users =
        Lightning.Projects.get_project_with_users!(project.id).project_users

      assert 1 == length(project_users)

      project_user = List.first(project_users)

      {:ok, _view, html} =
        live(
          conn,
          Routes.project_project_settings_path(conn, :index, project.id) <>
            "#collaboration"
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
      unauthenticated_user = user_fixture()

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
  end
end
