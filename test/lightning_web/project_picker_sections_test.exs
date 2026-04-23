defmodule LightningWeb.ProjectPickerSectionsTest do
  @moduledoc """
  Safety net: asserts `project_picker_href/2` handles every first-segment
  that appears in `/projects/:project_id/*` routes. If someone adds a new
  project-scoped route and forgets to update the picker, this test fails
  with a message telling them what to change.
  """
  use ExUnit.Case, async: true

  alias LightningWeb.LayoutComponents

  # Every segment below is one the picker currently knows about — either as
  # a direct section or as an alias (e.g. "runs" -> "history"). Keep this
  # list in sync with the `project_picker_href/2` guard.
  @known_segments ~w(w history runs dataclips channels sandboxes settings jobs)

  test "project_picker_href/2 handles every project-scoped route segment" do
    # Only LiveView page routes — the picker navigates to pages, not API endpoints.
    router_segments =
      LightningWeb.Router.__routes__()
      |> Enum.filter(fn r ->
        r.plug == Phoenix.LiveView.Plug and
          String.starts_with?(r.path, "/projects/:project_id/")
      end)
      |> Enum.map(fn %{path: path} ->
        path
        |> String.replace_prefix("/projects/:project_id/", "")
        |> String.split("/")
        |> hd()
      end)
      |> MapSet.new()

    missing = MapSet.difference(router_segments, MapSet.new(@known_segments))

    assert MapSet.size(missing) == 0, """
    Project picker is missing routing entries for: #{inspect(MapSet.to_list(missing))}

    Open lib/lightning_web/components/layout_components.ex and update
    `project_picker_href/2`. Either add the segment as a known section (e.g.
    `foo`) or alias it to an existing section (e.g. match `"foo"` and return
    `"history"`). Then add it to `@known_segments` in this test.
    """
  end

  describe "project_picker_href/2" do
    test "preserves known sections" do
      for section <- ~w(w history channels sandboxes settings jobs) do
        assert LayoutComponents.project_picker_href(
                 "abc",
                 "/projects/xyz/#{section}"
               ) ==
                 "/projects/abc/#{section}"
      end
    end

    test "maps runs/:id to history" do
      assert LayoutComponents.project_picker_href(
               "abc",
               "/projects/xyz/runs/123"
             ) ==
               "/projects/abc/history"
    end

    test "maps dataclips/:id/show to history" do
      assert LayoutComponents.project_picker_href(
               "abc",
               "/projects/xyz/dataclips/123/show"
             ) ==
               "/projects/abc/history"
    end

    test "strips workflow IDs, preserving the section" do
      assert LayoutComponents.project_picker_href("abc", "/projects/xyz/w/123") ==
               "/projects/abc/w"
    end

    test "falls back to /w for paths outside the project scope" do
      for path <- [
            "/services/accounts/42",
            "/settings/users",
            "/projects",
            nil
          ] do
        assert LayoutComponents.project_picker_href("abc", path) ==
                 "/projects/abc/w"
      end
    end

    test "falls back to /w for an unknown segment" do
      assert LayoutComponents.project_picker_href(
               "abc",
               "/projects/xyz/does-not-exist"
             ) ==
               "/projects/abc/w"
    end
  end
end
