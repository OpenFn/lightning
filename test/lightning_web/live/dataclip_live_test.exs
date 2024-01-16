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
          )
        )

      assert html =~ dataclip.id

      dataclip_text =
        element(view, "#dataclip-form_body")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.text()
        |> String.replace("&amp;quot;", "\"")

      assert dataclip_text =~ ~S("foo":"bar")

      project_unscoped = Lightning.ProjectsFixtures.project_fixture()

      error =
        live(
          conn,
          Routes.project_dataclip_show_path(
            conn,
            :show,
            project_unscoped.id,
            dataclip.id
          )
        )

      assert error ==
               {:error, {:redirect, %{flash: %{"nav" => :not_found}, to: "/"}}}
    end
  end
end
