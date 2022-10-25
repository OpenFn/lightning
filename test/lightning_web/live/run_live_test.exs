defmodule LightningWeb.RunLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.InvocationFixtures

  defp create_run(%{project: project}) do
    run =
      run_fixture(
        project_id: project.id,
        log: ["First Run"]
      )

    finished_run =
      run_fixture(
        project_id: project.id,
        log: ["Finished Run"],
        started_at: DateTime.add(DateTime.utc_now(), -1, :second),
        finished_at: DateTime.add(DateTime.utc_now(), -500, :millisecond)
      )

    # Add a bunch of other runs to invoke pagination with more than one page.
    Enum.each(0..10, fn _ ->
      run_fixture(
        project_id: project.id,
        log: ["Finished Run"],
        started_at: DateTime.add(DateTime.utc_now(), -1, :second),
        finished_at: DateTime.add(DateTime.utc_now(), -500, :millisecond)
      )
      |> shift_inserted_at!(days: -1)
    end)

    %{run: run, finished_run: finished_run}
  end

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "Index" do
    setup [:create_run]

    test "lists all runs", %{conn: conn, project: project, run: run} do
      other_run = run_fixture(log: ["Other Run"])

      {:ok, view, html} =
        live(conn, Routes.project_run_index_path(conn, :index, project.id))

      assert html =~ "Runs"

      table = view |> element("section#inner_content") |> render()
      assert table =~ "run-#{run.id}"
      refute table =~ "run-#{other_run.id}"
    end

    test "deletes run in listing", %{conn: conn, run: run, project: project} do
      {:ok, index_live, _html} =
        live(conn, Routes.project_run_index_path(conn, :index, project.id))

      assert index_live
             |> element("#run-#{run.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#run-#{run.id}")
    end
  end

  describe "Show" do
    setup [:create_run]

    test "displays run", %{conn: conn, run: run, project: project} do
      {:ok, _show_live, html} =
        live(conn, Routes.project_run_index_path(conn, :show, project.id, run))

      assert html =~ "Run"
    end
  end
end
