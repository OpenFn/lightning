defmodule LightningWeb.DataclipLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  defp create_dataclip(%{project: project}) do
    %{dataclip: insert(:dataclip, body: %{foo: "bar"}, project: project)}
  end

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "Show" do
    setup [:create_dataclip]

    test "displays basic dataclip information on show page", %{
      conn: conn,
      dataclip: dataclip,
      project: project_scoped
    } do
      {:ok, _view, html} =
        live(
          conn,
          Routes.project_dataclip_show_path(
            conn,
            :show,
            project_scoped.id,
            dataclip.id
          ),
          on_error: :raise
        )

      # Check page title appears
      assert html =~ "Dataclip"

      # Check dataclip ID appears in the metadata section
      assert html =~ dataclip.id

      # Check "Dataclip Details" section header appears
      assert html =~ "Dataclip Details"

      # Check metadata fields are present
      assert html =~ "ID"
      assert html =~ "Type"
      assert html =~ "Created"
      assert html =~ "Updated"

      # Check dataclip viewer component is rendered (not wiped message)
      assert html =~ "dataclip-viewer-#{dataclip.id}"
      refute html =~ "No Data Available"
      refute html =~ "wiped in accordance"
    end

    test "no access to project on show", %{
      conn: conn,
      dataclip: dataclip,
      project: project_scoped
    } do
      {:ok, _view, html} =
        live(
          conn,
          Routes.project_dataclip_show_path(
            conn,
            :show,
            project_scoped.id,
            dataclip.id
          ),
          on_error: :raise
        )

      assert html =~ dataclip.id

      project_unscoped = Lightning.ProjectsFixtures.project_fixture()

      error =
        live(
          conn,
          Routes.project_dataclip_show_path(
            conn,
            :show,
            project_unscoped.id,
            dataclip.id
          ),
          on_error: :raise
        )

      assert error ==
               {:error,
                {:redirect, %{flash: %{"nav" => :not_found}, to: "/projects"}}}
    end

    test "cannot view a dataclip from another project via an accessible project",
         %{conn: conn, project: project} do
      other_project = insert(:project)

      other_dataclip =
        insert(:dataclip, body: %{secret: "from B"}, project: other_project)

      assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
               live(
                 conn,
                 Routes.project_dataclip_show_path(
                   conn,
                   :show,
                   project.id,
                   other_dataclip.id
                 )
               )

      assert to == "/projects/#{project.id}/history"
      assert flash["error"] == "Dataclip not found"
    end
  end
end
