defmodule LightningWeb.ConnectedSystemLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  describe "Index as a regular user" do
    setup :register_and_log_in_user

    test "regular user cannot access the systems page", %{conn: conn} do
      {:ok, _view, html} =
        live(conn, ~p"/settings/connected_systems")
        |> follow_redirect(conn, ~p"/projects")

      assert html =~ "No Access"
    end
  end

  describe "Index as a superuser" do
    setup :register_and_log_in_superuser

    test "superuser sees the empty state", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/settings/connected_systems")

      assert html =~ "Systems"
      assert html =~ "No systems found."
    end

    test "systems are listed with name and type", %{conn: conn} do
      system =
        insert(:connected_system, name: "National ID", slug: "national-id", type: "http")

      {:ok, view, _html} =
        live(conn, ~p"/settings/connected_systems", on_error: :raise)

      assert has_element?(
               view,
               "tr#connected-systems-table-row-#{system.id}"
             )

      assert render(view) =~ "National ID"
    end

    test "a system can be created through the modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/connected_systems")

      view
      |> form("#connected-system-form-new",
        connected_system: %{raw_name: "Southwest Health Tracker", type: "dhis2"}
      )
      |> render_submit()

      assert {:ok, system} =
               Lightning.ConnectedSystems.get_connected_system_by_slug(
                 "southwest-health-tracker"
               )

      assert system.name == "Southwest Health Tracker"
      assert system.type == "dhis2"
    end

    test "a system can be deleted", %{conn: conn} do
      system = insert(:connected_system)

      {:ok, view, _html} = live(conn, ~p"/settings/connected_systems")

      view
      |> element("#delete-connected-system-#{system.id}-modal_confirm_button")
      |> render_click()

      assert Lightning.ConnectedSystems.get_connected_system(system.id) == nil
    end
  end
end
