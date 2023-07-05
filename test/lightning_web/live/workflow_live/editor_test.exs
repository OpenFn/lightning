defmodule LightningWeb.WorkflowLive.EditorTest do
  use LightningWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Lightning.Factories

  setup :register_and_log_in_user
  setup :create_project_for_current_user
  setup :create_workflow

  test "can edit a jobs body", %{
    project: project,
    workflow: workflow,
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}")

    job = workflow.jobs |> List.first()

    view |> select_job(job)

    assert view |> job_panel_element(job) |> render() =~ "First Job",
           "can see the job name in the panel"

    view |> click_edit(job)

    assert view |> job_edit_view(job) |> has_element?(),
           "can see the job_edit_view component"

    # IO.inspect(html)
  end

  # Ensure that @latest is converted into a version number
  test "mounts the JobEditor with the correct attrs"

  describe "manual runs" do
    test "can see the last 3 dataclips"
    test "can create a new dataclip"
    test "can run a workflow"
  end

  defp create_workflow(%{project: project}) do
    trigger = build(:trigger, type: :webhook)

    job =
      build(:job,
        body: ~s[fn(state => { return {...state, extra: "data"} })],
        name: "First Job"
      )

    workflow =
      build(:workflow, project: project)
      |> with_job(job)
      |> with_trigger(trigger)
      |> with_edge({trigger, job})
      |> insert()

    %{workflow: workflow |> Lightning.Repo.preload([:jobs, :triggers, :edges])}
  end

  defp select_job(view, job) do
    view
    |> editor_element()
    |> render_hook("hash-changed", %{"hash" => "#id=#{job.id}"})
  end

  defp editor_element(view) do
    view |> element("div[phx-hook=WorkflowEditor]")
  end

  defp job_panel_element(view, job) do
    view |> element("#job-pane-#{job.id}")
  end

  defp job_edit_view(view, job) do
    view |> element("#job-edit-view-#{job.id}")
  end

  defp click_edit(view, job) do
    view
    |> element("#job-pane-#{job.id} button[phx-click=set_expanded_job]")
    |> render_click()
  end
end
