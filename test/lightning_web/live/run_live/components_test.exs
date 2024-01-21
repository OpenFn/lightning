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

    [first_step, second_step, third_step] = attempt.steps

    project_id = workflow.project_id

    html =
      render_component(&Components.step_list_item/1,
        step: first_step,
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

    assert has_attempt_step_link?(html, workflow.project, attempt, first_step)

    html =
      render_component(&Components.step_list_item/1,
        step: second_step,
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

    assert has_attempt_step_link?(html, workflow.project, attempt, second_step)

    html =
      render_component(&Components.step_list_item/1,
        step: third_step,
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

    assert has_attempt_step_link?(html, workflow.project, attempt, third_step)

    # Rerun attempt
    last_step = List.last(attempt.steps)

    attempt2 =
      insert(:attempt,
        state: :started,
        work_order_id: attempt.work_order_id,
        dataclip: dataclip,
        starting_job: last_step.job,
        steps: attempt.steps -- [last_step]
      )

    attempt2_last_step =
      insert(:step,
        attempts: [attempt2],
        job: job_3,
        exit_reason: nil,
        finished_at: nil
      )

    first_step = hd(attempt2.steps)

    html =
      render_component(&Components.step_list_item/1,
        step: first_step,
        attempt: attempt2,
        project_id: project_id,
        can_rerun_job: true
      )

    assert html
           |> Floki.parse_fragment!()
           |> Floki.find(~s{span[id="clone_#{attempt2.id}_#{first_step.id}"]})
           |> Enum.any?()

    assert html =~ "This step was originally executed in a previous run"

    html =
      render_component(&Components.step_list_item/1,
        step: attempt2_last_step,
        attempt: attempt2,
        project_id: project_id,
        can_rerun_job: true
      )

    refute html
           |> Floki.parse_fragment!()
           |> Floki.find(~s{span[id="clone_#{attempt2.id}_#{first_step.id}"]})
           |> Enum.any?()

    refute html =~ "This step was originally executed in a previous run"
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
        steps: [
          build(:step, finished_at: DateTime.utc_now(), exit_reason: "success")
        ]
      )

    step = List.first(attempt.steps)

    project_id = step.job.workflow.project_id

    html =
      render_component(&Components.step_list_item/1,
        step: step,
        attempt: attempt,
        project_id: project_id,
        can_rerun_job: true
      )
      |> Floki.parse_fragment!()

    assert html
           |> Floki.find(~s{span[title="Rerun workflow from here"]})
           |> Enum.any?()

    html =
      render_component(&Components.step_list_item/1,
        step: step,
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

  defp has_attempt_step_link?(html, project, attempt, step) do
    html
    |> Floki.find(
      ~s{a[href='#{~p"/projects/#{project}/attempts/#{attempt}?#{%{step: step.id}}"}']}
    )
    |> Enum.any?()
  end
end
