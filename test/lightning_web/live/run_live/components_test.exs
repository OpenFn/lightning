defmodule LightningWeb.RunLive.ComponentsTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias LightningWeb.RunLive.Components
  import Lightning.InvocationFixtures

  import Lightning.Factories

  test "run_list_item component" do
    reason = insert(:reason, type: :webhook)

    attempt =
      insert(:attempt,
        work_order: build(:workorder, reason: reason),
        runs: [
          build(:run),
          build(:run, finished_at: DateTime.utc_now(), exit_code: 0),
          build(:run, finished_at: DateTime.utc_now())
        ],
        reason: reason
      )

    first_run = attempt.runs |> List.first()
    second_run = attempt.runs |> Enum.at(1)
    third_run = attempt.runs |> List.last()

    project_id = first_run.job.workflow.project_id

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
             ~s{svg[class="mr-1.5 h-5 w-5 flex-shrink-0 text-gray-500"]}
           )
           |> Enum.any?()

    assert html
           |> Floki.find(
             ~s{a[href="#{LightningWeb.RouteHelpers.show_run_url(project_id, first_run.id)}"]}
           )
           |> Enum.any?()

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
             ~s{svg[class="mr-1.5 h-5 w-5 flex-shrink-0 text-green-500"]}
           )
           |> Enum.any?()

    assert html
           |> Floki.find(
             ~s{a[href="#{LightningWeb.RouteHelpers.show_run_url(project_id, second_run.id)}"]}
           )
           |> Enum.any?()

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
             ~s{svg[class="mr-1.5 h-5 w-5 flex-shrink-0 text-red-500"]}
           )
           |> Enum.any?()

    assert html
           |> Floki.find(
             ~s{a[href="#{LightningWeb.RouteHelpers.show_run_url(project_id, third_run.id)}"]}
           )
           |> Enum.any?()
  end

  test "no rerun button is displayed when user can't rerun a job" do
    reason = insert(:reason, type: :webhook)

    attempt =
      build(:attempt,
        work_order: build(:workorder, reason: reason),
        runs: [
          build(:run),
          build(:run, finished_at: DateTime.utc_now(), exit_code: 0),
          build(:run, finished_at: DateTime.utc_now())
        ],
        reason: reason
      )
      |> insert()

    run = attempt.runs |> List.first()

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

  test "log_view component" do
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

      run = run_fixture(started_at: started_at, finished_at: finished_at)

      html =
        render_component(&Components.run_details/1, run: run)
        |> Floki.parse_fragment!()

      assert html
             |> Floki.find("div#finished-at-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~
               Calendar.strftime(finished_at, "%c")

      assert html
             |> Floki.find("div#ran-for-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~
               "24000 ms"

      assert html
             |> Floki.find("div#exit-code-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~
               "?"
    end

    test "with pending run" do
      now = Timex.now()

      started_at = now |> Timex.shift(seconds: -25)
      run = run_fixture(started_at: started_at)

      html =
        render_component(&Components.run_details/1, run: run)
        |> Floki.parse_fragment!()

      assert html
             |> Floki.find("div#finished-at-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~ "Running..."

      assert html
             |> Floki.find("div#ran-for-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~
               ~r/25\d\d\d ms/

      assert html
             |> Floki.find("div#exit-code-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~
               "?"
    end

    test "with unstarted run" do
      run = run_fixture()

      html =
        render_component(&Components.run_details/1, run: run)
        |> Floki.parse_fragment!()

      assert html
             |> Floki.find("div#finished-at-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~ "Not started."

      assert html
             |> Floki.find("div#ran-for-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~ "Not started."

      assert html
             |> Floki.find("div#exit-code-#{run.id} > div:nth-child(2)")
             |> Floki.text() =~
               "?"
    end
  end
end
