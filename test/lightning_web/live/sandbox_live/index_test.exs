defmodule LightningWeb.SandboxLive.IndexTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories
  import Ecto.Query

  alias Lightning.Repo
  alias Lightning.Projects.Project

  use Mimic

  setup_all do
    Mimic.copy(Lightning.Projects)
    Mimic.copy(Lightning.Projects.Sandboxes)

    Mimic.stub_with(Lightning.Projects, Lightning.Projects)
    Mimic.stub_with(Lightning.Projects.Sandboxes, Lightning.Projects.Sandboxes)
    :ok
  end

  describe "Index (user logged in)" do
    setup :register_and_log_in_user

    setup %{user: user} do
      parent =
        insert(:project,
          name: "parent",
          env: nil,
          project_users: [%{user: user, role: :owner}]
        )

      sb1 =
        insert(:project,
          name: "sb-1",
          color: "#ff0000",
          env: "staging",
          parent: parent,
          project_users: [%{user: user, role: :owner}]
        )

      sb2 =
        insert(:project,
          name: "sb-2",
          color: "#00ff00",
          env: "dev",
          parent: parent,
          project_users: [%{user: user, role: :owner}]
        )

      sb_no_env =
        insert(:project,
          name: "sb-no-env",
          color: "#0000ff",
          env: nil,
          parent: parent,
          project_users: [%{user: user, role: :owner}]
        )

      {:ok, parent: parent, sb1: sb1, sb2: sb2, sb_no_env: sb_no_env}
    end

    test "lists sandboxes; empty state shows message", %{
      conn: conn,
      parent: parent,
      sb1: sb1,
      sb2: sb2,
      sb_no_env: sb_no_env
    } do
      {:ok, view, html} =
        live(conn, ~p"/projects/#{parent.id}/sandboxes", on_error: :raise)

      assert html =~ "Sandboxes"
      assert has_element?(view, "#edit-sandbox-#{sb1.id}")
      assert has_element?(view, "#edit-sandbox-#{sb2.id}")

      for sandbox <- [sb1, sb2, sb_no_env] do
        from(pu in Lightning.Projects.ProjectUser,
          where: pu.project_id == ^sandbox.id
        )
        |> Repo.delete_all()

        Repo.delete!(sandbox)
      end

      html2 = render_patch(view, ~p"/projects/#{parent.id}/sandboxes")
      assert html2 =~ "No sandboxes found"
    end

    test "root project without environment shows 'main' badge", %{
      conn: conn,
      parent: parent
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      badge = element(view, "#env-badge-#{parent.id}")

      assert render(badge) =~ "main"
    end

    test "root project with environment shows env badge with actual environment",
         %{
           conn: conn,
           user: user
         } do
      parent_with_env =
        insert(:project,
          name: "parent-with-env",
          env: "production",
          project_users: [%{user: user, role: :owner}]
        )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{parent_with_env.id}/sandboxes")

      badge = element(view, "#env-badge-#{parent_with_env.id}")

      assert render(badge) =~ "production"
      refute render(badge) =~ "main"
    end

    test "sandbox with environment shows env badge, sandbox without env shows no badge",
         %{
           conn: conn,
           parent: parent,
           sb1: sb1,
           sb_no_env: sb_no_env
         } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      badge = element(view, "#env-badge-#{sb1.id}")

      assert render(badge) =~ "staging"

      refute element(view, "#env-badge-#{sb_no_env.id}") |> has_element?()
    end

    test "current sandbox shows active badge", %{
      conn: conn,
      parent: parent,
      sb1: _sb1
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      env_badge = element(view, "#env-badge-#{parent.id}")
      active_badge = element(view, "#active-badge-#{parent.id}")

      assert render(env_badge) =~ "main"
      assert render(active_badge) =~ "active"
    end

    test "delete modal shows redirect warning when deleting current project", %{
      conn: conn,
      parent: parent,
      sb1: sb1,
      user: _user
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{sb1.id}/sandboxes")

      view |> element("#delete-sandbox-#{sb1.id} button") |> render_click()

      html = render(view)

      assert html =~ "You are currently viewing this project"
      assert html =~ "you&#39;ll be redirected to"
      assert html =~ "#{parent.name}"
    end

    test "delete modal without redirect warning when not deleting current project",
         %{
           conn: conn,
           parent: parent,
           sb1: sb1
         } do
      {:ok, view, _} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      view |> element("#delete-sandbox-#{sb1.id} button") |> render_click()

      html = render(view)

      refute html =~ "You are currently viewing this project"
      refute html =~ "After deletion, you'll be redirected to"
    end

    test "navigates to new sandbox modal from header button", %{
      conn: conn,
      parent: parent
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      view |> element("#create-sandbox-button") |> render_click()

      assert_patch(view, ~p"/projects/#{parent.id}/sandboxes/new")
      assert has_element?(view, "#sandbox-form-new")
      assert render(view) =~ "Create a new sandbox"
    end

    test "navigates to edit modal via card action", %{
      conn: conn,
      parent: parent,
      sb1: sb1
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      view |> element("#edit-sandbox-#{sb1.id} button") |> render_click()

      assert_patch(view, ~p"/projects/#{parent.id}/sandboxes/#{sb1.id}/edit")
      assert has_element?(view, "#sandbox-form-#{sb1.id}")
      assert render(view) =~ "Edit sandbox"
    end

    test "delete modal open/validate/close UX", %{
      conn: conn,
      parent: parent,
      sb1: sb1
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      view |> element("#delete-sandbox-#{sb1.id} button") |> render_click()
      assert has_element?(view, "#confirm-delete-sandbox")

      view
      |> form("#confirm-delete-sandbox form", confirm: %{"name" => "wrong"})
      |> render_change()

      refute view
             |> element(
               "#confirm-delete-sandbox button[type=\"submit\"]:not([disabled])"
             )
             |> has_element?()

      view
      |> element("#confirm-delete-sandbox [aria-label='Close']")
      |> render_click()

      refute has_element?(view, "#confirm-delete-sandbox")
    end

    test "confirm-delete result paths: ok, unauthorized, not_found, generic error",
         %{conn: conn, parent: parent, sb1: sb1, sb2: sb2, user: user} do
      {:ok, view, _} =
        live(conn, ~p"/projects/#{parent.id}/sandboxes", on_error: :raise)

      Mimic.expect(Lightning.Projects, :delete_sandbox, fn %Project{id: id},
                                                           user_arg ->
        assert id == sb1.id
        assert user_arg.id == user.id
        {:ok, %Project{}}
      end)

      Mimic.expect(Lightning.Projects, :list_workspace_projects, fn id ->
        assert id == parent.id

        %{
          root: parent,
          descendants: [sb2]
        }
      end)

      Mimic.allow(Lightning.Projects, self(), view.pid)

      view |> element("#delete-sandbox-#{sb1.id} button") |> render_click()

      html =
        view
        |> form("#confirm-delete-sandbox form", confirm: %{"name" => sb1.name})
        |> render_submit()

      assert html =~
               "Sandbox #{sb1.name} and all its associated descendants deleted"

      assert has_element?(view, "#edit-sandbox-#{sb2.id}")

      target_id = sb2.id

      Mimic.expect(Lightning.Projects, :delete_sandbox, fn %Project{
                                                             id: ^target_id
                                                           },
                                                           user_arg ->
        assert user_arg.id == user.id
        {:error, :unauthorized}
      end)

      Mimic.allow(Lightning.Projects, self(), view.pid)

      view |> element("#delete-sandbox-#{target_id} button") |> render_click()

      html =
        view
        |> form("#confirm-delete-sandbox form", confirm: %{"name" => sb2.name})
        |> render_submit()

      assert html =~ "You don&#39;t have permission to delete this sandbox"

      Mimic.expect(Lightning.Projects, :delete_sandbox, fn %Project{
                                                             id: ^target_id
                                                           },
                                                           user_arg ->
        assert user_arg.id == user.id
        {:error, :not_found}
      end)

      Mimic.allow(Lightning.Projects, self(), view.pid)

      view |> element("#delete-sandbox-#{target_id} button") |> render_click()

      html =
        view
        |> form("#confirm-delete-sandbox form", confirm: %{"name" => sb2.name})
        |> render_submit()

      assert html =~ "Sandbox not found"

      Mimic.expect(Lightning.Projects, :delete_sandbox, fn %Project{
                                                             id: ^target_id
                                                           },
                                                           user_arg ->
        assert user_arg.id == user.id
        {:error, :boom}
      end)

      Mimic.allow(Lightning.Projects, self(), view.pid)

      view |> element("#delete-sandbox-#{target_id} button") |> render_click()

      html =
        view
        |> form("#confirm-delete-sandbox form", confirm: %{"name" => sb2.name})
        |> render_submit()

      assert html =~ "Failed to delete sandbox: "
    end

    test "open-delete-modal with unknown id shows flash", %{
      conn: conn,
      parent: parent
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      bad_id = Ecto.UUID.generate()
      html = render_click(view, "open-delete-modal", %{"id" => bad_id})

      assert html =~ "Sandbox not found"
      refute has_element?(view, "#confirm-delete-sandbox")
    end

    test "confirm-delete-validate with empty params keeps modal open", %{
      conn: conn,
      parent: parent,
      sb1: sb1
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      view |> element("#delete-sandbox-#{sb1.id} button") |> render_click()
      assert has_element?(view, "#confirm-delete-sandbox")

      _html_before = render(view)

      _html_after =
        view |> element("#confirm-delete-sandbox form") |> render_change(%{})

      assert has_element?(view, "#confirm-delete-sandbox")
    end

    test "confirm-delete with empty params keeps modal open", %{
      conn: conn,
      parent: parent,
      sb1: sb1
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      view |> element("#delete-sandbox-#{sb1.id} button") |> render_click()
      assert has_element?(view, "#confirm-delete-sandbox")

      _html =
        view |> element("#confirm-delete-sandbox form") |> render_submit(%{})

      assert has_element?(view, "#confirm-delete-sandbox")
    end

    test "close-delete-modal resets assigns", %{
      conn: conn,
      parent: parent,
      sb1: sb1
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      view |> element("#delete-sandbox-#{sb1.id} button") |> render_click()
      assert has_element?(view, "#confirm-delete-sandbox")

      view
      |> element("#confirm-delete-sandbox [aria-label='Close']")
      |> render_click()

      refute has_element?(view, "#confirm-delete-sandbox")

      view |> element("#delete-sandbox-#{sb1.id} button") |> render_click()
      assert has_element?(view, "#confirm-delete-sandbox")

      view
      |> form("#confirm-delete-sandbox form", confirm: %{"name" => "nope"})
      |> render_change()

      refute view
             |> element(
               ~s/#confirm-delete-sandbox button[type="submit"]:not([disabled])/
             )
             |> has_element?()
    end

    test "confirm-delete-validate ignores event when no sandbox selected" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          confirm_delete_sandbox: nil,
          confirm_changeset: :sentinel,
          confirm_delete_input: ""
        }
      }

      {:noreply, socket} =
        LightningWeb.SandboxLive.Index.handle_event(
          "confirm-delete-validate",
          %{"confirm" => %{}},
          socket
        )

      assert socket.assigns.confirm_changeset == :sentinel
      assert socket.assigns.confirm_delete_input == ""
    end

    test "confirm-delete ignores event when no sandbox selected" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          project: %Lightning.Projects.Project{id: Ecto.UUID.generate()},
          current_user: %Lightning.Accounts.User{id: Ecto.UUID.generate()},
          confirm_delete_sandbox: nil,
          confirm_changeset: :sentinel
        }
      }

      {:noreply, sock2} =
        LightningWeb.SandboxLive.Index.handle_event(
          "confirm-delete",
          %{"confirm" => %{}},
          socket
        )

      assert sock2.assigns == socket.assigns
    end
  end

  describe "Authorization scenarios for action buttons" do
    setup :register_and_log_in_user

    setup %{user: owner_user} do
      viewer_user = insert(:user)

      parent =
        insert(:project,
          name: "parent",
          project_users: [
            %{user: owner_user, role: :owner},
            %{user: viewer_user, role: :viewer}
          ]
        )

      sandbox =
        insert(:project,
          name: "test-sandbox",
          parent: parent,
          project_users: [
            %{user: owner_user, role: :owner},
            %{user: viewer_user, role: :viewer}
          ]
        )

      {:ok,
       owner_user: owner_user,
       viewer_user: viewer_user,
       parent: parent,
       sandbox: sandbox}
    end

    test "edit button disabled state for unauthorized user", %{
      conn: conn,
      viewer_user: viewer_user,
      parent: parent,
      sandbox: _sandbox
    } do
      conn = log_in_user(conn, viewer_user)
      {:ok, _view, html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      assert html =~ ~s(cursor-not-allowed)
      assert html =~ ~s(text-slate-300)
      assert html =~ "You are not authorized to edit this sandbox"
    end

    test "edit button enabled state for authorized user", %{
      conn: conn,
      owner_user: owner_user,
      parent: parent,
      sandbox: _sandbox
    } do
      conn = log_in_user(conn, owner_user)
      {:ok, _view, html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      assert html =~ ~s(hover:bg-slate-100)
      assert html =~ ~s(text-slate-700)
      assert html =~ "Edit this sandbox"
    end

    test "delete button disabled state for unauthorized user", %{
      conn: conn,
      viewer_user: viewer_user,
      parent: parent,
      sandbox: _sandbox
    } do
      conn = log_in_user(conn, viewer_user)
      {:ok, _view, html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      assert html =~ "You are not authorized to delete this sandbox"
      assert html =~ ~s(cursor-not-allowed)
    end

    test "delete button enabled state for authorized user", %{
      conn: conn,
      owner_user: owner_user,
      parent: parent,
      sandbox: _sandbox
    } do
      conn = log_in_user(conn, owner_user)
      {:ok, _view, html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      assert html =~ "Delete this sandbox"
      assert html =~ ~s(hover:bg-slate-100)
    end
  end

  describe "Handle params authorization coverage" do
    setup :register_and_log_in_user

    setup %{user: owner_user} do
      viewer_user = insert(:user)

      parent =
        insert(:project,
          name: "parent",
          project_users: [
            %{user: owner_user, role: :owner},
            %{user: viewer_user, role: :viewer}
          ]
        )

      sandbox =
        insert(:project,
          name: "test-sandbox",
          parent: parent,
          project_users: [
            %{user: owner_user, role: :owner},
            %{user: viewer_user, role: :viewer}
          ]
        )

      {:ok,
       owner_user: owner_user,
       viewer_user: viewer_user,
       parent: parent,
       sandbox: sandbox}
    end

    test "edit route unauthorized redirects with flash", %{
      conn: conn,
      viewer_user: viewer_user,
      parent: parent,
      sandbox: sandbox
    } do
      conn = log_in_user(conn, viewer_user)

      result =
        live(conn, ~p"/projects/#{parent.id}/sandboxes/#{sandbox.id}/edit")

      assert {:error, {:live_redirect, %{to: redirect_path, flash: flash}}} =
               result

      assert redirect_path == "/projects/#{parent.id}/sandboxes"
      assert flash["error"] == "You are not authorized to edit this sandbox"
    end

    test "new route unauthorized redirects with flash", %{
      conn: conn,
      viewer_user: viewer_user,
      parent: parent
    } do
      conn = log_in_user(conn, viewer_user)

      result = live(conn, ~p"/projects/#{parent.id}/sandboxes/new")

      assert {:error, {:live_redirect, %{to: redirect_path, flash: flash}}} =
               result

      assert redirect_path == "/projects/#{parent.id}/sandboxes"

      assert flash["error"] ==
               "You are not authorized to create sandboxes in this workspace"
    end

    test "edit route with non-existent sandbox shows error", %{
      conn: conn,
      parent: parent
    } do
      fake_id = Ecto.UUID.generate()

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{parent.id}/sandboxes/#{fake_id}/edit")

      assert html =~ "Sandbox not found"
    end
  end

  describe "Delete sandbox with descendant checking" do
    setup :register_and_log_in_user

    setup %{user: user} do
      parent =
        insert(:project,
          name: "parent",
          project_users: [%{user: user, role: :owner}]
        )

      child_sandbox =
        insert(:project,
          name: "child-sandbox",
          parent: parent,
          project_users: [%{user: user, role: :owner}]
        )

      grandchild_sandbox =
        insert(:project,
          name: "grandchild-sandbox",
          parent: child_sandbox,
          project_users: [%{user: user, role: :owner}]
        )

      {:ok,
       parent: parent,
       child_sandbox: child_sandbox,
       grandchild_sandbox: grandchild_sandbox}
    end

    test "deleting sandbox redirects when current project is descendant", %{
      conn: conn,
      parent: parent,
      child_sandbox: child_sandbox,
      grandchild_sandbox: grandchild_sandbox,
      user: user
    } do
      {:ok, view, _} =
        live(conn, ~p"/projects/#{grandchild_sandbox.id}/sandboxes")

      Mimic.expect(Lightning.Projects, :delete_sandbox, fn sandbox, user_arg ->
        assert sandbox.id == child_sandbox.id
        assert user_arg.id == user.id
        {:ok, %Project{}}
      end)

      Mimic.expect(Lightning.Projects, :descendant_of?, fn current,
                                                           deleted,
                                                           root ->
        assert current.id == grandchild_sandbox.id
        assert deleted.id == child_sandbox.id
        assert root.id == parent.id
        true
      end)

      Mimic.allow(Lightning.Projects, self(), view.pid)

      view
      |> element("#delete-sandbox-#{child_sandbox.id} button")
      |> render_click()

      view
      |> form("#confirm-delete-sandbox form",
        confirm: %{"name" => child_sandbox.name}
      )
      |> render_submit()

      assert_redirect(view, ~p"/projects/#{parent.id}/w")
    end

    test "deleting sandbox does not redirect when current project is not descendant",
         %{
           conn: conn,
           parent: parent,
           child_sandbox: child_sandbox,
           user: _user
         } do
      {:ok, view, _} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      Mimic.expect(Lightning.Projects, :delete_sandbox, fn sandbox, _user_arg ->
        assert sandbox.id == child_sandbox.id
        {:ok, %Project{}}
      end)

      Mimic.expect(Lightning.Projects, :list_workspace_projects, fn id ->
        assert id == parent.id
        %{root: parent, descendants: []}
      end)

      Mimic.allow(Lightning.Projects, self(), view.pid)

      view
      |> element("#delete-sandbox-#{child_sandbox.id} button")
      |> render_click()

      html =
        view
        |> form("#confirm-delete-sandbox form",
          confirm: %{"name" => child_sandbox.name}
        )
        |> render_submit()

      assert html =~ "Sandboxes"
      assert html =~ parent.name
      assert render(view) =~ "Sandboxes"
    end
  end
end
