defmodule LightningWeb.JobLive.ManualRunComponentTest do
  use LightningWeb.ConnCase, async: true
  use Oban.Testing, repo: Lightning.Repo

  import Phoenix.LiveViewTest

  import Lightning.JobsFixtures
  import Lightning.InvocationFixtures

  import Lightning.Factories

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  test "has custom option", %{project: project, user: user} do
    job = build(:job) |> for_project(project) |> insert()

    html =
      render_component(LightningWeb.JobLive.ManualRunComponent,
        id: "manual-job-#{job.id}",
        job: job,
        dataclips: [],
        project: project,
        user: user,
        on_run: nil,
        can_run_job: true,
        return_to: ~p"/"
      )
      |> Floki.parse_fragment!()

    assert html
           |> Floki.find("textarea#manual_run_form_body")
           |> Enum.any?()
  end

  test "shows 3 latest dataclips for a job with several runs", %{
    conn: conn,
    project: project
  } do
    %{job: job} =
      workflow_job_fixture(
        project: project,
        body: ~s[fn(state => { return {...state, extra: "data"} })]
      )

    work_order = work_order_fixture(workflow_id: job.workflow_id)

    [d1, d2, d3, d4] =
      1..4 |> Enum.map(fn _ -> insert(:dataclip, project: project) end)

    reason = insert(:reason, type: :webhook, dataclip: d4)

    now = Timex.now()

    insert(:attempt, %{
      work_order: work_order,
      reason: reason,
      runs: [
        %{
          job: job,
          started_at: now |> Timex.shift(seconds: -50),
          finished_at: now |> Timex.shift(seconds: -40),
          exit_code: 0,
          input_dataclip: d1
        },
        %{
          job: job,
          started_at: now |> Timex.shift(seconds: -40),
          finished_at: now |> Timex.shift(seconds: -30),
          exit_code: 0,
          input_dataclip: d2
        },
        %{
          job: job,
          started_at: now |> Timex.shift(seconds: -30),
          finished_at: now |> Timex.shift(seconds: -1),
          exit_code: 0,
          input_dataclip: d3
        },
        %{
          job: job,
          started_at: now |> Timex.shift(seconds: -25),
          finished_at: now |> Timex.shift(seconds: -10),
          exit_code: 0,
          input_dataclip: d4
        }
      ]
    })

    {:ok, view, _html} =
      live(
        conn,
        ~p"/projects/#{project.id}/w/#{job.workflow_id}?s=#{job.id}&m=expand"
      )

    refute view
           |> has_element?(
             "select[name='manual_workorder[dataclip_id]'] option[value=#{d1.id}]"
           )

    assert view
           |> has_element?(
             "select[name='manual_workorder[dataclip_id]'] option[value=#{d2.id}]"
           )

    assert view
           |> has_element?(
             "select[name='manual_workorder[dataclip_id]'] option[value=#{d3.id}]"
           )

    assert view
           |> element(
             "select[name='manual_workorder[dataclip_id]'] option[selected='selected']"
           )
           |> render() =~ d4.id

    view
    |> form("#manual-job-#{job.id} form", %{
      manual_workorder: %{dataclip_id: d2.id}
    })
    |> render_change()

    assert view
           |> element(
             "select[name='manual_workorder[dataclip_id]'] option[selected='selected']"
           )
           |> render()
  end
end
