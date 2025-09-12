defmodule LightningWeb.SandboxLive.IndexTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

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
          project_users: [%{user: user, role: :owner}]
        )

      sb1 =
        insert(:project,
          name: "sb-1",
          color: "#ff0000",
          env: "staging",
          parent: parent
        )

      sb2 =
        insert(:project,
          name: "sb-2",
          color: "#00ff00",
          env: "dev",
          parent: parent
        )

      {:ok, parent: parent, sb1: sb1, sb2: sb2}
    end

    test "lists sandboxes; empty state shows message", %{
      conn: conn,
      parent: parent,
      sb1: sb1,
      sb2: sb2
    } do
      {:ok, view, html} =
        live(conn, ~p"/projects/#{parent.id}/sandboxes", on_error: :raise)

      assert html =~ "Sandboxes"
      assert has_element?(view, "#edit-sandbox-#{sb1.id}")
      assert has_element?(view, "#edit-sandbox-#{sb2.id}")

      Repo.delete!(sb1)
      Repo.delete!(sb2)

      html2 = render_patch(view, ~p"/projects/#{parent.id}/sandboxes")
      assert html2 =~ "No sandboxes found."
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

      view |> element("#edit-sandbox-#{sb1.id}") |> render_click()

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

      view |> element("#delete-sandbox-#{sb1.id}") |> render_click()
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

      Mimic.expect(Lightning.Projects.Sandboxes, :delete_sandbox, fn parent_arg,
                                                                     user_arg,
                                                                     %Project{
                                                                       id: id
                                                                     } ->
        assert parent_arg.id == parent.id
        assert user_arg.id == user.id
        assert id == sb1.id
        {:ok, %Project{}}
      end)

      Mimic.expect(Lightning.Projects, :list_sandboxes, fn id ->
        assert id == parent.id
        [sb2]
      end)

      Mimic.allow(Lightning.Projects.Sandboxes, self(), view.pid)
      Mimic.allow(Lightning.Projects, self(), view.pid)

      view |> element("#delete-sandbox-#{sb1.id}") |> render_click()

      html =
        view
        |> form("#confirm-delete-sandbox form", confirm: %{"name" => sb1.name})
        |> render_submit()

      assert html =~ "Sandbox #{sb1.name} deleted"
      assert has_element?(view, "#edit-sandbox-#{sb2.id}")

      target_id = sb2.id

      Mimic.expect(Lightning.Projects.Sandboxes, :delete_sandbox, fn parent_arg,
                                                                     user_arg,
                                                                     %Project{
                                                                       id:
                                                                         ^target_id
                                                                     } ->
        assert parent_arg.id == parent.id
        assert user_arg.id == user.id
        {:error, :unauthorized}
      end)

      Mimic.allow(Lightning.Projects.Sandboxes, self(), view.pid)

      view |> element("#delete-sandbox-#{target_id}") |> render_click()

      html =
        view
        |> form("#confirm-delete-sandbox form", confirm: %{"name" => sb2.name})
        |> render_submit()

      assert html =~ "You don’t have permission to delete this sandbox"

      Mimic.expect(Lightning.Projects.Sandboxes, :delete_sandbox, fn parent_arg,
                                                                     user_arg,
                                                                     %Project{
                                                                       id:
                                                                         ^target_id
                                                                     } ->
        assert parent_arg.id == parent.id
        assert user_arg.id == user.id
        {:error, :not_found}
      end)

      Mimic.allow(Lightning.Projects.Sandboxes, self(), view.pid)

      view |> element("#delete-sandbox-#{target_id}") |> render_click()

      html =
        view
        |> form("#confirm-delete-sandbox form", confirm: %{"name" => sb2.name})
        |> render_submit()

      assert html =~ "Sandbox not found"

      Mimic.expect(Lightning.Projects.Sandboxes, :delete_sandbox, fn parent_arg,
                                                                     user_arg,
                                                                     %Project{
                                                                       id:
                                                                         ^target_id
                                                                     } ->
        assert parent_arg.id == parent.id
        assert user_arg.id == user.id
        {:error, :boom}
      end)

      Mimic.allow(Lightning.Projects.Sandboxes, self(), view.pid)

      view |> element("#delete-sandbox-#{target_id}") |> render_click()

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

      view |> element("#delete-sandbox-#{sb1.id}") |> render_click()
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

      view |> element("#delete-sandbox-#{sb1.id}") |> render_click()
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

      view |> element("#delete-sandbox-#{sb1.id}") |> render_click()
      assert has_element?(view, "#confirm-delete-sandbox")

      view
      |> element("#confirm-delete-sandbox [aria-label='Close']")
      |> render_click()

      refute has_element?(view, "#confirm-delete-sandbox")

      view |> element("#delete-sandbox-#{sb1.id}") |> render_click()
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
end
