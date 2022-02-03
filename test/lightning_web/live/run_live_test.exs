defmodule LightningWeb.RunLiveTest do
  use LightningWeb.ConnCase

  import Phoenix.LiveViewTest
  import Lightning.InvocationFixtures

  @create_attrs %{exit_code: 42, finished_at: %{day: 2, hour: 11, minute: 49, month: 2, year: 2022}, log: [], started_at: %{day: 2, hour: 11, minute: 49, month: 2, year: 2022}}
  @update_attrs %{exit_code: 43, finished_at: %{day: 3, hour: 11, minute: 49, month: 2, year: 2022}, log: [], started_at: %{day: 3, hour: 11, minute: 49, month: 2, year: 2022}}
  @invalid_attrs %{exit_code: nil, finished_at: %{day: 30, hour: 11, minute: 49, month: 2, year: 2022}, log: [], started_at: %{day: 30, hour: 11, minute: 49, month: 2, year: 2022}}

  defp create_run(_) do
    run = run_fixture()
    %{run: run}
  end

  describe "Index" do
    setup [:create_run]

    test "lists all runs", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, Routes.run_index_path(conn, :index))

      assert html =~ "Listing Runs"
    end

    test "saves new run", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, Routes.run_index_path(conn, :index))

      assert index_live |> element("a", "New Run") |> render_click() =~
               "New Run"

      assert_patch(index_live, Routes.run_index_path(conn, :new))

      assert index_live
             |> form("#run-form", run: @invalid_attrs)
             |> render_change() =~ "is invalid"

      {:ok, _, html} =
        index_live
        |> form("#run-form", run: @create_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.run_index_path(conn, :index))

      assert html =~ "Run created successfully"
    end

    test "updates run in listing", %{conn: conn, run: run} do
      {:ok, index_live, _html} = live(conn, Routes.run_index_path(conn, :index))

      assert index_live |> element("#run-#{run.id} a", "Edit") |> render_click() =~
               "Edit Run"

      assert_patch(index_live, Routes.run_index_path(conn, :edit, run))

      assert index_live
             |> form("#run-form", run: @invalid_attrs)
             |> render_change() =~ "is invalid"

      {:ok, _, html} =
        index_live
        |> form("#run-form", run: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.run_index_path(conn, :index))

      assert html =~ "Run updated successfully"
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

    test "updates run within modal", %{conn: conn, run: run} do
      {:ok, show_live, _html} = live(conn, Routes.run_show_path(conn, :show, run))

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Run"

      assert_patch(show_live, Routes.run_show_path(conn, :edit, run))

      assert show_live
             |> form("#run-form", run: @invalid_attrs)
             |> render_change() =~ "is invalid"

      {:ok, _, html} =
        show_live
        |> form("#run-form", run: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.run_show_path(conn, :show, run))

      assert html =~ "Run updated successfully"
    end
  end
end
