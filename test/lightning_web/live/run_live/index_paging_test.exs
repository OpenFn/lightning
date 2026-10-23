defmodule LightningWeb.RunLive.IndexPagingTest do
  # History on a busy project: a new work order (a cron trigger, every minute)
  # mustn't land on a later page or grow the page size the page links are
  # counted from.
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  alias Lightning.WorkOrders.Events

  setup :register_and_log_in_superuser
  setup :create_project_for_current_user
  setup :stub_usage_limiter_ok

  @page "#history-work-orders-page"

  setup %{project: project} do
    %{triggers: [trigger]} =
      workflow = insert(:simple_workflow, project: project) |> with_snapshot()

    now = DateTime.utc_now()

    # 25 work orders: three pages of ten, newest first.
    for i <- 1..25 do
      work_order(workflow, trigger, DateTime.add(now, -i * 60))
    end

    %{workflow: workflow, trigger: trigger}
  end

  defp work_order(workflow, trigger, last_activity) do
    insert(:workorder,
      workflow: workflow,
      trigger: trigger,
      dataclip: insert(:dataclip, project: workflow.project),
      state: :success,
      last_activity: last_activity
    )
  end

  defp new_work_order(view, workflow, trigger) do
    work_order = work_order(workflow, trigger, DateTime.utc_now())

    send(view.pid, %Events.WorkOrderCreated{
      work_order: work_order,
      project_id: workflow.project_id
    })

    work_order
  end

  defp props(view), do: page_props(view, @page)
  defp ids(view), do: Enum.map(props(view)["rows"], & &1["id"])

  test "a new work order keeps the page size the page links are counted from",
       %{conn: conn, project: project, workflow: workflow, trigger: trigger} do
    {:ok, view, _html} = live_async(conn, ~p"/projects/#{project}/history")

    assert %{"size" => 10, "totalEntries" => 25} = props(view)["page"]

    new_work_order(view, workflow, trigger)

    # Pagination.tsx counts pages as ceil(totalEntries / size), and the
    # server pages by 10: a size of 11 links 3 pages where there are 3, but
    # after a few minutes it links fewer pages than exist.
    assert %{"size" => 10, "totalEntries" => 26} = props(view)["page"]
  end

  test "a new work order isn't added to a later page",
       %{conn: conn, project: project, workflow: workflow, trigger: trigger} do
    {:ok, view, _html} =
      live_async(conn, ~p"/projects/#{project}/history?page=2")

    assert length(ids(view)) == 10

    created = new_work_order(view, workflow, trigger)

    refute created.id in ids(view)
  end

  test "the next page doesn't repeat rows the page already showed",
       %{conn: conn, project: project, workflow: workflow, trigger: trigger} do
    {:ok, view, _html} = live_async(conn, ~p"/projects/#{project}/history")

    new_work_order(view, workflow, trigger)
    seen = ids(view)

    render_patch(view, ~p"/projects/#{project}/history?page=2")
    render_async(view)

    assert MapSet.disjoint?(MapSet.new(seen), MapSet.new(ids(view)))
  end
end
