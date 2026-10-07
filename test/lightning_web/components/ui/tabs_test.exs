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
end
