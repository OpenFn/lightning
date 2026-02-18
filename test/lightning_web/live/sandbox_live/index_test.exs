defmodule LightningWeb.SandboxLive.IndexTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories
  import Lightning.GithubHelpers
  import Ecto.Query

  alias Lightning.Repo
  alias Lightning.Projects.Project

  use Mimic

  setup_all do
    Mimic.copy(Lightning.Projects)
    Mimic.copy(Lightning.Projects.Sandboxes)
    Mimic.copy(Lightning.Projects.MergeProjects)
    Mimic.copy(Lightning.Projects.Provisioner)

    Mimic.stub_with(Lightning.Projects, Lightning.Projects)
    Mimic.stub_with(Lightning.Projects.Sandboxes, Lightning.Projects.Sandboxes)

    Mimic.stub_with(
      Lightning.Projects.MergeProjects,
      Lightning.Projects.MergeProjects
    )

    Mimic.stub_with(
      Lightning.Projects.Provisioner,
      Lightning.Projects.Provisioner
    )

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

    test "create sandbox button is disabled when the limiter returns error", %{
      conn: conn,
      parent: %{id: parent_id} = parent,
      test: test
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      assert has_element?(view, "button#create-sandbox-button")
      refute has_element?(view, "button#create-sandbox-button:disabled")

      error_message = "error-#{test}"

      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn
          %{type: :new_sandbox, amount: 1}, %{project_id: ^parent_id} ->
            {:error, :exceeded_limit, %{text: error_message}}

          _action, _context ->
            :ok
        end
      )

      {:ok, view, _} = live(conn, ~p"/projects/#{parent.id}/sandboxes")
      assert has_element?(view, "button#create-sandbox-button:disabled")

      assert view |> render() =~ error_message
    end

    test "visiting /new redirects back to index incase the limiter returns error",
         %{
           conn: conn,
           parent: %{id: parent_id} = parent,
           test: test
         } do
      error_message = "error-#{test}"

      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn
          %{type: :new_sandbox, amount: 1}, %{project_id: ^parent_id} ->
            {:error, :exceeded_limit, %{text: error_message}}

          _action, _context ->
            :ok
        end
      )

      assert {:error, {:live_redirect, redirect}} =
               live(conn, ~p"/projects/#{parent.id}/sandboxes/new")

      assert redirect[:to] == ~p"/projects/#{parent.id}/sandboxes"
      assert redirect[:flash]["error"] == error_message
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

  describe "Merge modal functionality" do
    setup :register_and_log_in_user

    setup %{user: user} do
      # Create a hierarchy:
      # root
      # ├── child1
      # │   ├── grandchild1
      # │   └── grandchild2
      # ├── child2
      # └── child3

      root =
        insert(:project,
          name: "root",
          project_users: [%{user: user, role: :owner}]
        )

      child1 =
        insert(:project,
          name: "child1",
          parent: root,
          project_users: [%{user: user, role: :owner}]
        )

      child2 =
        insert(:project,
          name: "child2",
          parent: root,
          project_users: [%{user: user, role: :owner}]
        )

      child3 =
        insert(:project,
          name: "child3",
          parent: root,
          project_users: [%{user: user, role: :owner}]
        )

      grandchild1 =
        insert(:project,
          name: "grandchild1",
          parent: child1,
          project_users: [%{user: user, role: :owner}]
        )

      grandchild2 =
        insert(:project,
          name: "grandchild2",
          parent: child1,
          project_users: [%{user: user, role: :owner}]
        )

      {:ok,
       root: root,
       child1: child1,
       child2: child2,
       child3: child3,
       grandchild1: grandchild1,
       grandchild2: grandchild2}
    end

    test "merge button opens modal", %{conn: conn, root: root, child1: child1} do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      view
      |> element("#branch-rewire-sandbox-#{child1.id} button")
      |> render_click()

      assert has_element?(view, "#merge-sandbox-modal")
      assert render(view) =~ "Merge"
      assert render(view) =~ child1.name
    end

    test "merge modal shows all valid targets excluding descendants", %{
      conn: conn,
      root: root,
      child1: child1
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      view
      |> element("#branch-rewire-sandbox-#{child1.id} button")
      |> render_click()

      dropdown_html =
        view
        |> element("#merge-target-select")
        |> render()

      assert dropdown_html =~ root.name
      assert dropdown_html =~ "child2"
      assert dropdown_html =~ "child3"

      refute dropdown_html =~ "child1"
      refute dropdown_html =~ "grandchild1"
      refute dropdown_html =~ "grandchild2"
    end

    test "merge modal defaults to parent as target", %{
      conn: conn,
      root: root,
      child1: child1
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      view
      |> element("#branch-rewire-sandbox-#{child1.id} button")
      |> render_click()

      hidden_input =
        view
        |> element("input[type=hidden][name='merge[target_id]']")
        |> render()

      assert hidden_input =~ root.id
    end

    test "merge modal shows no descendants warning for leaf sandbox", %{
      conn: conn,
      root: root,
      child2: child2
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      view
      |> element("#branch-rewire-sandbox-#{child2.id} button")
      |> render_click()

      html = render(view)

      refute html =~ "Child sandboxes will be closed"
      refute html =~ "will also be closed"
    end

    test "merge modal shows single descendant warning", %{
      conn: conn,
      root: root,
      grandchild1: grandchild1,
      user: user
    } do
      great_grandchild =
        insert(:project,
          name: "great-grandchild",
          parent: grandchild1,
          project_users: [%{user: user, role: :owner}]
        )

      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      view
      |> element("#branch-rewire-sandbox-#{grandchild1.id} button")
      |> render_click()

      html = render(view)

      assert html =~ great_grandchild.name
      assert html =~ "will also be closed"
      assert html =~ "Consider merging it into"
    end

    test "merge modal shows multiple descendants warning with full list", %{
      conn: conn,
      root: root,
      child1: child1
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      view
      |> element("#branch-rewire-sandbox-#{child1.id} button")
      |> render_click()

      html = render(view)

      assert html =~ "Child sandboxes will be closed"
      assert html =~ "2 sandboxes will be permanently closed"

      assert html =~ "grandchild1"
      assert html =~ "grandchild2"

      assert html =~ "Consider merging child sandboxes into"
      assert html =~ child1.name
    end

    test "merge modal shows correct dropdown options", %{
      conn: conn,
      root: root,
      child1: child1,
      child2: child2,
      child3: child3
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      view
      |> element("#branch-rewire-sandbox-#{child1.id} button")
      |> render_click()

      assert view
             |> element("input[type=hidden][name='merge[target_id]']")
             |> render() =~ root.id

      dropdown = view |> element("#merge-target-select") |> render()

      assert dropdown =~ root.name
      assert dropdown =~ child2.name
      assert dropdown =~ child3.name
      refute dropdown =~ child1.name
      refute dropdown =~ "grandchild"
    end

    test "close merge modal resets state", %{
      conn: conn,
      root: root,
      child1: child1
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      view
      |> element("#branch-rewire-sandbox-#{child1.id} button")
      |> render_click()

      assert has_element?(view, "#merge-sandbox-modal")

      view
      |> element("#merge-sandbox-modal [aria-label='Close']")
      |> render_click()

      refute has_element?(view, "#merge-sandbox-modal")

      view
      |> element("#branch-rewire-sandbox-#{child1.id} button")
      |> render_click()

      hidden_input =
        view
        |> element("input[type=hidden][name='merge[target_id]']")
        |> render()

      assert hidden_input =~ root.id
    end

    test "merge modal shows error for non-existent sandbox", %{
      conn: conn,
      root: root
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      fake_id = Ecto.UUID.generate()
      html = render_click(view, "open-merge-modal", %{"id" => fake_id})

      assert html =~ "Sandbox not found"
      refute has_element?(view, "#merge-sandbox-modal")
    end

    test "merge button works for sandbox with no siblings", %{
      conn: conn,
      root: root,
      grandchild1: grandchild1,
      child1: child1
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      view
      |> element("#branch-rewire-sandbox-#{grandchild1.id} button")
      |> render_click()

      assert has_element?(view, "#merge-sandbox-modal")

      hidden_input =
        view
        |> element("input[type=hidden][name='merge[target_id]']")
        |> render()

      assert hidden_input =~ child1.id
    end

    test "confirm merge executes successfully", %{
      conn: conn,
      root: root,
      child1: child1,
      user: user
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      Mimic.expect(
        Lightning.Projects.MergeProjects,
        :merge_project,
        fn source, target ->
          assert source.id == child1.id
          assert target.id == root.id
          "merged_yaml"
        end
      )

      Mimic.expect(
        Lightning.Projects.Provisioner,
        :import_document,
        fn target, actor, yaml, opts ->
          assert target.id == root.id
          assert actor.id == user.id
          assert yaml == "merged_yaml"
          assert opts[:allow_stale] == true
          {:ok, target}
        end
      )

      Mimic.expect(Lightning.Projects, :delete_sandbox, fn source, actor ->
        assert source.id == child1.id
        assert actor.id == user.id
        {:ok, source}
      end)

      Mimic.allow(Lightning.Projects.MergeProjects, self(), view.pid)
      Mimic.allow(Lightning.Projects.Provisioner, self(), view.pid)
      Mimic.allow(Lightning.Projects, self(), view.pid)

      view
      |> element("#branch-rewire-sandbox-#{child1.id} button")
      |> render_click()

      view
      |> form("#merge-sandbox-modal form")
      |> render_submit()

      assert_redirect(view, ~p"/projects/#{root.id}/w")
    end

    test "merge shows error on merge failure", %{
      conn: conn,
      root: root,
      child1: child1
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      Mimic.expect(
        Lightning.Projects.MergeProjects,
        :merge_project,
        fn _source, _target ->
          "merged_yaml"
        end
      )

      Mimic.expect(
        Lightning.Projects.Provisioner,
        :import_document,
        fn _target, _actor, _yaml, _opts ->
          {:error, :import_failed}
        end
      )

      Mimic.allow(Lightning.Projects.MergeProjects, self(), view.pid)
      Mimic.allow(Lightning.Projects.Provisioner, self(), view.pid)

      view
      |> element("#branch-rewire-sandbox-#{child1.id} button")
      |> render_click()

      view
      |> form("#merge-sandbox-modal form")
      |> render_submit()

      html = render(view)

      assert html =~ "Failed to merge"

      refute has_element?(view, "#merge-sandbox-modal")
    end

    test "merge modal shows beta warning", %{
      conn: conn,
      root: root,
      child1: child1
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      view
      |> element("#branch-rewire-sandbox-#{child1.id} button")
      |> render_click()

      html = render(view)

      assert html =~ "Beta"
      assert html =~ "use the CLI to merge locally"
    end

    test "descendants are calculated correctly for deep nesting", %{
      conn: conn,
      root: root,
      child1: child1,
      grandchild1: grandchild1,
      user: user
    } do
      _great_grandchild1 =
        insert(:project,
          name: "great-grandchild1",
          parent: grandchild1,
          project_users: [%{user: user, role: :owner}]
        )

      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      view
      |> element("#branch-rewire-sandbox-#{child1.id} button")
      |> render_click()

      html = render(view)

      assert html =~ "sandboxes will be permanently closed"
      assert html =~ "grandchild1"
      assert html =~ "grandchild2"
      assert html =~ "3 sandboxes will be permanently closed"
    end

    test "sibling can be selected as merge target", %{
      conn: conn,
      root: root,
      child1: child1,
      child3: child3
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      view
      |> element("#branch-rewire-sandbox-#{child1.id} button")
      |> render_click()

      html = render(view)

      assert html =~ child3.name
    end

    test "grandparent can be selected as merge target", %{
      conn: conn,
      root: root,
      grandchild1: grandchild1
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      view
      |> element("#branch-rewire-sandbox-#{grandchild1.id} button")
      |> render_click()

      html = render(view)

      assert html =~ root.name
    end

    test "cannot merge into own child", %{
      conn: conn,
      root: root,
      child1: child1,
      grandchild1: grandchild1
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      view
      |> element("#branch-rewire-sandbox-#{child1.id} button")
      |> render_click()

      dropdown_html =
        view
        |> element("#merge-target-select")
        |> render()

      refute dropdown_html =~ grandchild1.name
    end

    test "select-merge-target updates changeset", %{
      conn: conn,
      root: root,
      child1: child1,
      child2: child2
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      view
      |> element("#branch-rewire-sandbox-#{child1.id} button")
      |> render_click()

      # Change target selection
      render_click(view, "select-merge-target", %{
        "merge" => %{"target_id" => child2.id}
      })

      # Verify changeset updated
      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.merge_changeset.changes.target_id == child2.id
    end

    test "shows error when target project not found during merge", %{
      conn: conn,
      root: root,
      child1: child1
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      view
      |> element("#branch-rewire-sandbox-#{child1.id} button")
      |> render_click()

      # Submit with non-existent target_id
      fake_target_id = Ecto.UUID.generate()

      html =
        render_click(view, "confirm-merge", %{
          "merge" => %{"target_id" => fake_target_id}
        })

      assert html =~ "Target project not found"
      refute has_element?(view, "#merge-sandbox-modal")
    end

    test "shows partial success when merge succeeds but delete fails", %{
      conn: conn,
      root: root,
      child1: child1,
      user: _user
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      Mimic.expect(Lightning.Projects.MergeProjects, :merge_project, fn _source,
                                                                        _target ->
        "merged_yaml"
      end)

      Mimic.expect(Lightning.Projects.Provisioner, :import_document, fn _target,
                                                                        _actor,
                                                                        _yaml,
                                                                        _opts ->
        {:ok, root}
      end)

      Mimic.expect(Lightning.Projects, :delete_sandbox, fn _source, _actor ->
        {:error, :unauthorized}
      end)

      Mimic.allow(Lightning.Projects.MergeProjects, self(), view.pid)
      Mimic.allow(Lightning.Projects.Provisioner, self(), view.pid)
      Mimic.allow(Lightning.Projects, self(), view.pid)

      view
      |> element("#branch-rewire-sandbox-#{child1.id} button")
      |> render_click()

      {:ok, _view, html} =
        view
        |> form("#merge-sandbox-modal form")
        |> render_submit()
        |> follow_redirect(conn)

      assert html =~
               "Successfully merged child1 into root, but could not delete the sandbox"
    end

    test "formats changeset error correctly", %{
      conn: conn,
      root: root,
      child1: child1
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      Mimic.expect(Lightning.Projects.MergeProjects, :merge_project, fn _source,
                                                                        _target ->
        "merged_yaml"
      end)

      # Return changeset error
      changeset = %Ecto.Changeset{
        errors: [name: {"is invalid", []}],
        valid?: false
      }

      Mimic.expect(Lightning.Projects.Provisioner, :import_document, fn _target,
                                                                        _actor,
                                                                        _yaml,
                                                                        _opts ->
        {:error, changeset}
      end)

      Mimic.allow(Lightning.Projects.MergeProjects, self(), view.pid)
      Mimic.allow(Lightning.Projects.Provisioner, self(), view.pid)

      view
      |> element("#branch-rewire-sandbox-#{child1.id} button")
      |> render_click()

      view
      |> form("#merge-sandbox-modal form")
      |> render_submit()

      html = render(view)
      assert html =~ "name: is invalid"
      refute has_element?(view, "#merge-sandbox-modal")
    end

    test "formats text error correctly", %{
      conn: conn,
      root: root,
      child1: child1
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      Mimic.expect(Lightning.Projects.MergeProjects, :merge_project, fn _source,
                                                                        _target ->
        "merged_yaml"
      end)

      Mimic.expect(Lightning.Projects.Provisioner, :import_document, fn _target,
                                                                        _actor,
                                                                        _yaml,
                                                                        _opts ->
        {:error, %{text: "Custom import error message"}}
      end)

      Mimic.allow(Lightning.Projects.MergeProjects, self(), view.pid)
      Mimic.allow(Lightning.Projects.Provisioner, self(), view.pid)

      view
      |> element("#branch-rewire-sandbox-#{child1.id} button")
      |> render_click()

      view
      |> form("#merge-sandbox-modal form")
      |> render_submit()

      html = render(view)
      assert html =~ "Custom import error message"
      refute has_element?(view, "#merge-sandbox-modal")
    end

    test "formats generic error with inspect", %{
      conn: conn,
      root: root,
      child1: child1
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      Mimic.expect(Lightning.Projects.MergeProjects, :merge_project, fn _source,
                                                                        _target ->
        "merged_yaml"
      end)

      Mimic.expect(Lightning.Projects.Provisioner, :import_document, fn _target,
                                                                        _actor,
                                                                        _yaml,
                                                                        _opts ->
        {:error, {:unexpected, "something went wrong"}}
      end)

      Mimic.allow(Lightning.Projects.MergeProjects, self(), view.pid)
      Mimic.allow(Lightning.Projects.Provisioner, self(), view.pid)

      view
      |> element("#branch-rewire-sandbox-#{child1.id} button")
      |> render_click()

      view
      |> form("#merge-sandbox-modal form")
      |> render_submit()

      html = render(view)
      assert html =~ "Failed to merge:"
      assert html =~ "unexpected"
      refute has_element?(view, "#merge-sandbox-modal")
    end

    test "descendant_of? handles nil parent correctly", %{
      conn: conn,
      root: root,
      child1: child1
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      view
      |> element("#branch-rewire-sandbox-#{child1.id} button")
      |> render_click()

      assigns = :sys.get_state(view.pid).socket.assigns
      descendant_ids = Enum.map(assigns.merge_descendants, & &1.id)
      refute root.id in descendant_ids
    end
  end

  describe "Merge modal authorization" do
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

    test "owner can see and use merge button", %{
      conn: conn,
      owner_user: owner_user,
      parent: parent,
      sandbox: sandbox
    } do
      conn = log_in_user(conn, owner_user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      button_html =
        view
        |> element("#branch-rewire-sandbox-#{sandbox.id}")
        |> render()

      refute button_html =~ "cursor-not-allowed"
      refute button_html =~ "text-slate-300"
      assert button_html =~ "Merge this sandbox"

      view
      |> element("#branch-rewire-sandbox-#{sandbox.id} button")
      |> render_click()

      assert has_element?(view, "#merge-sandbox-modal")
    end

    test "viewer sees disabled merge button", %{
      conn: conn,
      viewer_user: viewer_user,
      parent: parent,
      sandbox: sandbox
    } do
      conn = log_in_user(conn, viewer_user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      button_html =
        view
        |> element("#branch-rewire-sandbox-#{sandbox.id}")
        |> render()

      assert button_html =~ "cursor-not-allowed"
      assert button_html =~ "text-slate-300"
      assert button_html =~ "You are not authorized to merge this sandbox"
    end

    test "viewer cannot open merge modal", %{
      conn: conn,
      viewer_user: viewer_user,
      parent: parent,
      sandbox: sandbox
    } do
      conn = log_in_user(conn, viewer_user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      html = render_click(view, "open-merge-modal", %{"id" => sandbox.id})

      assert html =~ "You are not authorized to merge this sandbox"
      refute has_element?(view, "#merge-sandbox-modal")
    end

    test "viewer cannot confirm merge without opening modal", %{
      conn: conn,
      viewer_user: viewer_user,
      parent: parent,
      sandbox: _sandbox
    } do
      conn = log_in_user(conn, viewer_user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      html =
        render_click(view, "confirm-merge", %{
          "merge" => %{"target_id" => parent.id}
        })

      assert html =~ "Invalid merge request"
      refute has_element?(view, "#merge-sandbox-modal")
    end

    test "can_merge permission is set correctly based on user role", %{
      conn: conn,
      owner_user: owner_user,
      parent: parent,
      sandbox: sandbox
    } do
      conn = log_in_user(conn, owner_user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      sandboxes = :sys.get_state(view.pid).socket.assigns.sandboxes
      test_sandbox = Enum.find(sandboxes, &(&1.id == sandbox.id))

      assert test_sandbox.can_merge == true
    end

    test "merge authorization follows update permissions from Sandboxes policy",
         %{
           conn: conn,
           viewer_user: viewer_user,
           parent: parent,
           sandbox: sandbox
         } do
      conn = log_in_user(conn, viewer_user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      sandboxes = :sys.get_state(view.pid).socket.assigns.sandboxes
      test_sandbox = Enum.find(sandboxes, &(&1.id == sandbox.id))

      assert test_sandbox.can_merge == false
      assert test_sandbox.can_edit == false
    end

    test "merge succeeds for owner", %{
      conn: conn,
      owner_user: owner_user,
      parent: parent,
      sandbox: sandbox
    } do
      conn = log_in_user(conn, owner_user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      Mimic.expect(
        Lightning.Projects.MergeProjects,
        :merge_project,
        fn _source, _target -> "merged_yaml" end
      )

      Mimic.expect(
        Lightning.Projects.Provisioner,
        :import_document,
        fn _target, _actor, _yaml, _opts -> {:ok, parent} end
      )

      Mimic.expect(
        Lightning.Projects,
        :delete_sandbox,
        fn _source, _actor -> {:ok, sandbox} end
      )

      Mimic.allow(Lightning.Projects.MergeProjects, self(), view.pid)
      Mimic.allow(Lightning.Projects.Provisioner, self(), view.pid)
      Mimic.allow(Lightning.Projects, self(), view.pid)

      view
      |> element("#branch-rewire-sandbox-#{sandbox.id} button")
      |> render_click()

      view
      |> form("#merge-sandbox-modal form")
      |> render_submit()

      assert_redirect(view, ~p"/projects/#{parent.id}/w")
    end

    test "viewer cannot bypass authorization", %{
      conn: conn,
      viewer_user: viewer_user,
      parent: parent,
      sandbox: _sandbox
    } do
      conn = log_in_user(conn, viewer_user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      html =
        render_click(view, "confirm-merge", %{
          "merge" => %{"target_id" => parent.id}
        })

      assert html =~ "Invalid merge request"
    end

    test "merges sandbox successfully when parent workflow was modified with new nodes/edges",
         %{
           conn: conn,
           owner_user: owner_user,
           parent: parent
         } do
      # This test simulates Joe's scenario:
      # 1. Create a sandbox from parent
      # 2. Add a new node/edge to parent (after sandbox creation)
      # 3. Merge sandbox back to parent
      # Expected: Merge succeeds and parent's new edges are deleted (overwrite behavior)

      # Create initial parent workflow with job1
      parent_workflow =
        insert(:workflow, project: parent, name: "Main Workflow")

      job1 =
        insert(:job,
          workflow: parent_workflow,
          name: "Initial Job",
          body: "job1()"
        )

      trigger = insert(:trigger, workflow: parent_workflow, type: :webhook)

      insert(:edge,
        workflow: parent_workflow,
        source_trigger: trigger,
        target_job: job1
      )

      # Create sandbox from parent (at this point, parent only has job1)
      sandbox = insert(:project, name: "Sandbox", parent: parent)

      sandbox_workflow =
        insert(:workflow,
          project: sandbox,
          name: "Main Workflow",
          lock_version: parent_workflow.lock_version
        )

      sandbox_job1 =
        insert(:job,
          workflow: sandbox_workflow,
          name: "Initial Job",
          body: "job1_modified()"
        )

      sandbox_trigger =
        insert(:trigger, workflow: sandbox_workflow, type: :webhook)

      insert(:edge,
        workflow: sandbox_workflow,
        source_trigger: sandbox_trigger,
        target_job: sandbox_job1
      )

      # NOW: Parent gets modified with a new job2 and edge (simulating concurrent work)
      job2 =
        insert(:job,
          workflow: parent_workflow,
          name: "New Job Added After Sandbox",
          body: "job2()"
        )

      new_edge =
        insert(:edge,
          workflow: parent_workflow,
          source_job: job1,
          target_job: job2
        )

      # Update parent workflow to increment lock_version (simulating the modification)
      parent_workflow =
        parent_workflow
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.optimistic_lock(:lock_version)
        |> Repo.update!()

      initial_parent_lock_version = parent_workflow.lock_version

      # Now perform the merge from sandbox to parent
      conn = log_in_user(conn, owner_user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      # Open the merge modal
      view
      |> element("#branch-rewire-sandbox-#{sandbox.id} button")
      |> render_click()

      # Submit the merge
      view
      |> form("#merge-sandbox-modal form", %{
        "merge" => %{"target_id" => parent.id}
      })
      |> render_submit()

      # Verify redirect to parent project
      assert_redirect(view, ~p"/projects/#{parent.id}/w")

      # Verify the merge succeeded with allow_stale
      updated_parent_workflow =
        Repo.reload(parent_workflow) |> Repo.preload([:edges, :jobs])

      # The workflow lock_version should have incremented (merge was applied)
      assert updated_parent_workflow.lock_version > initial_parent_lock_version

      # The new edge added to parent should be DELETED (overwrite behavior)
      edge_ids = Enum.map(updated_parent_workflow.edges, & &1.id)

      refute new_edge.id in edge_ids,
             "Parent's new edge should be deleted during merge"

      # Only the trigger->job1 edge should remain
      assert length(updated_parent_workflow.edges) == 1

      # job2 should also be deleted (not in sandbox)
      job_ids = Enum.map(updated_parent_workflow.jobs, & &1.id)

      refute job2.id in job_ids,
             "Parent's new job should be deleted during merge"

      # job1 should have the sandbox's modified body
      remaining_job =
        Enum.find(updated_parent_workflow.jobs, &(&1.name == "Initial Job"))

      assert remaining_job.body == "job1_modified()"
    end

    test "editor on root can see and use merge button", %{
      conn: conn,
      parent: parent,
      sandbox: sandbox
    } do
      editor_user = insert(:user)
      insert(:project_user, user: editor_user, project: parent, role: :editor)

      insert(:project_user,
        user: editor_user,
        project: sandbox,
        role: :editor
      )

      conn = log_in_user(conn, editor_user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      sandboxes = :sys.get_state(view.pid).socket.assigns.sandboxes
      test_sandbox = Enum.find(sandboxes, &(&1.id == sandbox.id))

      assert test_sandbox.can_merge == true
      assert test_sandbox.can_edit == false
      assert test_sandbox.can_delete == false
    end

    test "editor on root can create sandboxes", %{
      conn: conn,
      parent: parent
    } do
      editor_user = insert(:user)
      insert(:project_user, user: editor_user, project: parent, role: :editor)

      conn = log_in_user(conn, editor_user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      can_create = :sys.get_state(view.pid).socket.assigns.can_create_sandbox
      assert can_create == true
    end

    test "server-side merge auth rejects unauthorized user", %{
      conn: conn,
      parent: parent,
      sandbox: sandbox
    } do
      # A user who is editor on root but viewer on a specific target
      # should be blocked at server-side enforcement
      editor_user = insert(:user)
      insert(:project_user, user: editor_user, project: parent, role: :editor)

      insert(:project_user,
        user: editor_user,
        project: sandbox,
        role: :editor
      )

      # Create a target project where this user is only a viewer
      target =
        insert(:project,
          name: "restricted-target",
          parent: parent,
          project_users: [
            %{user: editor_user, role: :viewer}
          ]
        )

      conn = log_in_user(conn, editor_user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      # Open merge modal
      view
      |> element("#branch-rewire-sandbox-#{sandbox.id} button")
      |> render_click()

      # Try to merge into the restricted target via direct event
      html =
        render_click(view, "confirm-merge", %{
          "merge" => %{"target_id" => target.id}
        })

      assert html =~ "You are not authorized to merge into this project"
    end

    test "merge target options filter out projects where user lacks editor+ role",
         %{
           conn: conn,
           parent: parent,
           sandbox: sandbox
         } do
      editor_user = insert(:user)
      insert(:project_user, user: editor_user, project: parent, role: :editor)

      insert(:project_user,
        user: editor_user,
        project: sandbox,
        role: :editor
      )

      # Create another sandbox where user is only a viewer
      viewer_sandbox =
        insert(:project,
          name: "viewer-only-sandbox",
          parent: parent,
          project_users: [
            %{user: editor_user, role: :viewer}
          ]
        )

      # Create a sandbox where the editor has no membership at all
      no_membership_sandbox =
        insert(:project,
          name: "no-membership-sandbox",
          parent: parent,
          project_users: []
        )

      conn = log_in_user(conn, editor_user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      # Open merge modal
      view
      |> element("#branch-rewire-sandbox-#{sandbox.id} button")
      |> render_click()

      assigns = :sys.get_state(view.pid).socket.assigns
      target_ids = Enum.map(assigns.merge_target_options, & &1.value)

      # Parent should be in targets (user is editor)
      assert parent.id in target_ids

      # Viewer-only sandbox should NOT be in targets
      refute viewer_sandbox.id in target_ids

      # No-membership sandbox should NOT be in targets
      refute no_membership_sandbox.id in target_ids
    end

    test "checks for divergence when opening merge modal with default target",
         %{
           conn: conn,
           parent: parent,
           sandbox: sandbox
         } do
      parent_workflow =
        insert(:workflow, project: parent, name: "Test Workflow")

      insert(:workflow_version,
        workflow: parent_workflow,
        hash: "parent_hash",
        source: "app"
      )

      sandbox_workflow =
        insert(:workflow, project: sandbox, name: "Test Workflow")

      insert(:workflow_version,
        workflow: sandbox_workflow,
        hash: "sandbox_hash",
        source: "app"
      )

      {:ok, view, _} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      # Open the merge modal
      view
      |> render_click("open-merge-modal", %{"id" => sandbox.id})

      assert view
             |> element("#merge-divergence-alert")
             |> has_element?()
    end
  end

  describe "Edge cases for divergence and nil handling" do
    test "handles nil target_id in select-merge-target", %{conn: conn} do
      owner = insert(:user)

      root =
        insert(:project, project_users: [%{user: owner, role: :owner}])

      child1 =
        insert(:project,
          parent: root,
          project_users: [%{user: owner, role: :owner}]
        )

      conn = log_in_user(conn, owner)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{root.id}/sandboxes")

      view
      |> element("#branch-rewire-sandbox-#{child1.id} button")
      |> render_click()

      render_click(view, "select-merge-target", %{
        "merge" => %{"target_id" => ""}
      })

      # Should not crash - the diverged_workflows will be empty for nil target
      assigns = :sys.get_state(view.pid).socket.assigns
      assert assigns.merge_diverged_workflows == []
    end

    test "displays MAIN when selected target not found in options", %{conn: conn} do
      owner = insert(:user)

      root =
        insert(:project, project_users: [%{user: owner, role: :owner}])

      child1 =
        insert(:project,
          parent: root,
          project_users: [%{user: owner, role: :owner}]
        )

      _child2 =
        insert(:project,
          parent: root,
          project_users: [%{user: owner, role: :owner}]
        )

      conn = log_in_user(conn, owner)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{root.id}/sandboxes")

      view
      |> element("#branch-rewire-sandbox-#{child1.id} button")
      |> render_click()

      invalid_id = Ecto.UUID.generate()

      render_click(view, "select-merge-target", %{
        "merge" => %{"target_id" => invalid_id}
      })

      # The modal should still render without crashing
      # and the label should fall back to "MAIN"
      html = render(view)
      assert html =~ "MAIN"
    end

    test "has_environment? handles project without env field", %{conn: conn} do
      owner = insert(:user)

      root =
        insert(:project,
          project_users: [%{user: owner, role: :owner}],
          env: ""
        )

      conn = log_in_user(conn, owner)

      {:ok, view, html} =
        live(conn, ~p"/projects/#{root.id}/sandboxes")

      # With empty string env, it should show "main" badge
      assert html =~ "main"

      assert has_element?(view, "#env-badge-#{root.id}")
    end
  end

  describe "Creating sandbox" do
    setup :register_and_log_in_user

    test "copies allow_support_access field from parent project", %{
      conn: conn,
      user: user
    } do
      # Create parent with allow_support_access enabled
      parent =
        insert(:project,
          name: "parent-with-support",
          allow_support_access: true,
          project_users: [%{user: user, role: :owner}]
        )

      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      view |> element("#create-sandbox-button") |> render_click()
      assert_patch(view, ~p"/projects/#{parent.id}/sandboxes/new")

      view
      |> element("#sandbox-form-new")
      |> render_change(%{
        "project" => %{"raw_name" => "test-sandbox", "color" => "#E33D63"}
      })

      view
      |> element("#sandbox-form-new")
      |> render_submit(%{
        "project" => %{"raw_name" => "test-sandbox", "color" => "#E33D63"}
      })

      # Get the created sandbox from database
      sandbox =
        Repo.get_by!(Project, parent_id: parent.id, name: "test-sandbox")

      # Verify allow_support_access was copied from parent
      assert sandbox.allow_support_access == true

      # Also test with allow_support_access disabled
      parent_no_support =
        insert(:project,
          name: "parent-no-support",
          allow_support_access: false,
          project_users: [%{user: user, role: :owner}]
        )

      {:ok, view2, _html} =
        live(conn, ~p"/projects/#{parent_no_support.id}/sandboxes")

      view2 |> element("#create-sandbox-button") |> render_click()
      assert_patch(view2, ~p"/projects/#{parent_no_support.id}/sandboxes/new")

      view2
      |> element("#sandbox-form-new")
      |> render_change(%{
        "project" => %{"raw_name" => "test-sandbox-2", "color" => "#5AA1F0"}
      })

      view2
      |> element("#sandbox-form-new")
      |> render_submit(%{
        "project" => %{"raw_name" => "test-sandbox-2", "color" => "#5AA1F0"}
      })

      # Get the second sandbox from database
      sandbox2 =
        Repo.get_by!(Project,
          parent_id: parent_no_support.id,
          name: "test-sandbox-2"
        )

      # Verify allow_support_access remains false
      assert sandbox2.allow_support_access == false
    end

    test "copies all parent users when current user is owner", %{
      conn: conn,
      user: user
    } do
      # Create parent with multiple users
      parent =
        insert(:project,
          name: "parent-proj",
          project_users: [%{user: user, role: :owner}]
        )

      editor_user = insert(:user)
      viewer_user = insert(:user)

      insert(:project_user,
        project: parent,
        user: editor_user,
        role: :editor
      )

      insert(:project_user,
        project: parent,
        user: viewer_user,
        role: :viewer
      )

      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      view |> element("#create-sandbox-button") |> render_click()
      assert_patch(view, ~p"/projects/#{parent.id}/sandboxes/new")

      view
      |> element("#sandbox-form-new")
      |> render_change(%{
        "project" => %{"raw_name" => "my-test-sandbox", "color" => "#E33D63"}
      })

      view
      |> element("#sandbox-form-new")
      |> render_submit(%{
        "project" => %{"raw_name" => "my-test-sandbox", "color" => "#E33D63"}
      })

      # Get the created sandbox from database
      sandbox =
        Repo.get_by!(Project, parent_id: parent.id, name: "my-test-sandbox")
        |> Repo.preload(:project_users)

      # Verify all 3 users are present
      assert length(sandbox.project_users) == 3

      # Verify current user is owner
      assert Enum.any?(sandbox.project_users, fn pu ->
               pu.user_id == user.id and pu.role == :owner
             end)

      # Verify editor was copied
      assert Enum.any?(sandbox.project_users, fn pu ->
               pu.user_id == editor_user.id and pu.role == :editor
             end)

      # Verify viewer was copied
      assert Enum.any?(sandbox.project_users, fn pu ->
               pu.user_id == viewer_user.id and pu.role == :viewer
             end)
    end

    test "converts parent owner to admin when current user is admin", %{
      conn: conn,
      user: current_user
    } do
      # Create parent with a different owner
      owner_user = insert(:user)

      parent =
        insert(:project,
          name: "parent-proj-2",
          project_users: [%{user: owner_user, role: :owner}]
        )

      # Add current user as admin
      insert(:project_user,
        project: parent,
        user: current_user,
        role: :admin
      )

      # Add an editor
      editor_user = insert(:user)

      insert(:project_user,
        project: parent,
        user: editor_user,
        role: :editor
      )

      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      # Click create sandbox button
      view |> element("#create-sandbox-button") |> render_click()
      assert_patch(view, ~p"/projects/#{parent.id}/sandboxes/new")

      # Validate the form first (triggers phx-change)
      view
      |> element("#sandbox-form-new")
      |> render_change(%{
        "project" => %{"raw_name" => "admin-test-sandbox", "color" => "#5AA1F0"}
      })

      # Submit the form
      view
      |> element("#sandbox-form-new")
      |> render_submit(%{
        "project" => %{"raw_name" => "admin-test-sandbox", "color" => "#5AA1F0"}
      })

      # Get the created sandbox from database
      sandbox =
        Repo.get_by!(Project, parent_id: parent.id, name: "admin-test-sandbox")
        |> Repo.preload(:project_users)

      # Verify all 3 users are present
      assert length(sandbox.project_users) == 3

      # Verify current user is owner
      assert Enum.any?(sandbox.project_users, fn pu ->
               pu.user_id == current_user.id and pu.role == :owner
             end)

      # Verify parent owner was converted to admin
      assert Enum.any?(sandbox.project_users, fn pu ->
               pu.user_id == owner_user.id and pu.role == :admin
             end)

      # Verify editor was copied
      assert Enum.any?(sandbox.project_users, fn pu ->
               pu.user_id == editor_user.id and pu.role == :editor
             end)
    end
  end

  describe "merge modal with divergence" do
    setup :register_and_log_in_user

    setup %{user: user} do
      parent =
        insert(:project,
          name: "parent",
          project_users: [%{user: user, role: :owner}]
        )

      sandbox =
        insert(:project,
          name: "test-sandbox",
          parent: parent,
          project_users: [%{user: user, role: :owner}]
        )

      {:ok, parent: parent, sandbox: sandbox}
    end

    test "displays list of diverged workflow names when has_diverged is true", %{
      conn: conn,
      sandbox: sandbox,
      parent: parent
    } do
      # Setup: Create diverged workflows
      target_wf1 =
        insert(:workflow, project: parent, name: "Payment Processing")

      {:ok, _} =
        Lightning.WorkflowVersions.record_version(
          target_wf1,
          "aaa111111111",
          "app"
        )

      target_wf2 = insert(:workflow, project: parent, name: "Data Sync")

      {:ok, _} =
        Lightning.WorkflowVersions.record_version(
          target_wf2,
          "bbb222222222",
          "app"
        )

      sandbox_wf1 =
        insert(:workflow, project: sandbox, name: "Payment Processing")

      {:ok, _} =
        Lightning.WorkflowVersions.record_version(
          sandbox_wf1,
          "aaa999999999",
          "app"
        )

      sandbox_wf2 = insert(:workflow, project: sandbox, name: "Data Sync")

      {:ok, _} =
        Lightning.WorkflowVersions.record_version(
          sandbox_wf2,
          "bbb888888888",
          "app"
        )

      {:ok, view, _html} = live(conn, ~p"/projects/#{parent}/sandboxes")

      # Open merge modal
      view
      |> element("#branch-rewire-sandbox-#{sandbox.id} button")
      |> render_click()

      html = render(view)

      # Assert divergence alert is present
      assert html =~ "Target project has diverged"

      # Assert workflow names are listed
      assert html =~ "Payment Processing"
      assert html =~ "Data Sync"

      assert html =~ "workflow(s) have been modified"
    end

    test "does not show divergence alert when workflows match", %{
      conn: conn,
      sandbox: sandbox,
      parent: parent
    } do
      # Setup: Create matching workflows
      target_wf = insert(:workflow, project: parent, name: "Matching Workflow")

      {:ok, _} =
        Lightning.WorkflowVersions.record_version(
          target_wf,
          "aabbccddee00",
          "app"
        )

      sandbox_wf =
        insert(:workflow, project: sandbox, name: "Matching Workflow")

      {:ok, _} =
        Lightning.WorkflowVersions.record_version(
          sandbox_wf,
          "aabbccddee00",
          "app"
        )

      {:ok, view, _html} = live(conn, ~p"/projects/#{parent}/sandboxes")

      view
      |> element("#branch-rewire-sandbox-#{sandbox.id} button")
      |> render_click()

      html = render(view)

      refute html =~ "Target project has diverged"
      refute html =~ "Matching Workflow"
    end

    test "updates diverged workflow list when changing merge target", %{
      conn: conn,
      sandbox: sandbox,
      parent: parent,
      user: user
    } do
      # Create another sandbox (sibling) as alternative merge target
      sibling_sandbox =
        insert(:project,
          name: "sibling-sandbox",
          parent: parent,
          project_users: [%{user: user, role: :owner}]
        )

      # Setup: Different diverged workflows for each target
      parent_wf = insert(:workflow, project: parent, name: "Parent Workflow")

      {:ok, _} =
        Lightning.WorkflowVersions.record_version(
          parent_wf,
          "aabbcc123456",
          "app"
        )

      sibling_wf =
        insert(:workflow, project: sibling_sandbox, name: "Sibling Workflow")

      {:ok, _} =
        Lightning.WorkflowVersions.record_version(
          sibling_wf,
          "ddeeff654321",
          "app"
        )

      sandbox_parent_wf =
        insert(:workflow, project: sandbox, name: "Parent Workflow")

      {:ok, _} =
        Lightning.WorkflowVersions.record_version(
          sandbox_parent_wf,
          "112233445566",
          "app"
        )

      sandbox_sibling_wf =
        insert(:workflow, project: sandbox, name: "Sibling Workflow")

      {:ok, _} =
        Lightning.WorkflowVersions.record_version(
          sandbox_sibling_wf,
          "665544332211",
          "app"
        )

      {:ok, view, _html} = live(conn, ~p"/projects/#{parent}/sandboxes")

      # Open merge modal (defaults to parent target)
      view
      |> element("#branch-rewire-sandbox-#{sandbox.id} button")
      |> render_click()

      html = render(view)
      assert html =~ "Parent Workflow"
      refute html =~ "Sibling Workflow"

      # Change target to sibling_sandbox
      html =
        view
        |> form("#merge-sandbox-modal form")
        |> render_change(%{merge: %{target_id: sibling_sandbox.id}})

      refute html =~ "Parent Workflow"
      assert html =~ "Sibling Workflow"
    end
  end

  describe "GitHub sync integration during merge" do
    setup do
      Mox.verify_on_exit!()
    end

    setup :register_and_log_in_user

    setup %{user: user} do
      parent =
        insert(:project,
          name: "parent",
          project_users: [%{user: user, role: :owner}]
        )

      # Create workflows and snapshots for the parent project
      workflow = insert(:simple_workflow, project: parent)
      {:ok, snapshot} = Lightning.Workflows.Snapshot.create(workflow)

      sandbox =
        insert(:project,
          name: "test-sandbox",
          parent: parent,
          project_users: [%{user: user, role: :owner}]
        )

      {:ok,
       parent: parent, sandbox: sandbox, workflow: workflow, snapshot: snapshot}
    end

    test "commits to GitHub before and after merge when project has GitHub sync",
         %{
           conn: conn,
           parent: parent,
           sandbox: sandbox,
           snapshot: snapshot
         } do
      # Set up GitHub sync for the parent project
      repo_connection =
        insert(:project_repo_connection,
          project: parent,
          repo: "someaccount/somerepo",
          branch: "main",
          github_installation_id: "1234"
        )

      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      # Expect GitHub API calls for the pre-merge commit
      expect_create_installation_token(repo_connection.github_installation_id)
      expect_get_repo(repo_connection.repo)

      expect_create_workflow_dispatch_with_request_body(
        repo_connection.repo,
        "openfn-pull.yml",
        %{
          ref: "main",
          inputs: %{
            projectId: parent.id,
            apiSecretName: api_secret_name(parent),
            branch: repo_connection.branch,
            pathToConfig: path_to_config(repo_connection),
            commitMessage: "pre-merge commit",
            snapshots: "#{snapshot.id}"
          }
        }
      )

      # Expect GitHub API calls for the post-merge commit
      expect_create_installation_token(repo_connection.github_installation_id)
      expect_get_repo(repo_connection.repo)

      expect_create_workflow_dispatch_with_request_body(
        repo_connection.repo,
        "openfn-pull.yml",
        %{
          ref: "main",
          inputs: %{
            projectId: parent.id,
            apiSecretName: api_secret_name(parent),
            branch: repo_connection.branch,
            pathToConfig: path_to_config(repo_connection),
            commitMessage: "Merged sandbox #{sandbox.name}"
          }
        }
      )

      # Open merge modal and submit
      view
      |> element("#branch-rewire-sandbox-#{sandbox.id} button")
      |> render_click()

      view
      |> form("#merge-sandbox-modal form")
      |> render_submit()

      assert_redirect(view, ~p"/projects/#{parent.id}/w")
    end

    test "does not commit to GitHub when project has no GitHub sync configured",
         %{
           conn: conn,
           parent: parent,
           sandbox: sandbox
         } do
      # No repo_connection created = no GitHub sync
      # Without a repo_connection, get_repo_connection_for_project returns nil
      # and initiate_sync is never called, so no GitHub API calls happen
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      # Open merge modal and submit
      view
      |> element("#branch-rewire-sandbox-#{sandbox.id} button")
      |> render_click()

      view
      |> form("#merge-sandbox-modal form")
      |> render_submit()

      assert_redirect(view, ~p"/projects/#{parent.id}/w")
    end

    defp api_secret_name(%{id: project_id}) do
      project_id
      |> String.replace("-", "_")
      |> then(&"OPENFN_#{&1}_API_KEY")
    end

    defp path_to_config(repo_connection) do
      repo_connection
      |> Lightning.VersionControl.ProjectRepoConnection.config_path()
      |> Path.relative_to(".")
    end
  end
end
