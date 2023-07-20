defmodule LightningWeb.WorkflowLive.EditTest do
  use LightningWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Lightning.WorkflowLive.Helpers

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "new" do
    test "builds a new workflow", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      # Naively add a job via the editor (calling the push-change event)
      assert view
             |> push_patches_to_view([add_job_patch()])

      # The server responds with a patch with any further changes
      assert_reply(
        view,
        %{
          patches: [
            %{op: "add", path: "/jobs/0/project_credential_id", value: nil},
            %{
              op: "add",
              path: "/jobs/0/errors",
              value: %{
                "body" => ["can't be blank"],
                "name" => ["can't be blank"]
              }
            },
            %{op: "add", path: "/jobs/0/enabled", value: "true"},
            %{op: "add", path: "/jobs/0/body", value: ""},
            %{
              op: "add",
              path: "/jobs/0/adaptor",
              value: "@openfn/language-common@latest"
            }
          ]
        }
      )
    end

    @tag role: :editor
    test "creating a new workflow", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      assert view |> push_patches_to_view(initial_workflow_patchset(project))

      view |> fill_workflow_name("My Workflow")

      assert view |> save_is_disabled()

      {job, _, _} = view |> select_first_job()

      view |> fill_job_fields(job, %{name: "My Job"})

      view |> click_edit(job)

      view |> change_editor_text("some body")

      refute view |> save_is_disabled()

      assert view |> has_pending_changes()

      view |> click_save()

      refute view |> has_pending_changes()
    end

    @tag role: :viewer
    test "viewers can't create new workflows", %{conn: conn, project: project} do
      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/w/new")
        |> follow_redirect(conn, ~p"/projects/#{project.id}/w")

      assert html =~ "You are not authorized to perform this action."
    end
  end

  describe "edit" do
    setup :create_workflow

    test "users can edit an existing workflow", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}")

      assert html =~ workflow.name
    end

    @tag role: :viewer
    test "viewers can't edit existing workflows", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, _view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}")

      flunk("TODO: test that viewers can't edit workflows")
    end
  end
end
