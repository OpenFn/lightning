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
             |> element("#editor-#{project.id}")
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
      {:ok, _view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      flunk("TODO: test interacting with the editor and saving")
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

    @tag role: :viewer, skip: true
    test "viewers can't edit existing workflows", %{conn: conn, project: project} do
      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/w/new")
        |> follow_redirect(~r"/projects/#{project.id}/w")

      assert html =~ "You are not authorized to perform this action."
    end
  end

  defp push_patches_to_view(elem, patches) do
    elem
    |> render_hook("push-change", %{patches: patches})
  end

  defp add_job_patch(name \\ "") do
    Jsonpatch.diff(
      %{jobs: []},
      %{jobs: [%{id: Ecto.UUID.generate(), name: name}]}
    )
    |> Jsonpatch.Mapper.to_map()
    |> List.first()
    |> Lightning.Helpers.json_safe()
  end
end
