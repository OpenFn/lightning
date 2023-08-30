defmodule LightningWeb.WorkflowLive.EditorTest do
  alias Lightning.Invocation
  alias Lightning.InvocationFixtures
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
    @tag role: :viewer
    test "viewers can't run a job", %{
      conn: conn,
      project: p,
      workflow: w
    } do
      job = w.jobs |> hd

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{p}/w/#{w}?#{[s: job, m: "expand"]}")

      # dataclip dropdown is disabled
      assert view
             |> element(
               ~s{#manual-job-#{job.id} form #manual_workorder_dataclip_id[disabled='disabled']}
             )
             |> has_element?()

      # run button is disabled
      assert view
             |> element(
               ~s{#manual-job-#{job.id} form button[type='submit'][disabled='disabled']}
             )
             |> has_element?()

      # Why can't I see any Flash message while I can see it appear on the UI.
      # assert view |> with_target("#manual-job-#{job.id}") |> render_click("run", %{"manual_workorder" => %{}}) =~ "You are not authorized to perform this action."
    end

    @tag role: :admin
    test "can see the last 3 dataclips", %{
      conn: conn,
      project: p,
      workflow: w
    } do
      job = w.jobs |> hd

      first_dataclip =
        InvocationFixtures.run_fixture(project_id: p.id, job_id: job.id)
        |> Map.get(:input_dataclip_id)

      last_3_dataclips =
        for _ <- 1..3,
            do:
              InvocationFixtures.run_fixture(project_id: p.id, job_id: job.id)
              |> Map.get(:input_dataclip_id)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{p}/w/#{w}?#{[s: job, m: "expand"]}")

      last_3_dataclips
      |> Enum.each(fn dataclip ->
        assert view
               |> element(
                 ~s{#manual-job-#{job.id} form #manual_workorder_dataclip_id option[value='#{dataclip}']}
               )
               |> has_element?()
      end)

      refute view
             |> element(
               ~s{#manual-job-#{job.id} form #manual_workorder_dataclip_id option[value='#{first_dataclip}']}
             )
             |> has_element?()
    end

    test "can create a new dataclip", %{
      conn: conn,
      project: p,
      workflow: w
    } do
      job = w.jobs |> hd

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{p}/w/#{w}?#{[s: job, m: "expand"]}")

      assert Invocation.list_dataclips_for_job(job) |> Enum.count() == 0

      view
      |> form("#manual-job-#{job.id} form",
        manual_workorder: %{
          body: Jason.encode!(%{"a" => 1})
        }
      )
      |> render_submit()

      assert Invocation.list_dataclips_for_job(job) |> Enum.count() == 1
    end

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
