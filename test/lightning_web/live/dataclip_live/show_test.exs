defmodule LightningWeb.DataclipLive.ShowTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories
  import LightningWeb.DesignSystemHelpers

  @page "#dataclip-show-page"

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  test "sends the dataclip's details, never its body", %{
    conn: conn,
    project: project
  } do
    dataclip =
      insert(:dataclip, project: project, type: :http_request, body: %{"x" => 1})

    {:ok, view, _html} =
      live(conn, ~p"/projects/#{project.id}/dataclips/#{dataclip.id}/show")

    props = page_props(view, @page)

    assert props["dataclip"] == %{
             "id" => dataclip.id,
             "type" => "http_request",
             "insertedAt" => DateTime.to_iso8601(dataclip.inserted_at),
             "updatedAt" => DateTime.to_iso8601(dataclip.updated_at),
             "wipedAt" => nil
           }

    assert props["project"]["id"] == project.id
    refute Map.has_key?(props["dataclip"], "body")

    # A patch to another of the project's dataclips shows that one.
    second = insert(:dataclip, project: project, type: :step_result)

    render_patch(
      view,
      ~p"/projects/#{project.id}/dataclips/#{second.id}/show"
    )

    assert page_props(view, @page)["dataclip"]["id"] == second.id
  end

  test "says when the dataclip was wiped", %{conn: conn, project: project} do
    wiped_at = DateTime.utc_now() |> DateTime.truncate(:second)

    dataclip =
      insert(:dataclip,
        project: project,
        body: %{"still" => "stored"},
        wiped_at: wiped_at
      )

    {:ok, view, _html} =
      live(conn, ~p"/projects/#{project.id}/dataclips/#{dataclip.id}/show")

    props = page_props(view, @page)
    assert props["dataclip"]["wipedAt"] == DateTime.to_iso8601(wiped_at)
    refute inspect(props) =~ "stored"
  end

  test "sends a dataclip from another project, or none, back to History", %{
    conn: conn,
    project: project
  } do
    other = insert(:dataclip, project: insert(:project))

    for id <- [other.id, Ecto.UUID.generate()] do
      assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
               live(conn, ~p"/projects/#{project.id}/dataclips/#{id}/show")

      assert to == ~p"/projects/#{project.id}/history"
      assert flash["error"] == "Dataclip not found"
    end
  end
end
