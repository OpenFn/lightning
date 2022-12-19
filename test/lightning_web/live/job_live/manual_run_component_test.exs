defmodule LightningWeb.JobLive.ManualRunComponentTest do
  use LightningWeb.ConnCase, async: true
  use Oban.Testing, repo: Lightning.Repo

  import Phoenix.LiveViewTest

  import Lightning.JobsFixtures
  import Lightning.CredentialsFixtures
  import Lightning.InvocationFixtures

  alias LightningWeb.RouteHelpers

  alias Lightning.Attempt

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  setup %{project: project} do
    project_credential_fixture(project_id: project.id)
    job = workflow_job_fixture(project_id: project.id)
    %{job: job}
  end

  defp enter_dataclip_id(view, value) do
    view
    |> element("select[name='manual_run[dataclip_id]']")
    |> render_change(manual_run: [dataclip_id: value])
  end

  defp enter_body(view, value) do
    view
    |> element("select[name='manual_run[dataclip_id]']")
    |> render_change(manual_run: [dataclip_id: "custom", body: value])
  end

  defp run_button(view, disabled \\ '') do
    view
    |> element("button[disabled='#{disabled}']", "Run")
  end

  test "renders", %{conn: conn, job: job, project: project} do
    {:ok, view, _html} =
      live(
        conn,
        RouteHelpers.workflow_edit_job_path(project.id, job.workflow_id, job.id)
      )

    assert view |> enter_dataclip_id("") =~ html_escape("can't be blank")
    assert view |> enter_dataclip_id("abc") =~ "is invalid"

    refute view |> enter_dataclip_id(Ecto.UUID.generate()) =~
             html_escape("is invalid")

    assert view |> run_button() |> render_click() =~
             html_escape("doesn't exist")

    assert view |> run_button('disabled') |> has_element?()

    dataclip = dataclip_fixture()

    refute view |> enter_dataclip_id(dataclip.id) =~
             html_escape("is invalid")

    view |> run_button() |> render_click()

    view |> assert_push_event("push-hash", %{hash: "output"})

    assert_enqueued(worker: Lightning.Pipeline)

    assert [run_viewer] = live_children(view)

    assert run_viewer |> render() =~ "Not started."
  end

  test "has custom option on webhook type job ", %{
    conn: conn,
    job: job,
    project: project
  } do
    {:ok, view, _html} =
      live(
        conn,
        RouteHelpers.workflow_edit_job_path(project.id, job.workflow_id, job.id)
      )

    assert view
           |> has_element?(
             "select[name='manual_run[dataclip_id]'] option[value='custom']"
           )
  end

  test "has no option on job with no runs and not of type webhook", %{
    conn: conn,
    project: project
  } do
    job = job_fixture(trigger: %{type: :cron, cron_expression: "* * * * *"})

    {:ok, view, _html} =
      live(
        conn,
        RouteHelpers.workflow_edit_job_path(project.id, job.workflow_id, job.id)
      )

    refute view
           |> has_element?("select[name='manual_run[dataclip_id]'] option")
  end

  test "shows 3 latest dataclips for a job with several runs", %{
    conn: conn,
    job: _job,
    project: project,
    user: user
  } do
    job =
      workflow_job_fixture(
        project_id: project.id,
        body: ~s[fn(state => { return {...state, extra: "data"} })]
      )

    work_order = work_order_fixture(workflow_id: job.workflow_id)

    [d1, d2, d3, d4] =
      1..4 |> Enum.map(fn _ -> dataclip_fixture(project_id: project.id) end)

    reason =
      reason_fixture(
        trigger_id: job.trigger.id,
        dataclip_id: d4.id
      )

    now = Timex.now()

    Attempt.new(%{
      work_order_id: work_order.id,
      reason_id: reason.id,
      runs: [
        %{
          job_id: job.id,
          started_at: now |> Timex.shift(seconds: -50),
          finished_at: now |> Timex.shift(seconds: -40),
          exit_code: 0,
          input_dataclip_id: d1.id
        },
        %{
          job_id: job.id,
          started_at: now |> Timex.shift(seconds: -40),
          finished_at: now |> Timex.shift(seconds: -30),
          exit_code: 0,
          input_dataclip_id: d2.id
        },
        %{
          job_id: job.id,
          started_at: now |> Timex.shift(seconds: -30),
          finished_at: now |> Timex.shift(seconds: -1),
          exit_code: 0,
          input_dataclip_id: d3.id
        },
        %{
          job_id: job.id,
          started_at: now |> Timex.shift(seconds: -25),
          finished_at: now |> Timex.shift(seconds: -10),
          exit_code: 0,
          input_dataclip_id: d4.id
        }
      ]
    })
    |> Lightning.Repo.insert!()

    {:ok, view, _html} =
      live(
        conn,
        RouteHelpers.workflow_edit_job_path(project.id, job.workflow_id, job.id)
      )

    refute view
           |> has_element?(
             "select[name='manual_run[dataclip_id]'] option[value=#{d1.id}]"
           )

    assert view
           |> has_element?(
             "select[name='manual_run[dataclip_id]'] option[value=#{d2.id}]"
           )

    assert view
           |> has_element?(
             "select[name='manual_run[dataclip_id]'] option[value=#{d3.id}]"
           )

    assert view
           |> element(
             "select[name='manual_run[dataclip_id]'] option[selected='selected']"
           )
           |> render() =~ d4.id

    view |> enter_dataclip_id(d2.id)

    assert view
           |> element(
             "select[name='manual_run[dataclip_id]'] option[selected='selected']"
           )
           |> render() =~ d2.id

    view |> enter_body("{\"a\": 1}")

    # body textarea is displayed
    assert view
           |> has_element?("textarea#manual_run_body")

    assert view
           |> element(
             "select[name='manual_run[dataclip_id]'] option[selected='selected']"
           )
           |> render() =~ "Custom"

    # bad input
    view |> enter_body("xxx") =~ "is invalid"

    assert render_component(LightningWeb.JobLive.ManualRunComponent,
             id: "manual-job-#{job.id}",
             project: project,
             job_id: job.id,
             job: job,
             current_user: user,
             on_run: nil,
             builder_state: %{job_id: job.id, dataclip: d3}
           ) =~ "<option selected value=\"#{d3.id}\">#{d3.id}</option>"

    assert render_component(LightningWeb.JobLive.ManualRunComponent,
             id: "manual-job-#{job.id}",
             project: project,
             job_id: job.id,
             job: job,
             current_user: user,
             on_run: nil,
             builder_state: %{job_id: job.id, dataclip: d4}
           ) =~ "<option selected value=\"#{d4.id}\">#{d4.id}</option>"
  end
end
