defmodule LightningWeb.SandboxLive.IndexTest do
  use LightningWeb.ConnCase, async: true
  use Mimic
  use LightningWeb.SandboxPageHelpers

  import Ecto.Query
  import Lightning.Factories
  import Phoenix.LiveViewTest

  alias Lightning.Projects.Project
  alias Lightning.Repo

  # The page is drawn by React from data-props. What it renders from them
  # (badges, the scheduled section, tooltips, the modals' copy and the
  # disabled buttons) is tested in the design system's own
  # SandboxesIndexPage.test.tsx (in @openfn/ui), and the events it sends in
  # assets/test/design-system/SandboxesIndexPage.test.tsx. The merge's
  # events are tested in merge_test.exs and merge_selection_test.exs.

  defp send_event(view, event, payload),
    do: push_page_event(view, @page, event, payload)

  defp names(view), do: Enum.map(props(view)["sandboxes"], & &1["name"])

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp stub_sandbox_limit(project_id, text) do
    Mox.stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn
      %{type: :new_sandbox, amount: 1}, %{project_id: ^project_id} ->
        {:error, :exceeded_limit, %{text: text}}

      _action, _context ->
        :ok
    end)
  end

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

    {:ok, parent: parent, sb1: sb1, sb2: sb2}
  end

  describe "the list" do
    test "sends the root and each sandbox as the page's rows", %{
      conn: conn,
      parent: parent,
      sb1: sb1
    } do
      {:ok, view, html} =
        live(conn, ~p"/projects/#{parent.id}/sandboxes", on_error: :raise)

      assert html =~ "Sandboxes"

      assert %{
               "project" => %{"id" => project_id, "parentId" => nil},
               "projectLabel" => "parent",
               "rootIsSandbox" => false,
               "newHref" => new_href,
               "createBlockedReason" => nil,
               "form" => nil
             } = props(view)

      assert project_id == parent.id
      assert new_href == ~p"/projects/#{parent.id}/sandboxes/new"
      assert names(view) == ["sb-1", "sb-2"]

      root_workflows = ~p"/projects/#{parent.id}/w"

      assert %{
               "editHref" => nil,
               "env" => nil,
               "workflowsHref" => ^root_workflows,
               "canEdit" => false,
               "canDelete" => false,
               "canMerge" => false
             } = row(view, parent)

      sb1_edit = ~p"/projects/#{parent.id}/sandboxes/#{sb1.id}/edit"
      sb1_workflows = ~p"/projects/#{sb1.id}/w"

      assert %{
               "name" => "sb-1",
               "color" => "#ff0000",
               "env" => "staging",
               "scheduledDeletion" => nil,
               "editHref" => ^sb1_edit,
               "workflowsHref" => ^sb1_workflows,
               "canEdit" => true,
               "canDelete" => true,
               "canMerge" => true,
               "canCancelDeletion" => false,
               "restoreBlockedReason" => nil,
               "activeDescendantCount" => 0
             } = row(view, sb1)
    end

    test "reloads the list on a patch back to it", %{
      conn: conn,
      parent: parent,
      sb1: sb1,
      sb2: sb2
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      for sandbox <- [sb1, sb2] do
        Repo.delete_all(Ecto.assoc(sandbox, :project_users))
        Repo.delete!(sandbox)
      end

      render_patch(view, ~p"/projects/#{parent.id}/sandboxes")
      assert names(view) == []
    end

    test "a sandbox's page names it as the current project and its root's env",
         %{conn: conn, user: user, sb1: sb1} do
      root =
        insert(:project,
          name: "with-env",
          env: "production",
          project_users: [%{user: user, role: :owner}]
        )

      {:ok, view, _html} = live(conn, ~p"/projects/#{root.id}/sandboxes")
      assert %{"env" => "production"} = row(view, root)

      {:ok, view, _html} = live(conn, ~p"/projects/#{sb1.id}/sandboxes")

      assert %{"project" => %{"id" => id, "parentId" => parent_id}} =
               props(view)

      assert {id, parent_id} == {sb1.id, sb1.parent_id}
    end

    test "counts the live sandboxes under each one, the hidden ones too", %{
      conn: conn,
      parent: parent,
      sb1: sb1,
      user: user
    } do
      child =
        insert(:project,
          name: "child",
          parent: sb1,
          project_users: [%{user: user, role: :owner}]
        )

      # Not a member, so not listed, but deleting sb-1 still takes it.
      insert(:project, name: "hidden-grandchild", parent: child)

      insert(:project,
        name: "scheduled-child",
        parent: sb1,
        scheduled_deletion: now(),
        project_users: [%{user: user, role: :owner}]
      )

      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      assert row(view, sb1)["activeDescendantCount"] == 2
      assert row(view, child)["activeDescendantCount"] == 1
      assert row(view, parent)["activeDescendantCount"] == 4
      refute "hidden-grandchild" in names(view)
    end

    test "sends the grace period, or null when none is set", %{
      conn: conn,
      parent: parent
    } do
      Mox.stub(Lightning.MockConfig, :purge_deleted_after_days, fn -> 1 end)
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")
      assert props(view)["gracePeriodDays"] == 1

      Mox.stub(Lightning.MockConfig, :purge_deleted_after_days, fn -> nil end)
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")
      assert props(view)["gracePeriodDays"] == nil
    end

    test "renders the usage limiter's banner above the page", %{
      conn: conn,
      parent: parent
    } do
      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :check_limits,
        &Lightning.Extensions.StubUsageLimiter.check_limits/1
      )

      {:ok, view, html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      assert html =~ "Some banner text"
      assert has_element?(view, @page)
    end
  end

  describe "visibility" do
    test "a root editor sees only the sandboxes they are a member of", %{
      conn: conn,
      user: user
    } do
      parent =
        insert(:project,
          name: "editor-root",
          project_users: [%{user: user, role: :editor}]
        )

      insert(:project,
        name: "visible-sandbox",
        parent: parent,
        project_users: [%{user: user, role: :viewer}]
      )

      insert(:project, name: "hidden-sandbox", parent: parent)

      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")
      assert names(view) == ["visible-sandbox"]
    end

    test "a root owner sees only the sandboxes they have a row on", %{
      conn: conn,
      parent: parent
    } do
      insert(:project, name: "without-pu", parent: parent)

      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")
      assert names(view) == ["sb-1", "sb-2"]
    end

    test "a sandbox-only member's tree starts at their access root", %{
      conn: conn,
      user: user
    } do
      hidden_root = insert(:project, name: "hidden-workspace")

      access_root =
        insert(:project,
          name: "user-access-root",
          parent: hidden_root,
          project_users: [%{user: user, role: :admin}]
        )

      insert(:project,
        name: "visible-leaf",
        parent: access_root,
        project_users: [%{user: user, role: :admin}]
      )

      {:ok, view, html} =
        live(conn, ~p"/projects/#{access_root.id}/sandboxes")

      refute html =~ hidden_root.name

      assert %{
               "root" => %{"name" => "user-access-root"},
               "rootIsSandbox" => true
             } =
               props(view)

      assert names(view) == ["visible-leaf"]
    end

    test "every action refuses a sandbox the viewer can't see", %{
      conn: conn,
      user: user
    } do
      parent =
        insert(:project,
          name: "editor-root",
          project_users: [%{user: user, role: :editor}]
        )

      hidden =
        insert(:project,
          name: "hidden-sandbox",
          parent: parent,
          scheduled_deletion: now()
        )

      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      for {event, payload} <- [
            {"delete-sandbox", %{"nameConfirmation" => hidden.name}},
            {"cancel-sandbox-deletion", %{}},
            {"preview-merge", %{"targetId" => nil}},
            {"merge-sandbox", %{"targetId" => parent.id}}
          ] do
        send_event(view, event, Map.put(payload, "id", hidden.id))
        assert_reply(view, %{error: "Sandbox not found"})
      end

      assert Repo.reload!(hidden).scheduled_deletion

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{parent.id}/sandboxes/#{hidden.id}/edit")

      assert html =~ "Sandbox not found"
    end

    test "every action refuses the workspace root itself", %{
      conn: conn,
      user: user
    } do
      root =
        insert(:project,
          name: "workspace-root",
          project_users: [%{user: user, role: :admin}]
        )

      trigger =
        insert(:trigger,
          workflow: insert(:workflow, project: root),
          enabled: true
        )

      {:ok, view, _html} = live(conn, ~p"/projects/#{root.id}/sandboxes")

      send_event(view, "delete-sandbox", %{
        "id" => root.id,
        "nameConfirmation" => root.name
      })

      assert_reply(view, %{
        error: "You are not authorized to delete this sandbox"
      })

      assert %{error: "You are not authorized to merge this sandbox"} =
               preview(view, root)

      merge(view, root, root.id)

      assert_reply(view, %{error: "You are not authorized to merge this sandbox"})

      root = Repo.reload!(root)
      assert is_nil(root.scheduled_deletion)
      assert Repo.reload!(trigger).enabled

      assert {:error, {:live_redirect, %{flash: %{"error" => edit_error}}}} =
               live(conn, ~p"/projects/#{root.id}/sandboxes/#{root.id}/edit")

      assert edit_error == "You are not authorized to edit this sandbox"
    end
  end

  describe "who may create" do
    test "a viewer is told why they can't, and can't reach the form", %{
      conn: conn,
      parent: parent
    } do
      viewer = insert(:user)
      insert(:project_user, project: parent, user: viewer, role: :viewer)
      conn = log_in_user(conn, viewer)

      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      assert props(view)["createBlockedReason"] ==
               "You are not authorized to create sandboxes in this workspace"

      assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
               live(conn, ~p"/projects/#{parent.id}/sandboxes/new")

      assert to == ~p"/projects/#{parent.id}/sandboxes"

      assert flash["error"] ==
               "You are not authorized to create sandboxes in this workspace"
    end

    test "an editor can create, and reaches the form", %{
      conn: conn,
      parent: parent
    } do
      editor = insert(:user)
      insert(:project_user, project: parent, user: editor, role: :editor)
      conn = log_in_user(conn, editor)

      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")
      assert props(view)["createBlockedReason"] == nil

      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes/new")
      assert %{"mode" => "new"} = props(view)["form"]
    end

    test "the nesting cap blocks creating, below it nothing does", %{
      conn: conn,
      parent: parent,
      sb1: sb1
    } do
      Mox.stub(Lightning.MockConfig, :max_sandbox_nesting_depth, fn -> 1 end)

      {:ok, view, _html} = live(conn, ~p"/projects/#{sb1.id}/sandboxes")

      assert props(view)["createBlockedReason"] =~
               "Maximum sandbox nesting depth reached"

      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")
      assert props(view)["createBlockedReason"] == nil
    end

    test "the plan's limit blocks creating and sends /new back to the list", %{
      conn: conn,
      parent: parent,
      test: test
    } do
      stub_sandbox_limit(parent.id, "error-#{test}")

      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")
      assert props(view)["createBlockedReason"] == "error-#{test}"

      assert {:error, {:live_redirect, redirect}} =
               live(conn, ~p"/projects/#{parent.id}/sandboxes/new")

      assert redirect[:to] == ~p"/projects/#{parent.id}/sandboxes"
      assert redirect[:flash]["error"] == "error-#{test}"
    end
  end

  describe "create" do
    defp create_sandbox(view, raw_name, color \\ "#E33D63"),
      do:
        send_event(view, "create-sandbox", %{
          "rawName" => raw_name,
          "color" => color
        })

    test "/new opens the form with a palette colour under this project", %{
      conn: conn,
      parent: parent,
      sb1: sb1
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")
      render_patch(view, ~p"/projects/#{parent.id}/sandboxes/new")

      assert %{
               "mode" => "new",
               "parentName" => "parent",
               "parentIsSandbox" => false,
               "initialColor" => color
             } = props(view)["form"]

      assert color in LightningWeb.SandboxLive.Components.color_palette_hex_colors()

      render_patch(view, ~p"/projects/#{parent.id}/sandboxes")
      assert props(view)["form"] == nil

      {:ok, view, _html} = live(conn, ~p"/projects/#{sb1.id}/sandboxes/new")

      assert %{"parentName" => "sb-1", "parentIsSandbox" => true} =
               props(view)["form"]
    end

    test "creates the sandbox, copying the parent's users and support access",
         %{conn: conn, user: user} do
      owner = insert(:user)
      editor = insert(:user)

      parent =
        insert(:project,
          name: "parent-proj",
          allow_support_access: true,
          project_users: [
            %{user: owner, role: :owner},
            %{user: user, role: :admin},
            %{user: editor, role: :editor}
          ]
        )

      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes/new")

      create_sandbox(view, "My Test Sandbox", "#5AA1F0")
      {to, flash} = assert_redirect(view)

      sandbox =
        Project
        |> Repo.get_by!(parent_id: parent.id, name: "my-test-sandbox")
        |> Repo.preload(:project_users)

      assert to == ~p"/projects/#{sandbox.id}/w"
      assert flash["info"] == "Sandbox created"
      assert {sandbox.color, sandbox.env} == {"#5AA1F0", "dev"}
      assert sandbox.allow_support_access

      # The creator owns it; the parent's owner comes in as an admin.
      assert sandbox.project_users
             |> Enum.map(&{&1.user_id, &1.role})
             |> Enum.sort() ==
               Enum.sort([
                 {user.id, :owner},
                 {owner.id, :admin},
                 {editor.id, :editor}
               ])
    end

    test "a sibling's name or a blank name is refused on the field, and nothing is created",
         %{conn: conn, parent: parent} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes/new")

      create_sandbox(view, "SB 1")

      assert_reply(view, %{
        error: "Please fix the errors below.",
        fieldErrors: field_errors
      })

      assert field_errors == %{"rawName" => ["Sandbox name already exists"]}

      create_sandbox(view, "")

      assert_reply(view, %{
        fieldErrors: %{"rawName" => ["This field can't be blank."]}
      })

      assert Repo.aggregate(
               from(p in Project, where: p.parent_id == ^parent.id),
               :count
             ) == 2
    end

    test "a name taken between the check and the insert is refused on the field",
         %{conn: conn, parent: parent} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes/new")

      Mimic.expect(Lightning.Projects, :provision_sandbox, fn _parent,
                                                              _user,
                                                              _attrs ->
        {:error,
         %Project{}
         |> Ecto.Changeset.change()
         |> Ecto.Changeset.add_error(:name, "has already been taken")}
      end)

      # Free when the form is checked, taken by the time it's checked again.
      Lightning.Projects
      |> Mimic.expect(:sandbox_name_exists?, fn _parent_id, _name, _id ->
        false
      end)
      |> Mimic.expect(:sandbox_name_exists?, fn _parent_id, _name, _id ->
        true
      end)

      allow_mocks(view)

      create_sandbox(view, "Test Sandbox")

      assert_reply(view, %{fieldErrors: field_errors})
      assert field_errors == %{"rawName" => ["Sandbox name already exists"]}
    end

    test "the plan's limit at save, or any other failure, is replied and the form stays open",
         %{conn: conn, parent: parent} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes/new")

      stub_sandbox_limit(parent.id, "limit-reached")

      create_sandbox(view, "sb-limited")
      assert_reply(view, %{error: "limit-reached"})
      assert %{"mode" => "new"} = props(view)["form"]

      Mox.stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn _, _ ->
        :ok
      end)

      Mimic.expect(Lightning.Projects, :provision_sandbox, fn _parent,
                                                              _user,
                                                              _attrs ->
        {:error,
         %Project{}
         |> Ecto.Changeset.change()
         |> Ecto.Changeset.add_error(:history_retention_period, "is invalid")}
      end)

      allow_mocks(view)

      create_sandbox(view, "sb-broken")

      assert_reply(view, %{
        error:
          "Something went wrong while creating the sandbox. Please check the parent project's settings and try again."
      })

      assert %{"mode" => "new"} = props(view)["form"]
      refute Repo.get_by(Project, name: "sb-limited")
    end

    test "the nesting cap refuses the save, and nothing is created", %{
      conn: conn,
      sb1: sb1
    } do
      Mox.stub(Lightning.MockConfig, :max_sandbox_nesting_depth, fn -> 1 end)

      {:ok, view, _html} = live(conn, ~p"/projects/#{sb1.id}/sandboxes/new")

      create_sandbox(view, "too-deep")

      assert_reply(view, %{
        error: "Maximum sandbox nesting depth reached (1 levels deep)"
      })

      refute Repo.exists?(from(p in Project, where: p.parent_id == ^sb1.id))
    end

    test "is refused when the context refuses it", %{
      conn: conn,
      parent: parent
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes/new")

      Mimic.expect(Lightning.Projects, :provision_sandbox, fn _parent,
                                                              _user,
                                                              _attrs ->
        {:error, :unauthorized}
      end)

      allow_mocks(view)

      create_sandbox(view, "refused")

      assert_reply(view, %{
        error: "You are not authorized to create sandboxes in this workspace"
      })
    end

    test "is refused off the /new route",
         %{conn: conn, parent: parent} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      create_sandbox(view, "not-from-the-form")

      assert_reply(view, %{
        error: "You are not authorized to create sandboxes in this workspace"
      })

      viewer = insert(:user)
      insert(:project_user, project: parent, user: viewer, role: :viewer)

      {:ok, view, _html} =
        live(log_in_user(conn, viewer), ~p"/projects/#{parent.id}/sandboxes")

      create_sandbox(view, "from-a-viewer")

      assert_reply(view, %{
        error: "You are not authorized to create sandboxes in this workspace"
      })

      refute Repo.get_by(Project, name: "not-from-the-form")
      refute Repo.get_by(Project, name: "from-a-viewer")
    end
  end

  describe "edit" do
    defp update_sandbox(view, sandbox, raw_name, color \\ "#ff0000"),
      do:
        send_event(view, "update-sandbox", %{
          "id" => sandbox.id,
          "rawName" => raw_name,
          "color" => color
        })

    test "the edit route opens the form with the stored values", %{
      conn: conn,
      parent: parent,
      sb1: sb1
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{parent.id}/sandboxes/#{sb1.id}/edit")

      sandbox_id = sb1.id

      assert %{
               "mode" => "edit",
               "sandboxId" => ^sandbox_id,
               "initial" => %{"rawName" => "sb-1", "color" => "#ff0000"}
             } = props(view)["form"]
    end

    test "saves the name and colour and goes back to the list", %{
      conn: conn,
      parent: parent,
      sb1: sb1
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{parent.id}/sandboxes/#{sb1.id}/edit")

      assert update_sandbox(view, sb1, "Renamed SB", "#00ff00") =~
               "Sandbox updated"

      assert_patch(view, ~p"/projects/#{parent.id}/sandboxes")

      assert %{name: "renamed-sb", color: "#00ff00"} = Repo.reload!(sb1)
      assert props(view)["form"] == nil
    end

    test "keeps its own name, and refuses a sibling's or a blank one on the field",
         %{conn: conn, parent: parent, sb1: sb1} do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{parent.id}/sandboxes/#{sb1.id}/edit")

      update_sandbox(view, sb1, "SB 2")

      assert_reply(view, %{fieldErrors: field_errors})
      assert field_errors == %{"rawName" => ["Sandbox name already exists"]}

      update_sandbox(view, sb1, "")

      assert_reply(view, %{
        fieldErrors: %{"rawName" => ["This field can't be blank."]}
      })

      assert Repo.reload!(sb1).name == "sb-1"

      assert update_sandbox(view, sb1, "sb-1") =~ "Sandbox updated"
    end

    test "a viewer can't open the form, and is refused when they send the save",
         %{conn: conn, parent: parent, sb1: sb1} do
      viewer = insert(:user)
      insert(:project_user, project: parent, user: viewer, role: :viewer)
      insert(:project_user, project: sb1, user: viewer, role: :viewer)
      conn = log_in_user(conn, viewer)

      assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
               live(conn, ~p"/projects/#{parent.id}/sandboxes/#{sb1.id}/edit")

      assert to == ~p"/projects/#{parent.id}/sandboxes"
      assert flash["error"] == "You are not authorized to edit this sandbox"

      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")
      assert %{"canEdit" => false} = row(view, sb1)

      update_sandbox(view, sb1, "taken-over")
      assert_reply(view, %{error: "You are not authorized to edit this sandbox"})
      assert Repo.reload!(sb1).name == "sb-1"
    end

    test "only the sandbox whose form is open can be saved", %{
      conn: conn,
      parent: parent,
      sb1: sb1,
      sb2: sb2
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{parent.id}/sandboxes/#{sb1.id}/edit")

      update_sandbox(view, sb2, "not-the-open-form")
      assert_reply(view, %{error: "You are not authorized to edit this sandbox"})
      assert Repo.reload!(sb2).name == "sb-2"
    end

    test "replies with what the context refused", %{
      conn: conn,
      parent: parent,
      sb1: sb1
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{parent.id}/sandboxes/#{sb1.id}/edit")

      allow_mocks(view)

      for {result, message} <- [
            {{:error, :unauthorized},
             "You are not authorized to edit this sandbox"},
            {{:error, :not_found}, "Sandbox not found"},
            {{:error, :not_related_to_project},
             "Something went wrong while updating the sandbox. Please try again."}
          ] do
        Mimic.expect(Lightning.Projects, :update_sandbox, fn _sandbox,
                                                             _actor,
                                                             _attrs ->
          result
        end)

        update_sandbox(view, sb1, "renamed")
        assert_reply(view, %{error: ^message})
      end

      # A name taken after the form's check lands on the field, not on `name`.
      Mimic.expect(Lightning.Projects, :update_sandbox, fn _sandbox,
                                                           _actor,
                                                           _attrs ->
        {:error,
         %Project{}
         |> Ecto.Changeset.change()
         |> Ecto.Changeset.add_error(:name, "has already been taken")}
      end)

      # Free when the form is checked, taken by the time it's checked again.
      Lightning.Projects
      |> Mimic.expect(:sandbox_name_exists?, fn _parent_id, _name, _id ->
        false
      end)
      |> Mimic.expect(:sandbox_name_exists?, fn _parent_id, _name, _id ->
        true
      end)

      update_sandbox(view, sb1, "renamed")
      assert_reply(view, %{fieldErrors: field_errors})
      assert field_errors == %{"rawName" => ["Sandbox name already exists"]}

      assert Repo.reload!(sb1).name == "sb-1"
    end

    test "a missing sandbox's edit route says so", %{conn: conn, parent: parent} do
      {:ok, view, html} =
        live(
          conn,
          ~p"/projects/#{parent.id}/sandboxes/#{Ecto.UUID.generate()}/edit"
        )

      assert html =~ "Sandbox not found"
      assert props(view)["form"] == nil
    end
  end

  describe "delete" do
    defp delete_sandbox(view, sandbox, typed),
      do:
        send_event(view, "delete-sandbox", %{
          "id" => sandbox.id,
          "nameConfirmation" => typed
        })

    test "schedules the sandbox and its subtree, and refreshes the list", %{
      conn: conn,
      parent: parent,
      sb1: sb1,
      user: user
    } do
      child =
        insert(:project,
          name: "child",
          parent: sb1,
          project_users: [%{user: user, role: :owner}]
        )

      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      assert delete_sandbox(view, sb1, "sb-1") =~
               "Sandbox sb-1 scheduled for deletion."

      assert_reply(view, %{})

      assert Repo.reload!(sb1).scheduled_deletion
      assert Repo.reload!(child).scheduled_deletion

      assert %{
               "scheduledDeletion" => at,
               "canCancelDeletion" => true,
               "canDelete" => false
             } =
               row(view, sb1)

      assert at
    end

    test "moves the viewer to the parent's list when they are inside it", %{
      conn: conn,
      parent: parent,
      sb1: sb1,
      user: user
    } do
      grandchild =
        insert(:project,
          name: "grandchild",
          parent: sb1,
          project_users: [%{user: user, role: :owner}]
        )

      {:ok, view, _html} = live(conn, ~p"/projects/#{grandchild.id}/sandboxes")

      delete_sandbox(view, sb1, "sb-1")
      flash = assert_redirect(view, ~p"/projects/#{parent.id}/sandboxes")
      assert flash["info"] == "Sandbox sb-1 scheduled for deletion."
    end

    test "deleting a sibling from three levels down stays put", %{
      conn: conn,
      sb1: sb1,
      sb2: sb2,
      user: user
    } do
      deep =
        insert(:project,
          name: "deep",
          parent:
            insert(:project,
              name: "mid",
              parent: sb1,
              project_users: [%{user: user, role: :owner}]
            ),
          project_users: [%{user: user, role: :owner}]
        )

      {:ok, view, _html} = live(conn, ~p"/projects/#{deep.id}/sandboxes")

      assert delete_sandbox(view, sb2, "sb-2") =~ "scheduled for deletion"
      assert Repo.reload!(sb2).scheduled_deletion
    end

    test "refuses a name that doesn't match, and nothing is scheduled", %{
      conn: conn,
      parent: parent,
      sb1: sb1
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      delete_sandbox(view, sb1, "wrong")
      assert_reply(view, %{error: "must match the sandbox name"})

      send_event(view, "delete-sandbox", %{"id" => sb1.id})
      assert_reply(view, %{error: "must match the sandbox name"})

      refute Repo.reload!(sb1).scheduled_deletion
    end

    test "replies with what the context refused", %{
      conn: conn,
      parent: parent,
      sb1: sb1
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")
      allow_mocks(view)

      for {result, message} <- [
            {{:error, :unauthorized},
             "You don't have permission to delete this sandbox"},
            {{:error, :not_found}, "Sandbox not found"},
            {{:error, :boom},
             "Couldn't schedule this sandbox for deletion. Please try again."}
          ] do
        Mimic.expect(Lightning.Projects.Sandboxes, :schedule_sandbox_deletion, fn
          %Project{id: id}, _actor when id == sb1.id -> result
        end)

        delete_sandbox(view, sb1, "sb-1")
        assert_reply(view, %{error: ^message})
      end
    end

    test "a viewer is refused when they send it, and nothing is scheduled", %{
      conn: conn,
      parent: parent,
      sb1: sb1
    } do
      viewer = insert(:user)
      insert(:project_user, project: parent, user: viewer, role: :viewer)
      insert(:project_user, project: sb1, user: viewer, role: :viewer)

      {:ok, view, _html} =
        live(log_in_user(conn, viewer), ~p"/projects/#{parent.id}/sandboxes")

      assert %{"canDelete" => false} = row(view, sb1)

      delete_sandbox(view, sb1, "sb-1")

      assert_reply(view, %{
        error: "You are not authorized to delete this sandbox"
      })

      refute Repo.reload!(sb1).scheduled_deletion
    end
  end

  describe "restore" do
    setup %{parent: parent, user: user} do
      scheduled =
        insert(:project,
          name: "scheduled",
          env: "production",
          parent: parent,
          project_users: [%{user: user, role: :owner}],
          scheduled_deletion: now()
        )

      {:ok, scheduled: scheduled}
    end

    defp restore_sandbox(view, sandbox),
      do: send_event(view, "cancel-sandbox-deletion", %{"id" => sandbox.id})

    test "a scheduled sandbox offers only Restore", %{
      conn: conn,
      parent: parent,
      scheduled: scheduled
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      assert %{
               "env" => "production",
               "scheduledDeletion" => at,
               "canEdit" => false,
               "canDelete" => false,
               "canMerge" => false,
               "canCancelDeletion" => true,
               "restoreBlockedReason" => nil
             } = row(view, scheduled)

      assert at
    end

    test "clears the schedule and refreshes the list", %{
      conn: conn,
      parent: parent,
      scheduled: scheduled
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      assert restore_sandbox(view, scheduled) =~
               "Cancelled deletion of sandbox scheduled."

      assert_reply(view, %{})

      assert Repo.reload!(scheduled).scheduled_deletion == nil

      assert %{"scheduledDeletion" => nil, "canDelete" => true} =
               row(view, scheduled)
    end

    test "the plan's limit blocks Restore, and the context's refusal is replied",
         %{conn: conn, parent: parent, scheduled: scheduled} do
      message = %Lightning.Extensions.Message{text: "stub-blocked-message"}

      Mox.stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn
        %{type: :new_sandbox}, _ctx -> {:error, :too_many_sandboxes, message}
        _action, _ctx -> :ok
      end)

      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")

      assert row(view, scheduled)["restoreBlockedReason"] ==
               "stub-blocked-message"

      restore_sandbox(view, scheduled)
      assert_reply(view, %{error: "stub-blocked-message"})
      assert Repo.reload!(scheduled).scheduled_deletion
    end

    test "replies with what the context refused", %{
      conn: conn,
      parent: parent,
      scheduled: scheduled
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{parent.id}/sandboxes")
      allow_mocks(view)

      for {result, message} <- [
            {{:error, :unauthorized},
             "You are not authorized to cancel this sandbox's deletion"},
            {{:error, :not_found}, "Sandbox not found"}
          ] do
        Mimic.expect(
          Lightning.Projects.Sandboxes,
          :cancel_scheduled_sandbox_deletion,
          fn _sandbox, _actor -> result end
        )

        restore_sandbox(view, scheduled)
        assert_reply(view, %{error: ^message})
      end

      send_event(view, "cancel-sandbox-deletion", %{"id" => Ecto.UUID.generate()})

      assert_reply(view, %{error: "Sandbox not found"})
    end

    test "a viewer is refused when they send it, and the schedule stays", %{
      conn: conn,
      parent: parent,
      scheduled: scheduled
    } do
      viewer = insert(:user)
      insert(:project_user, project: parent, user: viewer, role: :viewer)
      insert(:project_user, project: scheduled, user: viewer, role: :viewer)

      {:ok, view, _html} =
        live(log_in_user(conn, viewer), ~p"/projects/#{parent.id}/sandboxes")

      assert %{"canCancelDeletion" => false} = row(view, scheduled)

      restore_sandbox(view, scheduled)

      assert_reply(view, %{
        error: "You are not authorized to cancel this sandbox's deletion"
      })

      assert Repo.reload!(scheduled).scheduled_deletion
    end

    test "restoring reloads the list and shows the current project's new schedule",
         %{conn: conn, sb1: sb1, scheduled: scheduled} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{sb1.id}/sandboxes")

      Repo.update!(Ecto.Changeset.change(sb1, scheduled_deletion: now()))
      restore_sandbox(view, scheduled)

      assert row(view, sb1)["scheduledDeletion"]
    end
  end
end
