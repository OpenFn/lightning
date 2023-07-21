defmodule LightningWeb.WorkflowLive.EditorTest do
  use LightningWeb.ConnCase, async: true
  use Oban.Testing, repo: Lightning.Repo
  import Phoenix.LiveViewTest
  import Lightning.WorkflowLive.Helpers
  # import Lightning.Factories

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

    view |> select_node(job)

    view |> job_panel_element(job)

    assert view |> job_panel_element(job) |> render() =~ "First Job",
           "can see the job name in the panel"

    view |> click_edit(job)

    assert view |> job_edit_view(job) |> has_element?(),
           "can see the job_edit_view component"
  end

  # Ensure that @latest is converted into a version number
  @tag skip: true
  test "mounts the JobEditor with the correct attrs"

  describe "manual runs" do
    test "viewers can't run a job" do
      # view
      # |> with_target("#manual-job-#{job.id}")
    end

    test "can see the last 3 dataclips" do
    end

    @tag skip: true
    test "can create a new dataclip"

    test "can't with a new dataclip if it's invalid", %{
      conn: conn,
      project: p,
      workflow: w
    } do
      job = w.jobs |> hd

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{p}/w/#{w}?#{[s: job, m: "expand"]}")

      view
      |> form("#manual-job-#{job.id} form", %{
        "manual_workorder" => %{"body" => "["}
      })
      |> render_change()

      view
      |> element("#manual-job-#{job.id} form")
      |> render_submit()

      refute_enqueued(worker: Lightning.Pipeline)

      assert view
             |> element("#manual-job-#{job.id} form")
             |> render()

      assert view |> has_element?("#manual-job-#{job.id} form", "Invalid body")
    end

    test "can run a job", %{conn: conn, project: p, workflow: w} do
      job = w.jobs |> hd

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{p}/w/#{w}?#{[s: job, m: "expand"]}")

      assert view
             |> element(
               "#manual-job-#{job.id} form button[type=submit][disabled]"
             )
             |> has_element?()

      view
      |> form("#manual-job-#{job.id} form", %{
        "manual_workorder" => %{"body" => "{}"}
      })
      |> render_change()

      refute view
             |> element(
               "#manual-job-#{job.id} form button[type=submit][disabled]"
             )
             |> has_element?()

      view
      |> element("#manual-job-#{job.id} form")
      |> render_submit()

      assert_enqueued(worker: Lightning.Pipeline)
      assert [run_viewer] = live_children(view)
      assert run_viewer |> render() =~ "Not started."
    end
  end

  describe "Editor events" do
    @tag skip: true
    test "can handle request_metadata event", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}")

      assert has_element?(view, "#builder-new")

      assert view
             |> with_target("#builder-new")
             |> render_click("request_metadata", %{})

      assert_push_event(view, "metadata_ready", %{"error" => "no_credential"})
    end
  end
end
