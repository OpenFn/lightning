defmodule LightningWeb.ProjectLive.DeletionTeardownTest do
  @moduledoc """
  Session teardown for project-scoped LiveViews when the thing they are scoped
  to is deleted.

  A mount-time decision is not durable: the project can be wound down, and the
  workflow can be deleted, while the socket lives. Neither removes a membership
  row, so nothing about the socket's own authorisation changes — the view has to
  hear about the deletion itself.
  """
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import Phoenix.LiveViewTest

  alias Lightning.Projects
  alias Lightning.Workflows

  # The broadcast lands in the view's mailbox synchronously, but the teardown is
  # asynchronous relative to the test process.
  @teardown_timeout 2_000

  setup %{conn: conn} do
    Mox.stub(
      Lightning.Extensions.MockProjectHook,
      :handle_project_validation,
      & &1
    )

    owner = insert(:user)

    project =
      insert(:project, project_users: [%{user: owner, role: :owner}])

    workflow = insert(:workflow, project: project)

    %{
      conn: log_in_user(conn, owner),
      owner: owner,
      project: project,
      workflow: workflow
    }
  end

  describe "the project is scheduled for deletion" do
    for {label, suffix} <- [
          {"workflow list", "/w"},
          {"history", "/history"},
          {"settings", "/settings"},
          {"collaborative editor", :editor}
        ] do
      test "bounces the #{label} to the project list", %{
        conn: conn,
        project: project,
        workflow: workflow
      } do
        path =
          case unquote(suffix) do
            :editor -> ~p"/projects/#{project}/w/#{workflow}"
            suffix -> "/projects/#{project.id}#{suffix}"
          end

        {:ok, view, _html} = live(conn, path, on_error: :raise)

        {:ok, _project} = Projects.schedule_project_deletion(project)

        flash = assert_redirect(view, ~p"/projects", @teardown_timeout)

        assert flash["info"] == "Project deleted."
      end
    end

    test "leaves a view on another project mounted", %{
      conn: conn,
      owner: owner,
      project: project
    } do
      other_project =
        insert(:project, project_users: [%{user: owner, role: :owner}])

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/w", on_error: :raise)

      {:ok, _project} = Projects.schedule_project_deletion(other_project)

      assert_still_mounted(view, ~p"/projects")
    end

    # Scheduling a sandbox's deletion cascades to its descendants, so a session
    # held on a descendant is just as stale as one held on the target.
    test "bounces a session held on a scheduled sandbox's descendant", %{
      conn: conn,
      owner: owner
    } do
      parent = insert(:sandbox, project_users: [%{user: owner, role: :owner}])

      child =
        insert(:project,
          parent: parent,
          project_users: [%{user: owner, role: :owner}]
        )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{child}/w", on_error: :raise)

      {:ok, _sandbox} =
        Lightning.Projects.Sandboxes.schedule_sandbox_deletion(parent, owner)

      flash = assert_redirect(view, ~p"/projects", @teardown_timeout)

      assert flash["info"] == "Project deleted."
    end
  end

  describe "the open workflow is deleted" do
    test "bounces the collaborative editor to the project's workflow list", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/w/#{workflow}", on_error: :raise)

      {:ok, _} = Workflows.mark_for_deletion(workflow, insert(:user))

      flash =
        assert_redirect(view, ~p"/projects/#{project}/w", @teardown_timeout)

      assert flash["info"] == "Workflow deleted."
    end

    test "leaves the editor mounted when a different workflow is deleted", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      other_workflow = insert(:workflow, project: project)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/w/#{workflow}", on_error: :raise)

      {:ok, _} = Workflows.mark_for_deletion(other_workflow, insert(:user))

      assert_still_mounted(view, ~p"/projects/#{project}/w")
    end

    # The deletion reaches every project-scoped view on the project's topic, not
    # just the one holding the workflow open. A view with no `handle_info/2` for
    # it would die on the message.
    test "leaves other project views mounted", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      for path <- [
            ~p"/projects/#{project}/w",
            ~p"/projects/#{project}/settings",
            ~p"/projects/#{project}/history"
          ] do
        {:ok, view, _html} = live(conn, path, on_error: :raise)

        {:ok, _} =
          Workflows.mark_for_deletion(
            insert(:workflow, project: project),
            insert(:user)
          )

        assert_still_mounted(view, ~p"/projects/#{project}/w")
      end

      refute Repo.get!(Lightning.Workflows.Workflow, workflow.id).deleted_at
    end

    # Deletions ride the project's topic precisely so that saves — which are
    # frequent — never wake the editor. Guard against a future subscription
    # putting them back.
    test "leaves the editor mounted when a workflow is saved", %{
      conn: conn,
      owner: owner,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/w/#{workflow}", on_error: :raise)

      {:ok, _workflow} =
        Workflows.save_workflow(
          Workflows.change_workflow(workflow, %{name: "Renamed"}),
          owner
        )

      assert_still_mounted(view, ~p"/projects/#{project}/w")
    end
  end

  # `refute_redirected/2` reads the mailbox as it is, so give the broadcast the
  # same room to arrive that the positive cases get before concluding it did
  # nothing.
  defp assert_still_mounted(view, to) do
    Process.sleep(200)
    :ok = refute_redirected(view, to)
    assert render(view)
  end
end
