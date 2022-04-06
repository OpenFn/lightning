defmodule LightningWeb.DataclipLiveTest do
  use LightningWeb.ConnCase

  import Phoenix.LiveViewTest
  import Lightning.InvocationFixtures

  @create_attrs %{body: "{}", type: :http_request}
  @update_attrs %{body: "{}", type: :global}
  @invalid_attrs %{body: nil, type: nil}

  defp create_dataclip(_) do
    dataclip = dataclip_fixture()
    %{dataclip: dataclip}
  end

  describe "Index" do
    setup [:create_dataclip]

    test "lists all dataclips", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, Routes.dataclip_index_path(conn, :index))

      assert html =~ "Listing Dataclips"
    end

    test "saves new dataclip", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, Routes.dataclip_index_path(conn, :index))

      assert index_live |> element("a", "New Dataclip") |> render_click() =~
               "New Dataclip"

      assert_patch(index_live, Routes.dataclip_index_path(conn, :new))

      assert index_live
             |> form("#dataclip-form", dataclip: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        index_live
        |> form("#dataclip-form", dataclip: @create_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.dataclip_index_path(conn, :index))

      assert html =~ "Dataclip created successfully"
    end

    test "updates dataclip in listing", %{conn: conn, dataclip: dataclip} do
      {:ok, index_live, _html} = live(conn, Routes.dataclip_index_path(conn, :index))

      assert index_live
             |> element("#dataclip-#{dataclip.id} a", "Edit")
             |> render_click() =~
               "Edit Dataclip"

      assert_patch(
        index_live,
        Routes.dataclip_index_path(conn, :edit, dataclip)
      )

      assert index_live
             |> form("#dataclip-form", dataclip: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        index_live
        |> form("#dataclip-form", dataclip: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.dataclip_index_path(conn, :index))

      assert html =~ "Dataclip updated successfully"
    end

    test "deletes dataclip in listing", %{conn: conn, dataclip: dataclip} do
      {:ok, index_live, _html} = live(conn, Routes.dataclip_index_path(conn, :index))

      assert index_live
             |> element("#dataclip-#{dataclip.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#dataclip-#{dataclip.id}")
    end
  end

  describe "Show" do
    setup [:create_dataclip]

    test "displays dataclip", %{conn: conn, dataclip: dataclip} do
      {:ok, _show_live, html} = live(conn, Routes.dataclip_show_path(conn, :show, dataclip))

      assert html =~ "Show Dataclip"
    end

    test "updates dataclip within modal", %{conn: conn, dataclip: dataclip} do
      {:ok, show_live, _html} = live(conn, Routes.dataclip_show_path(conn, :show, dataclip))

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Dataclip"

      assert_patch(show_live, Routes.dataclip_show_path(conn, :edit, dataclip))

      assert show_live
             |> form("#dataclip-form", dataclip: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        show_live
        |> form("#dataclip-form", dataclip: @update_attrs)
        |> render_submit()
        |> follow_redirect(
          conn,
          Routes.dataclip_show_path(conn, :show, dataclip)
        )

      assert html =~ "Dataclip updated successfully"
    end
  end
end
