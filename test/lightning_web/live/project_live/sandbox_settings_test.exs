defmodule LightningWeb.ProjectLive.SandboxSettingsTest do
  use LightningWeb.ConnCase, async: true
  use Mimic

  import Phoenix.LiveViewTest
  import Lightning.Factories
  import LightningWeb.ProjectSettingsPageHelpers

  alias Lightning.Projects
  alias Lightning.Projects.Sandboxes

  # The page is drawn by React from data-props: a sandbox's banners,
  # headings and disabled controls come from `parent`, and are tested in
  # the design system's ProjectSettingsPage.test.tsx.

  setup :stub_usage_limiter_ok
  setup :register_and_log_in_user

  setup do
    Mimic.copy(Lightning.Projects.Sandboxes)
    :ok
  end

  defp setup_parent_and_sandbox(%{user: user}) do
    parent =
      insert(:project,
        name: "parent-project",
        project_users: [%{user: user, role: :owner}]
      )

    sandbox =
      insert(:project,
        name: "sandbox-test",
        parent: parent,
        project_users: [%{user: user, role: :owner}]
      )

    {:ok, parent: parent, sandbox: sandbox}
  end

  describe "non-sandbox project (parent project)" do
    setup [:setup_parent_and_sandbox]

    test "is drawn as a project, with no parent", %{conn: conn, parent: parent} do
      assert %{"parent" => nil, "project" => %{"parentId" => nil}} =
               conn |> open(parent) |> props()
    end

    test "its owner may delete it", %{conn: conn, parent: parent} do
      assert %{"setup" => %{"canDeleteProject" => true}} =
               conn |> open(parent) |> props()
    end

    test "an admin cannot delete the project, whole or scheduled",
         %{conn: conn, user: user} do
      root =
        insert(:project,
          name: "root-project",
          project_users: [%{user: user, role: :admin}]
        )

      workflow = insert(:workflow, project: root)
      view = open(conn, root)

      # The name matches, so only the role can refuse it.
      send_event(view, "delete_project", %{
        "nameConfirmation" => root.name
      })

      assert_refused(view)

      assert Lightning.Repo.reload(root)
      assert Lightning.Repo.reload(workflow)
      assert is_nil(Lightning.Repo.reload!(root).scheduled_deletion)
    end
  end

  describe "sandbox project" do
    setup [:setup_parent_and_sandbox]

    test "is drawn as a sandbox of its parent", %{
      conn: conn,
      sandbox: sandbox,
      parent: parent
    } do
      parent_id = parent.id
      settings_href = "/projects/#{parent.id}/settings"

      assert %{
               "project" => %{"parentId" => ^parent_id},
               "parent" => %{
                 "name" => "parent-project",
                 "settingsHref" => ^settings_href
               },
               "setup" => %{"canDeleteProject" => true}
             } = conn |> open(sandbox) |> props()
    end

    test "delete sandbox flow calls delete_sandbox and redirects to root project",
         %{conn: conn, sandbox: sandbox, parent: parent} do
      view = open(conn, sandbox, "settings/delete")

      send_event(view, "delete_project", %{
        "nameConfirmation" => sandbox.name
      })

      flash = assert_redirected(view, ~p"/projects/#{parent.id}/w")
      assert flash["info"] =~ "and all its associated descendants deleted"
      assert is_nil(Lightning.Projects.get_project(sandbox.id))
    end

    test "a wrong name does not delete and replies the error",
         %{conn: conn, sandbox: sandbox} do
      view = open(conn, sandbox, "settings/delete")

      send_event(view, "delete_project", %{
        "nameConfirmation" => "wrong"
      })

      assert_reply(view, %{error: "does not match the sandbox name"})
      assert Lightning.Projects.get_project(sandbox.id)
    end

    test "the delete modal opens only at its own address",
         %{conn: conn, sandbox: sandbox} do
      assert %{"deleting" => true} =
               conn |> open(sandbox, "settings/delete") |> props()

      assert %{"deleting" => false} =
               conn |> open(sandbox) |> props()
    end

    test "unauthorized sandbox delete replies an error and keeps the sandbox",
         %{conn: conn, sandbox: sandbox} do
      view = open(conn, sandbox, "settings/delete")

      # The context refuses although the page's own role check let it through.
      Mimic.expect(Lightning.Projects.Sandboxes, :delete_sandbox, fn _, _ ->
        {:error, :unauthorized}
      end)

      send_event(view, "delete_project", %{
        "nameConfirmation" => sandbox.name
      })

      assert_reply(view, %{
        error: "You don't have permission to delete this sandbox"
      })

      assert Lightning.Projects.get_project(sandbox.id)
    end

    test "unexpected sandbox delete error replies a generic error",
         %{conn: conn, sandbox: sandbox} do
      view = open(conn, sandbox, "settings/delete")

      Mimic.expect(Lightning.Projects.Sandboxes, :delete_sandbox, fn _, _ ->
        {:error, :boom}
      end)

      send_event(view, "delete_project", %{
        "nameConfirmation" => sandbox.name
      })

      assert_reply(view, %{
        error: "Could not delete sandbox. Please try again later."
      })

      assert Lightning.Projects.get_project(sandbox.id)
    end
  end

  describe "Sandboxes.parent_admin?/2" do
    test "returns true when user is admin on direct parent" do
      user = insert(:user)
      parent = insert(:project, project_users: [%{user: user, role: :admin}])
      sandbox = insert(:project, parent: parent, project_users: [])

      assert Sandboxes.parent_admin?(sandbox, user)
    end

    test "returns true when user is owner on direct parent" do
      user = insert(:user)
      parent = insert(:project, project_users: [%{user: user, role: :owner}])
      sandbox = insert(:project, parent: parent, project_users: [])

      assert Sandboxes.parent_admin?(sandbox, user)
    end

    test "returns false when user is editor on parent" do
      user = insert(:user)
      parent = insert(:project, project_users: [%{user: user, role: :editor}])
      sandbox = insert(:project, parent: parent, project_users: [])

      refute Sandboxes.parent_admin?(sandbox, user)
    end

    test "returns false when user has no role on parent" do
      user = insert(:user)
      parent = insert(:project, project_users: [])
      sandbox = insert(:project, parent: parent, project_users: [])

      refute Sandboxes.parent_admin?(sandbox, user)
    end

    test "walks the chain — admin on grandparent counts" do
      user = insert(:user)

      grandparent =
        insert(:project, project_users: [%{user: user, role: :admin}])

      parent = insert(:project, parent: grandparent, project_users: [])
      sandbox = insert(:project, parent: parent, project_users: [])

      assert Sandboxes.parent_admin?(sandbox, user)
    end

    test "returns false for projects with no parent" do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user, role: :admin}])

      refute Sandboxes.parent_admin?(project, user)
    end

    test "returns false when parent_id points to a deleted project" do
      # Race condition: in-memory sandbox struct has a parent_id that
      # was nilified in the database after we loaded the struct (because
      # the parent project was deleted). The function should treat the
      # missing ancestor as no ancestor, not crash.
      user = insert(:user)
      sandbox = insert(:project)
      stale_parent_id = Ecto.UUID.generate()
      stale_sandbox = %{sandbox | parent_id: stale_parent_id}

      refute Sandboxes.parent_admin?(stale_sandbox, user)
    end
  end

  describe "delete_project_user! parent admin protection" do
    test "raises when removing a parent admin from a sandbox" do
      admin = insert(:user)
      other = insert(:user)

      parent =
        insert(:project,
          project_users: [
            %{user: admin, role: :admin},
            %{user: other, role: :owner}
          ]
        )

      sandbox =
        insert(:project,
          parent: parent,
          project_users: [
            %{user: admin, role: :editor},
            %{user: other, role: :owner}
          ]
        )

      sandbox_pu = Projects.get_project_user(sandbox, admin)

      assert_raise ArgumentError,
                   ~r/Cannot remove a parent project admin/,
                   fn ->
                     Projects.delete_project_user!(sandbox_pu, insert(:user))
                   end
    end

    test "allows removing a non-parent-admin from a sandbox" do
      regular = insert(:user)
      owner = insert(:user)

      parent =
        insert(:project, project_users: [%{user: owner, role: :owner}])

      sandbox =
        insert(:project,
          parent: parent,
          project_users: [
            %{user: regular, role: :editor},
            %{user: owner, role: :owner}
          ]
        )

      sandbox_pu = Projects.get_project_user(sandbox, regular)

      assert %Lightning.Projects.ProjectUser{} =
               Projects.delete_project_user!(sandbox_pu, insert(:user))
    end

    test "allows removing any user from a non-sandbox project" do
      admin = insert(:user)
      other = insert(:user)

      project =
        insert(:project,
          project_users: [
            %{user: admin, role: :admin},
            %{user: other, role: :owner}
          ]
        )

      pu = Projects.get_project_user(project, admin)

      assert %Lightning.Projects.ProjectUser{} =
               Projects.delete_project_user!(pu, insert(:user))
    end
  end

  describe "Remove Collaborator UI guard for parent admins" do
    test "Remove button is disabled for a parent admin in sandbox", %{
      conn: conn,
      user: user
    } do
      parent_admin = insert(:user, email: "parent-admin@example.com")

      parent =
        insert(:project,
          project_users: [
            %{user: user, role: :owner},
            %{user: parent_admin, role: :admin}
          ]
        )

      sandbox =
        insert(:project,
          parent: parent,
          project_users: [
            %{user: user, role: :owner},
            %{user: parent_admin, role: :editor}
          ]
        )

      {:ok, _view, html} = live(conn, ~p"/projects/#{sandbox.id}/settings")

      assert html =~
               "Cannot remove a user who is admin or owner on the parent project"
    end
  end
end
