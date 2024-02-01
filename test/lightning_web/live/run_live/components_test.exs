defmodule LightningWeb.RunLive.ComponentsTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias LightningWeb.RunLive.Components
  alias LightningWeb.RunLive.Index

  import Lightning.Factories

  test "is_checked returns true if a specified filter is part of a filter changeset" do
    changeset =
      Index.filters_changeset(%{
        "body" => "true",
        "date_after" => "2023-11-02T13:02",
        "date_before" => "",
        "log" => "true",
        "search_term" => "",
        "success" => "true",
        "wo_date_after" => "",
        "wo_date_before" => "",
        "workflow_id" => ""
      })

    assert Index.checked?(changeset, :body) == true
    assert Index.checked?(changeset, :success) == true
    assert Index.checked?(changeset, :failed) == false

    unchecking_changeset =
      Index.filters_changeset(%{
        "body" => "true",
        "date_after" => "2023-11-02T13:02",
        "date_before" => "",
        "log" => "true",
        "search_term" => "",
        "success" => "false",
        "wo_date_after" => "",
        "wo_date_before" => "",
        "workflow_id" => ""
      })

    assert Index.checked?(unchecking_changeset, :search_term) == false
    assert Index.checked?(unchecking_changeset, :body) == true
    assert Index.checked?(unchecking_changeset, :success) == false
  end

  test "step_list_item component" do
    %{triggers: [trigger], jobs: jobs} =
      workflow = insert(:complex_workflow)

    [job_1, job_2, job_3 | _] = jobs

    dataclip = insert(:dataclip)
    output_dataclip = insert(:dataclip)

    %{runs: [run]} =
      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip,
        runs: [
          %{
            state: :failed,
            dataclip: dataclip,
            starting_trigger: trigger,
            steps: [
              insert(:step,
                job: job_1,
                input_dataclip: dataclip,
                output_dataclip: output_dataclip,
                exit_reason: nil
              ),
              insert(:step,
                job: job_2,
                input_dataclip: output_dataclip,
                exit_reason: "success"
              ),
              insert(:step,
                job: job_3,
                exit_reason: "fail",
                finished_at: build(:timestamp)
              )
            ]
          }
        ]
      )

    [first_step, second_step, third_step] = run.steps

    project_id = workflow.project_id

    html =
      render_component(&Components.step_list_item/1,
        step: first_step,
        run: run,
        project_id: project_id,
        can_rerun_job: true,
        can_edit_data_retention: true
      )
      |> Floki.parse_fragment!()

    assert html
           |> Floki.find(
             ~s{svg[class="mr-1.5 h-5 w-5 flex-shrink-0 inline text-gray-400"]}
           )
           |> Enum.any?()

    assert has_run_step_link?(html, workflow.project, run, first_step)

    html =
      render_component(&Components.step_list_item/1,
        step: second_step,
        run: run,
        project_id: project_id,
        can_rerun_job: true,
        can_edit_data_retention: true
      )
      |> Floki.parse_fragment!()

    assert html
           |> Floki.find(
             ~s{svg[class="mr-1.5 h-5 w-5 flex-shrink-0 inline text-green-500"]}
           )
           |> Enum.any?()

    assert has_run_step_link?(html, workflow.project, run, second_step)

    html =
      render_component(&Components.step_list_item/1,
        step: third_step,
        run: run,
        project_id: project_id,
        can_rerun_job: true,
        can_edit_data_retention: true
      )
      |> Floki.parse_fragment!()

    assert html
           |> Floki.find(
             ~s{svg[class="mr-1.5 h-5 w-5 flex-shrink-0 inline text-red-500"]}
           )
           |> Enum.any?()

    assert has_run_step_link?(html, workflow.project, run, third_step)

    # Rerun run
    last_step = List.last(run.steps)

    run2 =
      insert(:run,
        state: :started,
        work_order_id: run.work_order_id,
        dataclip: dataclip,
        starting_job: last_step.job,
        steps: run.steps -- [last_step]
      )

    run2_last_step =
      insert(:step,
        runs: [run2],
        job: job_3,
        exit_reason: nil,
        finished_at: nil
      )

    first_step = hd(run2.steps)

    html =
      render_component(&Components.step_list_item/1,
        step: first_step,
        run: run2,
        project_id: project_id,
        can_rerun_job: true,
        can_edit_data_retention: true
      )

    assert html
           |> Floki.parse_fragment!()
           |> Floki.find(~s{span[id="clone_#{run2.id}_#{first_step.id}"]})
           |> Enum.any?()

    assert html =~ "This step was originally executed in a previous run"

    html =
      render_component(&Components.step_list_item/1,
        step: run2_last_step,
        run: run2,
        project_id: project_id,
        can_rerun_job: true,
        can_edit_data_retention: true
      )

    refute html
           |> Floki.parse_fragment!()
           |> Floki.find(~s{span[id="clone_#{run2.id}_#{first_step.id}"]})
           |> Enum.any?()

    refute html =~ "This step was originally executed in a previous run"
  end

  test "no rerun button is displayed when user can't rerun a job" do
    %{triggers: [trigger]} = workflow = insert(:simple_workflow)

    dataclip = insert(:dataclip)

    %{runs: [run]} =
      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip,
        state: :failed
      )
      |> with_run(
        state: :failed,
        dataclip: dataclip,
        starting_trigger: trigger,
        finished_at: build(:timestamp),
        steps: [
          build(:step, finished_at: DateTime.utc_now(), exit_reason: "success")
        ]
      )

    step = List.first(run.steps)

    project_id = step.job.workflow.project_id

    html =
      render_component(&Components.step_list_item/1,
        step: step,
        run: run,
        project_id: project_id,
        can_rerun_job: true,
        can_edit_data_retention: true
      )
      |> Floki.parse_fragment!()

    assert html
           |> Floki.find(~s{span[title="Rerun workflow from here"]})
           |> Enum.any?()

    html =
      render_component(&Components.step_list_item/1,
        step: step,
        run: run,
        project_id: project_id,
        can_rerun_job: false,
        can_edit_data_retention: true
      )
      |> Floki.parse_fragment!()

    refute html
           |> Floki.find(~s{span[title="Rerun workflow from here"]})
           |> Enum.any?()
  end

  test "rerun button is disabled when the step dataclip is not saved" do
    %{triggers: [trigger], jobs: [job | _rest]} =
      workflow = insert(:simple_workflow)

    dataclip = insert(:dataclip, body: nil, wiped_at: DateTime.utc_now())

    %{runs: [run]} =
      insert(:workorder,
        workflow: workflow,
        trigger: trigger,
        dataclip: dataclip,
        state: :failed
      )
      |> with_run(
        state: :failed,
        dataclip: dataclip,
        starting_trigger: trigger,
        finished_at: build(:timestamp),
        steps: [
          build(:step,
            finished_at: DateTime.utc_now(),
            job: job,
            exit_reason: "success",
            input_dataclip: nil,
            output_dataclip: nil
          )
        ]
      )

    step = List.first(run.steps)

    project_id = workflow.project_id

    html =
      render_component(&Components.step_list_item/1,
        step: step,
        run: run,
        project_id: project_id,
        can_rerun_job: true,
        can_edit_data_retention: true
      )

    parsed_html = Floki.parse_fragment!(html)

    assert parsed_html
           |> Floki.find(~s{span[id=#{step.id}]})
           |> Enum.any?(),
           "rerun button exists"

    refute parsed_html
           |> Floki.find(~s{span[id=#{step.id}][phx-click="rerun"]})
           |> Enum.any?(),
           "rerun button does not have the rerun phx event"

    assert html =~
             "This work order cannot be rerun since no input data has been stored",
           "Tooltip is displayed"

    assert html =~ "Go to retention settings", "User sees link to go to settings"
    refute html =~ "contact one of your account administrators"

    html =
      render_component(&Components.step_list_item/1,
        step: step,
        run: run,
        project_id: project_id,
        can_rerun_job: true,
        can_edit_data_retention: false
      )

    parsed_html = Floki.parse_fragment!(html)

    assert parsed_html
           |> Floki.find(~s{span[id=#{step.id}]})
           |> Enum.any?(),
           "rerun button exists"

    refute parsed_html
           |> Floki.find(~s{span[id=#{step.id}][phx-click="rerun"]})
           |> Enum.any?(),
           "rerun button does not have the rerun phx event"

    assert html =~
             "This work order cannot be rerun since no input data has been stored",
           "Tooltip is displayed"

    refute html =~ "Go to retention settings",
           "User does not see link to go to settings"

    assert html =~ "contact one of your account administrators"
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

  defp has_run_step_link?(html, project, run, step) do
    html
    |> Floki.find(
      ~s{a[href='#{~p"/projects/#{project}/runs/#{run}?#{%{step: step.id}}"}']}
    )
    |> Enum.any?()
  end
end
