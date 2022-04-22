defmodule LightningWeb.RunLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.InvocationFixtures

  defp create_run(_) do
    run = run_fixture()
    %{run: run}
  end

  setup :register_and_log_in_user

  describe "Index" do
    setup [:create_run]

    test "lists all runs", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, Routes.run_index_path(conn, :index))

      assert html =~ "Listing Runs"

      # Temporarily check that you _can't_ create a run via the front end
      refute html =~ "New Run"
    end

    test "deletes run in listing", %{conn: conn, run: run} do
      {:ok, index_live, _html} = live(conn, Routes.run_index_path(conn, :index))

      assert index_live |> element("#run-#{run.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#run-#{run.id}")
    end
  end

  describe "Show" do
    setup [:create_run]

    test "displays run", %{conn: conn, run: run} do
      {:ok, _show_live, html} = live(conn, Routes.run_show_path(conn, :show, run))

      assert html =~ "Show Run"
    end
  end
end
