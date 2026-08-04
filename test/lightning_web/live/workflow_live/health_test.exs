defmodule LightningWeb.WorkflowLive.HealthTest do
  use LightningWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest
  import Lightning.Factories
  import Lightning.WorkflowLive.Helpers

  setup :register_and_log_in_user
  setup :create_project_for_current_user
  setup :stub_usage_limiter_ok
  setup :verify_on_exit!

  setup %{project: project} do
    workflow = insert(:workflow, project: project)
    trigger = insert(:trigger, workflow: workflow, type: :webhook)
    dataclip = insert(:dataclip, project: project)
    job = insert(:job, workflow: workflow, name: "transform")

    %{
      workflow: workflow,
      trigger: trigger,
      dataclip: dataclip,
      job: job
    }
  end

  test "renders the health screen for a workflow", ctx do
    %{conn: conn, project: project, workflow: workflow} = ctx

    {:ok, _view, html} =
      live(conn, ~p"/projects/#{project}/w/#{workflow}/health")

    assert html =~ workflow.name
    assert html =~ "Last 24 hours"
    assert html =~ "What is real on this screen"
  end

  test "passes computed metrics to the React island", ctx do
    %{conn: conn, project: project, workflow: workflow} = ctx

    insert_failed_run(ctx)

    {:ok, _view, html} =
      live(conn, ~p"/projects/#{project}/w/#{workflow}/health")

    # Props reach React as JSON in a script tag, so the numbers are visible in
    # the rendered markup even though the charts themselves are client-side.
    assert html =~ ~s("success_rate":0.0)
    assert html =~ ~s("error_type":"RuntimeError")
    assert html =~ ~s("job":"transform")
  end

  test "switching the window reloads the metrics", ctx do
    %{conn: conn, project: project, workflow: workflow} = ctx

    # Old enough to be outside 24 hours but inside 30 days.
    insert_failed_run(ctx, DateTime.add(DateTime.utc_now(), -3, :day))

    {:ok, view, html} =
      live(conn, ~p"/projects/#{project}/w/#{workflow}/health")

    assert html =~ ~s("total":0)

    html =
      view
      |> element(~s(a[href$="health?window=30d"]))
      |> render_click()

    assert html =~ ~s("total":1)
    assert html =~ "Last 30 days"
  end

  test "falls back to the default window for an unknown value", ctx do
    %{conn: conn, project: project, workflow: workflow} = ctx

    {:ok, _view, html} =
      live(conn, ~p"/projects/#{project}/w/#{workflow}/health?window=nonsense")

    assert html =~ "Last 24 hours"
  end

  test "redirects when the workflow is not in the project", ctx do
    %{conn: conn, project: project} = ctx
    other_workflow = insert(:workflow)

    assert {:error, {:redirect, %{to: to, flash: flash}}} =
             live(conn, ~p"/projects/#{project}/w/#{other_workflow}/health")

    assert to == ~p"/projects/#{project}/w"
    assert flash["error"] == "Workflow not found"
  end

  defp insert_failed_run(ctx, inserted_at \\ nil) do
    inserted_at = inserted_at || DateTime.add(DateTime.utc_now(), -1, :hour)

    work_order =
      insert(:workorder,
        workflow: ctx.workflow,
        trigger: ctx.trigger,
        dataclip: ctx.dataclip,
        inserted_at: inserted_at,
        updated_at: inserted_at
      )

    insert(:run,
      work_order: work_order,
      dataclip: ctx.dataclip,
      starting_trigger: ctx.trigger,
      state: :failed,
      started_at: inserted_at,
      finished_at: DateTime.add(inserted_at, 2, :second),
      inserted_at: inserted_at,
      steps: [
        build(:step,
          job: ctx.job,
          exit_reason: "fail",
          error_type: "RuntimeError",
          started_at: inserted_at,
          finished_at: inserted_at,
          inserted_at: inserted_at
        )
      ]
    )
  end
end
