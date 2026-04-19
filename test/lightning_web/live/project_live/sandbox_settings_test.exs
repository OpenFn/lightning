defmodule LightningWeb.ProjectLive.SandboxSettingsTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  alias Lightning.Projects
  alias Lightning.Projects.Sandboxes

  setup :stub_usage_limiter_ok
  setup :register_and_log_in_user

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

    test "does not show any sandbox banners", %{conn: conn, parent: parent} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{parent.id}/settings")

      refute html =~ "sandbox-banner-"
    end

    test "shows 'Project Identity' header on project tab", %{
      conn: conn,
      parent: parent
    } do
      {:ok, _view, html} = live(conn, ~p"/projects/#{parent.id}/settings")
      assert html =~ "Project Identity"
      refute html =~ "Sandbox Identity"
    end

    test "shows the danger zone delete button", %{conn: conn, parent: parent} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{parent.id}/settings")
      assert html =~ "The danger zone"
      assert html =~ "Delete project"
    end

    test "shows webhook auth methods table on webhook_security tab", %{
      conn: conn,
      parent: parent
    } do
      {:ok, _view, html} = live(conn, ~p"/projects/#{parent.id}/settings")
      refute html =~ "Webhook authentication is managed in the parent project"
    end
  end

  describe "sandbox project" do
    setup [:setup_parent_and_sandbox]

    test "shows Editable banner on credentials and collections tabs", %{
      conn: conn,
      sandbox: sandbox
    } do
      {:ok, _view, html} = live(conn, ~p"/projects/#{sandbox.id}/settings")

      assert html =~ ~s(id="sandbox-banner-credentials")
      assert html =~ ~s(id="sandbox-banner-collections")

      assert html =~
               "Changes you make here will sync to the parent project on merge."
    end

    test "shows Local banner on project, collaboration, vcs, data-storage, history-exports tabs",
         %{conn: conn, sandbox: sandbox} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{sandbox.id}/settings")

      for tab <- ~w(project collaboration vcs data-storage history-exports) do
        assert html =~ ~s(id="sandbox-banner-#{tab}")
      end

      assert html =~
               "Changes you make here only apply to this sandbox and do not sync"
    end

    test "shows Inherited banner on security tab", %{
      conn: conn,
      sandbox: sandbox
    } do
      {:ok, _view, html} = live(conn, ~p"/projects/#{sandbox.id}/settings")

      assert html =~ ~s(id="sandbox-banner-security")
      assert html =~ "These settings are inherited from the parent project"
    end

    test "shows 'Sandbox Identity' header instead of 'Project Identity'", %{
      conn: conn,
      sandbox: sandbox
    } do
      {:ok, _view, html} = live(conn, ~p"/projects/#{sandbox.id}/settings")

      assert html =~ "Sandbox Identity"
      assert html =~ "Sandbox setup"
      assert html =~ "Identifies this sandbox within its parent:"
      assert html =~ "parent-project"
    end

    test "hides the danger zone delete button", %{conn: conn, sandbox: sandbox} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{sandbox.id}/settings")

      refute html =~ "The danger zone"
      refute html =~ "Delete project"
    end

    test "shows webhook security explanatory message instead of auth methods",
         %{conn: conn, sandbox: sandbox} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{sandbox.id}/settings")

      assert html =~ "Webhook authentication is managed in the parent project"
    end

    test "MFA toggle is disabled in sandbox", %{conn: conn, sandbox: sandbox} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{sandbox.id}/settings")
      html = render(view)

      assert html =~ ~s(id="toggle-mfa-switch")
      assert html =~ ~s(disabled)
      assert html =~ "cursor-not-allowed"
    end

    test "does not show the role permissions message on webhook_security or security tabs",
         %{conn: conn, sandbox: sandbox} do
      {:ok, _view, html} = live(conn, ~p"/projects/#{sandbox.id}/settings")

      refute html =~ "Role based permissions: You cannot modify"
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
                     Projects.delete_project_user!(sandbox_pu)
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
               Projects.delete_project_user!(sandbox_pu)
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
               Projects.delete_project_user!(pu)
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
