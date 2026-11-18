defmodule LightningWeb.AppMapTest do
  use ExUnit.Case, async: true

  alias LightningWeb.AppMap

  describe "drift between router and catalog" do
    test "every non-excluded router page has a catalog entry" do
      catalog_paths = AppMap.catalog() |> Map.keys() |> MapSet.new()

      uncovered =
        AppMap.routes()
        |> Enum.reject(&MapSet.member?(catalog_paths, &1.path))

      assert uncovered == [],
             """
             The following router page(s) have no entry in the LightningWeb.AppMap
             catalog:

             #{Enum.map_join(uncovered, "\n", &"  #{&1.path} (#{inspect(&1.module)})")}

             If it is a user-facing page, add a catalog entry (id, label, section,
             description) in lib/lightning_web/app_map.ex. If it is not — an API
             endpoint, a redirect, auth plumbing — add it to the exclusion lists
             there instead.
             """
    end

    test "every catalog entry corresponds to a live route (no stale entries)" do
      route_paths = AppMap.routes() |> Enum.map(& &1.path) |> MapSet.new()

      stale =
        AppMap.catalog()
        |> Map.keys()
        |> Enum.reject(&MapSet.member?(route_paths, &1))

      assert stale == [],
             """
             The following LightningWeb.AppMap catalog entries no longer match any
             route in the router (renamed or removed?):

             #{Enum.map_join(stale, "\n", &"  #{&1}")}

             Update or remove them in lib/lightning_web/app_map.ex.
             """
    end
  end

  describe "build/0" do
    test "entries have non-empty id, label, section, and description" do
      for page <- AppMap.build() do
        assert is_binary(page.id) and page.id != "",
               "empty id for #{page.path}"

        assert is_binary(page.label) and page.label != "",
               "empty label for #{page.path}"

        assert page.section in ["project", "user", "admin", "auth"],
               "unknown section #{inspect(page.section)} for #{page.path}"

        assert is_binary(page.description) and page.description != "",
               "empty description for #{page.path}"
      end
    end

    test "ids are unique" do
      ids = AppMap.build() |> Enum.map(& &1.id)

      assert ids == Enum.uniq(ids),
             "duplicate ids: #{inspect(ids -- Enum.uniq(ids))}"
    end

    test "includes the routes injected from config, not just router.ex" do
      # These four pages come from config/config.exs via
      # Lightning.Extensions.Routing, so they are invisible to anything that
      # parses the router file. Their presence here proves the map is built
      # from router introspection.
      paths = AppMap.build() |> Enum.map(& &1.path) |> MapSet.new()

      for path <- [
            "/projects",
            "/projects/:project_id/settings",
            "/profile",
            "/settings/users"
          ] do
        assert MapSet.member?(paths, path),
               "config-injected route #{path} missing from the app map"
      end
    end

    test "project settings entry carries the nine hash-addressed tabs" do
      settings =
        AppMap.build()
        |> Enum.find(&(&1.path == "/projects/:project_id/settings"))

      hashes = Enum.map(settings.tabs, & &1.hash)

      assert hashes == [
               "project",
               "credentials",
               "collections",
               "webhook_security",
               "collaboration",
               "security",
               "vcs",
               "data-storage",
               "history-exports"
             ]

      for tab <- settings.tabs do
        assert tab.label != "" and tab.description != "",
               "tab #{tab.hash} missing label or description"
      end
    end

    test "elements, where present, have unique kebab-case ids and non-empty text" do
      for page <- AppMap.build(), elements = Map.get(page, :elements) do
        ids = Enum.map(elements, & &1.id)

        assert ids == Enum.uniq(ids),
               "duplicate element ids on #{page.id}: #{inspect(ids -- Enum.uniq(ids))}"

        for element <- elements do
          assert element.id =~ ~r/^[a-z][a-z0-9]*(-[a-z0-9]+)*$/,
                 "element id #{inspect(element.id)} on #{page.id} is not kebab-case"

          assert is_binary(element.label) and element.label != "",
                 "empty label for element #{element.id} on #{page.id}"

          assert is_binary(element.description) and element.description != "",
                 "empty description for element #{element.id} on #{page.id}"

          assert is_nil(element.hint) or
                   (is_binary(element.hint) and element.hint != ""),
                 "hint for element #{element.id} on #{page.id} must be nil or a non-empty string"
        end
      end
    end

    test "workflow_edit carries exactly the twelve catalogued elements" do
      workflow_edit = AppMap.build() |> Enum.find(&(&1.id == "workflow_edit"))

      assert Enum.sort(Enum.map(workflow_edit.elements, & &1.id)) == [
               "adaptor-picker",
               "ai-assistant-toggle",
               "canvas-step",
               "code-panel-toggle",
               "credential-picker",
               "docs-tab",
               "open-editor",
               "run-button",
               "save-workflow",
               "settings-panel-toggle",
               "step-name",
               "version-switcher"
             ]
    end

    test "every element's requires references an existing element id on the same page" do
      for page <- AppMap.build(), elements = Map.get(page, :elements) do
        ids = MapSet.new(elements, & &1.id)

        for element <- elements, requires = element.requires do
          assert MapSet.member?(ids, requires),
                 "element #{element.id} on #{page.id} requires #{inspect(requires)}, " <>
                   "which is not an element id on that page"
        end
      end
    end

    test "requires chains contain no cycles" do
      for page <- AppMap.build(), elements = Map.get(page, :elements) do
        requires_by_id = Map.new(elements, &{&1.id, &1.requires})

        for element <- elements do
          walk_chain(element.id, requires_by_id, MapSet.new(), page.id)
        end
      end
    end

    test "resolves the LiveView module, not Phoenix.LiveView.Plug" do
      history =
        AppMap.build()
        |> Enum.find(&(&1.path == "/projects/:project_id/history"))

      assert history.module == "LightningWeb.RunLive.Index"
    end
  end

  describe "to_json/0" do
    test "round-trips through Jason" do
      pages = AppMap.to_json()

      assert {:ok, encoded} = Jason.encode(pages)
      assert {:ok, decoded} = Jason.decode(encoded)
      assert length(decoded) == length(pages)

      for page <- decoded do
        assert %{
                 "id" => _,
                 "path" => _,
                 "module" => _,
                 "label" => _,
                 "section" => _,
                 "description" => _
               } = page
      end
    end

    test "serialises elements sorted by label, omitting hint when nil" do
      {:ok, decoded} = AppMap.to_json() |> Jason.encode!() |> Jason.decode()

      workflow_edit = Enum.find(decoded, &(&1["id"] == "workflow_edit"))
      elements = workflow_edit["elements"]

      assert length(elements) == 12

      labels = Enum.map(elements, & &1["label"])
      assert labels == Enum.sort(labels)

      for element <- elements do
        assert %{"id" => _, "label" => _, "description" => _} = element

        case element do
          %{"hint" => hint} ->
            assert is_binary(hint) and hint != "",
                   "serialised hint for #{element["id"]} must be a non-empty string"

          _ ->
            :ok
        end
      end

      # hint is omitted, not null: run-button has no hint, step-name does
      run_button = Enum.find(elements, &(&1["id"] == "run-button"))
      refute Map.has_key?(run_button, "hint")

      step_name = Enum.find(elements, &(&1["id"] == "step-name"))

      assert step_name["hint"] ==
               "Select a step on the canvas to open its configuration panel first."
    end

    test "serialises requires only where set, never as null" do
      {:ok, decoded} = AppMap.to_json() |> Jason.encode!() |> Jason.decode()

      workflow_edit = Enum.find(decoded, &(&1["id"] == "workflow_edit"))
      elements = workflow_edit["elements"]

      for element <- elements do
        case element do
          %{"requires" => requires} ->
            assert is_binary(requires) and requires != "",
                   "serialised requires for #{element["id"]} must be a non-empty string"

          _ ->
            :ok
        end
      end

      # requires is omitted, not null: run-button has none, step-name does
      run_button = Enum.find(elements, &(&1["id"] == "run-button"))
      refute Map.has_key?(run_button, "requires")

      step_name = Enum.find(elements, &(&1["id"] == "step-name"))
      assert step_name["requires"] == "canvas-step"

      docs_tab = Enum.find(elements, &(&1["id"] == "docs-tab"))
      assert docs_tab["requires"] == "open-editor"
    end

    test "is deterministic and sorted by id" do
      pages = AppMap.to_json()

      assert pages == AppMap.to_json()
      assert Enum.map(pages, & &1["id"]) |> then(&(&1 == Enum.sort(&1)))
    end
  end

  describe "priv/app_map.json build artifact" do
    test "matches the current output of LightningWeb.AppMap" do
      # The committed artifact is read at runtime (Lightning.AiAssistant.AppMap)
      # and sent to the AI assistant, so it must not drift from its source.
      committed =
        :lightning
        |> Application.app_dir("priv/app_map.json")
        |> File.read!()
        |> Jason.decode!()

      assert committed == AppMap.to_json(),
             """
             priv/app_map.json is stale: it no longer matches
             LightningWeb.AppMap.to_json/0. The committed artifact is what the
             AI assistant receives at runtime, so regenerate it:

                 mix lightning.gen.app_map
             """
    end
  end

  # Follows an element's `requires` chain, failing if it revisits an id.
  defp walk_chain(nil, _requires_by_id, _visited, _page_id), do: :ok

  defp walk_chain(id, requires_by_id, visited, page_id) do
    refute MapSet.member?(visited, id),
           "requires cycle on #{page_id} involving element #{inspect(id)}"

    walk_chain(
      Map.get(requires_by_id, id),
      requires_by_id,
      MapSet.put(visited, id),
      page_id
    )
  end
end
