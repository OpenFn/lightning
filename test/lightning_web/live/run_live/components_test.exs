defmodule LightningWeb.RunLive.ComponentsTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias LightningWeb.RunLive.Components

  import Lightning.Factories

  describe "RunViewer" do
    test "output messages" do
      assert render_component(
               &LightningWeb.RunLive.Components.run_viewer/1,
               run:
                 insert(:run, exit_reason: "fail", output_dataclip_id: nil)
                 |> Lightning.Repo.preload(:log_lines)
                 |> Lightning.Repo.preload(:attempts),
               project_id: "4adf2644-ed4e-4f97-a24c-ab35b3cb1efa"
             ) =~
               "Certain errors are severe enough that the worker"

      assert render_component(
               &LightningWeb.RunLive.Components.run_viewer/1,
               run:
                 insert(:run, output_dataclip_id: nil)
                 |> Lightning.Repo.preload(:log_lines)
                 |> Lightning.Repo.preload(:attempts),
               project_id: "4adf2644-ed4e-4f97-a24c-ab35b3cb1efa"
             ) =~
               "This run has not yet finished."

      assert render_component(&LightningWeb.RunLive.Components.run_viewer/1,
               run:
                 insert(:run, exit_reason: "success", output_dataclip_id: nil)
                 |> Lightning.Repo.preload(:log_lines)
                 |> Lightning.Repo.preload(:attempts),
               project_id: "4adf2644-ed4e-4f97-a24c-ab35b3cb1efa"
             ) =~
               "There is no output for this run"

      run =
        insert(:run,
          exit_reason: "success",
          output_dataclip:
            build(:dataclip,
              type: :run_result,
              body: %{name: "dataclip_body"}
            )
        )

      assert render_component(&LightningWeb.RunLive.Components.run_viewer/1,
               run:
                 run
                 |> Lightning.Repo.preload(:log_lines)
                 |> Lightning.Repo.preload(:attempts),
               project_id: "4adf2644-ed4e-4f97-a24c-ab35b3cb1efa"
             ) =~
               "dataclip_body"
    end
  end

  test "run_list_item component" do
    %{triggers: [trigger], jobs: jobs} =
      workflow = insert(:complex_workflow)

    [job_1, job_2, job_3 | _] = jobs

    dataclip = insert(:dataclip)
    output_dataclip = insert(:dataclip)

    %{attempts: [attempt]} =
      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip,
        attempts: [
          %{
            state: :failed,
            dataclip: dataclip,
            starting_trigger: trigger,
            runs: [
              insert(:run,
                job: job_1,
                input_dataclip: dataclip,
                output_dataclip: output_dataclip,
                exit_reason: nil
              ),
              insert(:run,
                job: job_2,
                input_dataclip: output_dataclip,
                exit_reason: "success"
              ),
              insert(:run,
                job: job_3,
                exit_reason: "fail",
                finished_at: build(:timestamp)
              )
            ]
          }
        ]
      )

    [first_run, second_run, third_run] = attempt.runs

    project_id = workflow.project_id

    html =
      render_component(&Components.run_list_item/1,
        run: first_run,
        attempt: attempt,
        project_id: project_id,
        can_rerun_job: true
      )
      |> Floki.parse_fragment!()

    assert html
           |> Floki.find(
             ~s{svg[class="mr-1.5 h-5 w-5 flex-shrink-0 inline text-gray-400"]}
           )
           |> Enum.any?()

    assert has_attempt_run_link?(html, workflow.project, attempt, first_run)

    html =
      render_component(&Components.run_list_item/1,
        run: second_run,
        attempt: attempt,
        project_id: project_id,
        can_rerun_job: true
      )
      |> Floki.parse_fragment!()

    assert html
           |> Floki.find(
             ~s{svg[class="mr-1.5 h-5 w-5 flex-shrink-0 inline text-green-500"]}
           )
           |> Enum.any?()

    assert has_attempt_run_link?(html, workflow.project, attempt, second_run)

    html =
      render_component(&Components.run_list_item/1,
        run: third_run,
        attempt: attempt,
        project_id: project_id,
        can_rerun_job: true
      )
      |> Floki.parse_fragment!()

    assert html
           |> Floki.find(
             ~s{svg[class="mr-1.5 h-5 w-5 flex-shrink-0 inline text-red-500"]}
           )
           |> Enum.any?()

    assert has_attempt_run_link?(html, workflow.project, attempt, third_run)

    # Rerun attempt
    last_run = List.last(attempt.runs)

    attempt2 =
      insert(:attempt,
        state: :started,
        work_order_id: attempt.work_order_id,
        dataclip: dataclip,
        starting_job: last_run.job,
        runs: attempt.runs -- [last_run]
      )

    attempt2_last_run =
      insert(:run,
        attempts: [attempt2],
        job: job_3,
        exit_reason: nil,
        finished_at: nil
      )

    first_run = hd(attempt2.runs)

    html =
      render_component(&Components.run_list_item/1,
        run: first_run,
        attempt: attempt2,
        project_id: project_id,
        can_rerun_job: true
      )

    assert html
           |> Floki.parse_fragment!()
           |> Floki.find(~s{span[id="clone_#{attempt2.id}_#{first_run.id}"]})
           |> Enum.any?()

    assert html =~ "This run was originally executed in a previous attempt"

    html =
      render_component(&Components.run_list_item/1,
        run: attempt2_last_run,
        attempt: attempt2,
        project_id: project_id,
        can_rerun_job: true
      )

    refute html
           |> Floki.parse_fragment!()
           |> Floki.find(~s{span[id="clone_#{attempt2.id}_#{first_run.id}"]})
           |> Enum.any?()

    refute html =~ "This run was originally executed in a previous attempt"
  end

  test "no rerun button is displayed when user can't rerun a job" do
    %{triggers: [trigger]} = workflow = insert(:simple_workflow)

    dataclip = insert(:dataclip)

    %{attempts: [attempt]} =
      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip,
        state: :failed
      )
      |> with_attempt(
        state: :failed,
        dataclip: dataclip,
        starting_trigger: trigger,
        finished_at: build(:timestamp),
        runs: [
          build(:run, finished_at: DateTime.utc_now(), exit_reason: "success")
        ]
      )

    run = List.first(attempt.runs)

    project_id = run.job.workflow.project_id

    html =
      render_component(&Components.run_list_item/1,
        run: run,
        attempt: attempt,
        project_id: project_id,
        can_rerun_job: true
      )
      |> Floki.parse_fragment!()

    assert html
           |> Floki.find(~s{span[title="Rerun workflow from here"]})
           |> Enum.any?()

    html =
      render_component(&Components.run_list_item/1,
        run: run,
        attempt: attempt,
        project_id: project_id,
        can_rerun_job: false
      )
      |> Floki.parse_fragment!()

    refute html
           |> Floki.find(~s{span[title="Rerun workflow from here"]})
           |> Enum.any?()
  end

  describe "log_view component" do
    test "with no log lines" do
      html =
        render_component(&Components.log_view/1, log: [])
        |> Floki.parse_fragment!()

      assert html |> Floki.find("div[data-line-number]") |> length() == 0
    end

    test "with log lines" do
      log_lines = ["First line", "Second line"]

      html =
        render_component(&Components.log_view/1, log: log_lines)
        |> Floki.parse_fragment!()

      assert html |> Floki.find("div[data-line-number]") |> length() ==
               length(log_lines)

      # Check that the log lines are present.
      # Replace the resulting utf-8 &nbsp; back into a regular space.
      assert log_lines_from_html(html) == log_lines |> Enum.join("\n")
    end
  end

  defp log_lines_from_html(html) do
    html
    |> Floki.find("div[data-log-line]")
    |> Floki.text(sep: "\n")
    |> String.replace(<<160::utf8>>, " ")
  end

  describe "run_details component" do
    test "with finished run" do
      now = Timex.now()

      started_at = now |> Timex.shift(seconds: -25)
      finished_at = now |> Timex.shift(seconds: -1)

      run =
        insert(:run,
          started_at: started_at,
          finished_at: finished_at,
          exit_reason: "success"
        )

      html =
        render_component(&Components.run_details/1,
          run: run |> Lightning.Repo.preload(:attempts),
          project_id: "4adf2644-ed4e-4f97-a24c-ab35b3cb1efa"
        )
        |> Floki.parse_fragment!()

      assert html
             |> Floki.find("div#finished-at-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~
               Calendar.strftime(finished_at, "%c")

      assert html
             |> Floki.find("div#ran-for-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~
               "24000 ms"

      div =
        html
        |> Floki.find("div#exit-reason-#{run.id} > div:nth-child(2)")
        |> Floki.text()

      assert div =~ "Success"

      # We don't show error_type (with a " : ") on success.
      refute div =~ " : "
    end

    test "with pending run" do
      now = Timex.now()

      started_at = now |> Timex.shift(seconds: -25)
      run = insert(:run, started_at: started_at)

      html =
        render_component(&Components.run_details/1,
          run: run |> Lightning.Repo.preload(:attempts),
          project_id: "4adf2644-ed4e-4f97-a24c-ab35b3cb1efa"
        )
        |> Floki.parse_fragment!()

      assert html
             |> Floki.find("div#finished-at-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~ "n/a"

      assert html
             |> Floki.find("div#ran-for-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~ "n/a"

      # TODO: add a timer that counts up from run.started_at
      #  ~r/25\d\d\d ms/

      assert html
             |> Floki.find("div#exit-reason-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~
               "Running"
    end

    test "with failed run also shows error type" do
      now = Timex.now()

      started_at = now |> Timex.shift(seconds: -25)

      run =
        insert(:run,
          started_at: started_at,
          finished_at: started_at,
          exit_reason: "fail",
          error_type: "JobError"
        )

      html =
        render_component(&Components.run_details/1,
          run: run |> Lightning.Repo.preload(:attempts),
          project_id: "4adf2644-ed4e-4f97-a24c-ab35b3cb1efa"
        )
        |> Floki.parse_fragment!()

      div =
        html
        |> Floki.find("div#exit-reason-#{run.id} > div:nth-child(2)")
        |> Floki.text()

      assert div =~ "Fail"
      assert div =~ "JobError"
    end

    test "with lost run" do
      now = Timex.now()

      started_at = now |> Timex.shift(minutes: -25)
      run = insert(:run, started_at: started_at, exit_reason: "lost")

      html =
        render_component(&Components.run_details/1,
          run: run |> Lightning.Repo.preload(:attempts),
          project_id: "4adf2644-ed4e-4f97-a24c-ab35b3cb1efa"
        )
        |> Floki.parse_fragment!()

      assert html
             |> Floki.find("div#finished-at-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~ "n/a"

      assert html
             |> Floki.find("div#ran-for-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~ "n/a"

      assert html
             |> Floki.find("div#exit-reason-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~
               "Lost"
    end

    test "with unstarted run" do
      run = insert(:run)

      html =
        render_component(&Components.run_details/1,
          run: run |> Lightning.Repo.preload(:attempts),
          project_id: "4adf2644-ed4e-4f97-a24c-ab35b3cb1efa"
        )
        |> Floki.parse_fragment!()

      assert html
             |> Floki.find("div#finished-at-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~ "Not started."

      assert html
             |> Floki.find("div#ran-for-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~ "Not started."

      assert html
             |> Floki.find("div#exit-reason-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~
               "Running"
    end
  end

  defp has_attempt_run_link?(html, project, attempt, run) do
    html
    |> Floki.find(
      ~s{a[href='#{~p"/projects/#{project}/attempts/#{attempt}?#{%{r: run.id}}"}']}
    )
    |> Enum.any?()
  end
end
