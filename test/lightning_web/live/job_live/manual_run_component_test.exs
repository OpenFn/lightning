defmodule LightningWeb.JobLive.ManualRunComponentTest do
  use LightningWeb.ConnCase, async: true
  use Oban.Testing, repo: Lightning.Repo

  import Phoenix.LiveViewTest

  import Lightning.JobsFixtures
  import Lightning.CredentialsFixtures
  import Lightning.InvocationFixtures

  alias Lightning.Repo
  alias Lightning.Attempt

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  setup %{project: project} do
    project_credential_fixture(project_id: project.id)
    %{job: job} = workflow_job_fixture(project_id: project.id)
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

  test "has custom option on webhook type job ", %{
    conn: conn,
    job: job,
    project: project
  } do
    {:ok, view, _html} =
      live(
        conn,
        ~p"/projects/#{project.id}/w/#{job.workflow_id}/j/#{job.id}"
      )

    assert view
           |> has_element?(
             "select[name='manual_run[dataclip_id]'] option[value='custom']"
           )

    assert view
           |> has_element?("textarea#manual_run_body")
  end

  test "has custom option on cron type job", %{
    conn: conn,
    project: project
  } do
    job = job_fixture(trigger: %{type: :cron, cron_expression: "* * * * *"})

    {:ok, view, _html} =
      live(
        conn,
        ~p"/projects/#{project.id}/w/#{job.workflow_id}/j/#{job.id}"
      )

    assert view
           |> has_element?(
             "select[name='manual_run[dataclip_id]'] option[value='custom']"
           )

    assert view
           |> has_element?("textarea#manual_run_body")
  end

  test "has custom option on on_job_success type job", %{
    conn: conn,
    project: project
  } do
    upstream_job = job_fixture()

    job =
      job_fixture(
        trigger: %{type: :on_job_success, upstream_job_id: upstream_job.id}
      )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/projects/#{project.id}/w/#{job.workflow_id}/j/#{job.id}"
      )

    assert view
           |> has_element?(
             "select[name='manual_run[dataclip_id]'] option[value='custom']"
           )

    assert view
           |> has_element?("textarea#manual_run_body")
  end

  test "shows 3 latest dataclips for a job with several runs", %{
    conn: conn,
    job: _job,
    project: project,
    user: user
  } do
    %{job: job, trigger: trigger} =
      workflow_job_fixture(
        project_id: project.id,
        body: ~s[fn(state => { return {...state, extra: "data"} })]
      )

    work_order = work_order_fixture(workflow_id: job.workflow_id)

    [d1, d2, d3, d4] =
      1..4 |> Enum.map(fn _ -> dataclip_fixture(project_id: project.id) end)

    reason =
      reason_fixture(
        trigger_id: trigger.id,
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
        ~p"/projects/#{project.id}/w/#{job.workflow_id}/j/#{job.id}"
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

    assert view |> enter_body("{\"aaaa\": 1}")

    assert view
           |> element("button[phx-click='confirm']")
           |> render_click() =~ "aaaa"

    # bad input
    view |> enter_body("xxx") =~ "is invalid"

    assert render_component(LightningWeb.JobLive.ManualRunComponent,
             id: "manual-job-#{job.id}",
             project: project,
             job_id: job.id,
             job: job,
             current_user: user,
             on_run: nil,
             builder_state: %{job_id: job.id, dataclip: d3},
             can_run_job: true,
             return_to:
               Routes.project_workflow_path(
                 conn,
                 :show,
                 project.id,
                 job.workflow_id
               )
           ) =~ "<option selected value=\"#{d3.id}\">#{d3.id}</option>"

    assert render_component(LightningWeb.JobLive.ManualRunComponent,
             id: "manual-job-#{job.id}",
             project: project,
             job_id: job.id,
             job: job,
             current_user: user,
             on_run: nil,
             builder_state: %{job_id: job.id, dataclip: d4},
             can_run_job: true,
             return_to:
               Routes.project_workflow_path(
                 conn,
                 :show,
                 project.id,
                 job.workflow_id
               )
           ) =~ "<option selected value=\"#{d4.id}\">#{d4.id}</option>"
  end

  test "project viewers can't run a job from the inspector", %{
    conn: conn,
    project: project
  } do
    {conn, _user} = setup_project_user(conn, project, :viewer)

    %{job: job} =
      workflow_job_fixture(
        project_id: project.id,
        body: ~s[fn(state => { return {...state, extra: "data"} })]
      )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/projects/#{project.id}/w/#{job.workflow_id}/j/#{job.id}"
      )

    assert view
           |> element("button[phx-click='confirm'][disabled]")
           |> has_element?()

    view
    |> with_target("#manual-job-#{job.id}")
    |> render_click("confirm", %{}) =~
      "You are not authorized to perform this action."
  end
end
