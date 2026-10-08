defmodule LightningWeb.Components.UI.TabsTest do
  @moduledoc false
  use LightningWeb.ConnCase

  import Phoenix.LiveViewTest

  alias LightningWeb.Components.UI.Tabs

  defp render_tabs(assigns) do
    tabs =
      for {id, label} <- [{"first", "First"}, {"second", "Second"}] do
        %{id: id, patch: "/#{id}", inner_block: fn _, _ -> label end}
      end

    %{id: "test-tabs", active: "first", tab: tabs}
    |> Map.merge(assigns)
    |> then(fn assigns -> render_component(&Tabs.tabs/1, assigns) end)
    |> Floki.parse_fragment!()
  end

  defp render_hash_tabs(assigns) do
    tabs = [
      %{hash: "log", icon: "hero-key", inner_block: fn _, _ -> "Log" end},
      %{
        hash: "input",
        disabled: true,
        disabled_reason: "Pick a step",
        inner_block: fn _, _ -> "Input" end
      }
    ]

    panels = [
      %{hash: "log", class: "flex h-full", inner_block: fn _, _ -> "logs" end},
      %{hash: "input", inner_block: fn _, _ -> "input" end}
    ]

    %{id: "hash-tabs", default_hash: "log", tab: tabs, panel: panels}
    |> Map.merge(assigns)
    |> then(fn assigns -> render_component(&Tabs.tabs/1, assigns) end)
    |> Floki.parse_fragment!()
  end

  describe "tabs/1 in patch mode" do
    test "renders a nav with the id and one link per tab" do
      parsed = render_tabs(%{id: "my-tabs"})

      assert [nav] = Floki.find(parsed, "nav#my-tabs")
      assert Floki.attribute(nav, "aria-label") == ["Tabs"]

      links = Floki.find(nav, "a.ui-tab")

      assert links |> Enum.map(&Floki.text/1) |> Enum.map(&String.trim/1) ==
               ["First", "Second"]

      assert Enum.flat_map(links, &Floki.attribute(&1, "href")) ==
               ["/first", "/second"]
    end

    test "marks only the active tab with aria-current" do
      parsed = render_tabs(%{active: "second"})

      [first, second] = Floki.find(parsed, "a")

      assert Floki.attribute(first, "aria-current") == []
      assert Floki.attribute(second, "aria-current") == ["page"]
    end

    test "no tab is current when active matches none" do
      parsed = render_tabs(%{active: "nope"})

      assert Floki.find(parsed, "a[aria-current]") == []
    end

    test "renders the icon before the label" do
      tabs = [
        %{
          id: "first",
          patch: "/first",
          icon: "hero-key",
          inner_block: fn _, _ -> "First" end
        }
      ]

      parsed = render_tabs(%{tab: tabs})

      assert [{"a", _, [{"span", attrs, _} | _]}] = Floki.find(parsed, "a")
      assert Map.new(attrs)["class"] =~ "ui-tab__icon"

      assert parsed |> Floki.find("a") |> Floki.text() |> String.trim() ==
               "First"
    end

    test "variant, size and orientation add the modifier classes" do
      [default] = render_tabs(%{}) |> Floki.find("nav")
      assert [classes] = Floki.attribute(default, "class")
      assert String.split(classes) == ["ui-tabs"]

      [nav] =
        render_tabs(%{
          variant: "pills",
          size: "small",
          orientation: "vertical",
          class: "mx-3"
        })
        |> Floki.find("nav")

      [classes] = Floki.attribute(nav, "class")

      assert ~w(ui-tabs ui-tabs--pills ui-tabs--small ui-tabs--vertical mx-3) --
               String.split(classes) == []
    end
  end

  describe "tabs/1 in hash mode" do
    test "renders the markup the TabbedContainer hook reads" do
      parsed = render_hash_tabs(%{class: "run-tab-container"})

      assert [container] = Floki.find(parsed, "div#hash-tabs")
      assert Floki.attribute(container, "phx-hook") == ["TabbedContainer"]
      assert Floki.attribute(container, "data-default-hash") == ["log"]

      assert ~w(flex flex-col gap-x-4 gap-y-2 tab-container run-tab-container) --
               String.split(hd(Floki.attribute(container, "class"))) == []

      assert [{"div", _, tablist_children} = tablist] =
               Floki.find(container, "[role=tablist]")

      assert [classes] = Floki.attribute(tablist, "class")
      assert String.split(classes) == ["ui-tabs"]

      # The hook clears aria-selected through the tab's parentNode.
      assert [{"a", log_attrs, log_children}, {"span", input_attrs, _}] =
               Enum.filter(tablist_children, &is_tuple/1)

      assert Map.new(log_attrs) == %{
               "id" => "log-tab",
               "aria-controls" => "log-panel",
               "aria-selected" => "false",
               "role" => "tab",
               "data-hash" => "log",
               "href" => "#log",
               "lv-keep-aria" => "lv-keep-aria",
               "class" => "ui-tab"
             }

      # The icon sits before the label.
      assert [{"span", icon_attrs, _} | _] =
               Enum.filter(log_children, &is_tuple/1)

      assert Map.new(icon_attrs)["class"] =~ "ui-tab__icon"
      assert Map.new(icon_attrs)["class"] =~ "hero-key"

      assert Map.new(input_attrs) == %{
               "id" => "input-tab",
               "aria-controls" => "input-panel",
               "aria-selected" => "false",
               "role" => "tab",
               "data-disabled" => "data-disabled",
               "data-hash" => "input",
               "phx-hook" => "Tooltip",
               "aria-label" => "Pick a step",
               "data-allow-html" => "true",
               "lv-keep-aria" => "lv-keep-aria",
               "class" => "ui-tab"
             }

      panels = Floki.find(container, "[role=tabpanel]")

      assert Enum.map(panels, fn {"div", attrs, _} -> Map.new(attrs) end) == [
               %{
                 "id" => "log-panel",
                 "aria-labelledby" => "log-tab",
                 "class" => "flex h-full hidden",
                 "role" => "tabpanel",
                 "tabindex" => "0",
                 "lv-keep-class" => "lv-keep-class"
               },
               %{
                 "id" => "input-panel",
                 "aria-labelledby" => "input-tab",
                 "class" => "hidden",
                 "role" => "tabpanel",
                 "tabindex" => "0",
                 "lv-keep-class" => "lv-keep-class"
               }
             ]
    end

    test "vertical puts the panels in a grow column" do
      [container] =
        render_hash_tabs(%{orientation: "vertical"}) |> Floki.find("#hash-tabs")

      assert ~w(flex flex-row gap-y-2 tab-container) --
               String.split(hd(Floki.attribute(container, "class"))) == []

      assert [classes] =
               container
               |> Floki.find("[role=tablist]")
               |> Floki.attribute("class")

      assert String.split(classes) == ["ui-tabs", "ui-tabs--vertical"]

      assert container
             |> Floki.find("div.grow > [role=tabpanel]")
             |> Enum.flat_map(&Floki.attribute(&1, "id")) ==
               ["log-panel", "input-panel"]
    end

    test "stays in hash mode when there are no panels" do
      parsed = render_hash_tabs(%{panel: []})

      assert Floki.find(parsed, "#hash-tabs[phx-hook=TabbedContainer]") != []
      assert Floki.find(parsed, "[role=tabpanel]") == []
    end
  end
end
