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
      {:ok, view, html} =
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
      dataclip_id_short = String.slice(dataclip.id, 0..7)
      assert html =~ "Dataclip #{dataclip_id_short}"

      # Check dataclip ID appears in the metadata section
      assert html =~ dataclip.id

      # Check "Dataclip Details" section header appears
      assert html =~ "Dataclip Details"

      # Check metadata fields are present
      assert html =~ "ID"
      assert html =~ "Type"
      assert html =~ "Created"
      assert html =~ "Updated"

      # Check copy button appears (since dataclip is not wiped)
      assert html =~ "Click to copy JSON body"
      assert html =~ "copy-dataclip-#{dataclip.id}"

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
      {:ok, view, html} =
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
  end
end
