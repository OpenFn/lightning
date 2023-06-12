defmodule LightningWeb.WorkflowNewLiveTest do
  use LightningWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias LightningWeb.WorkflowLive.Components

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "CronSetupComponent" do
    test "xyz" do
      assigns = %{
        form: %{
          errors: [],
          changes: %{
            enabled: true,
            name: "My Job"
          }
        },
        cancel_url: "/path/to/cancel"
      }

      # Invoke the job_form function and capture the rendered HTML
      rendered_html = Components.job_form(assigns) |> rendered_to_string()

      # Example assertion
      assert rendered_html =~ "Untitled Job"
      # Example assertion
      assert rendered_html =~ "Job Name"
      # Example assertion
      assert rendered_html =~ "AdaptorPicker"
    end
  end

  describe "edit" do
    test "edit_job", %{conn: conn, project: project} do
      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w-new/new/j/fac0594f-e836-4a36-b408-ac96316deb49"
        )

      LightningWeb.WorkflowNewLive.handle_event(
        "push-change",
        %{"patches" => %{"workflow_params" => %{}}},
        conn
      )
      |> IO.inspect()

      assert html =~ "ckjshj"
      # %{"value" => %{"id" => job_id, "name" => job_name}} =
      #   job_patch = add_job_patch("my_job") |> IO.inspect()

      # assert view
      #        |> element("#editor-#{project.id}")
      #        |> push_patches_to_view([job_patch]) =~ "jhknsd"

      # {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/w-new/new/j/#{job_id}")

      # IO.inspect(job_id)
      # IO.inspect(job_name)
      # IO.inspect(job_patch)

      # # assert html =~ job_name

      # assert view |> element("div", "job-1") |> has_element?()
    end
  end

  describe "new" do
    test "builds a new workflow", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w-new/new")

      # Naively add a job via the editor (calling the push-change event)
      assert view
             |> element("#editor-#{project.id}")
             |> push_patches_to_view([add_job_patch()])

      # The server responds with a patch with any further changes
      assert_reply(
        view,
        %{
          patches: [
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
