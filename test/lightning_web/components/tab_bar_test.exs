defmodule LightningWeb.Components.TabBarTest do
  @moduledoc false
  use LightningWeb.ConnCase

  import Phoenix.LiveViewTest

  alias LightningWeb.Components.TabBar

  describe "pill_tabs/1" do
    test "renders all tabs" do
      html =
        render_component(&TabBar.pill_tabs/1, %{
          id: "test-tabs",
          active: "first",
          tab: [
            %{id: "first", patch: "/first", inner_block: fn _, _ -> "First" end},
            %{
              id: "second",
              patch: "/second",
              inner_block: fn _, _ -> "Second" end
            }
          ]
        })

      parsed = Floki.parse_fragment!(html)

      links = Floki.find(parsed, "a")
      assert length(links) == 2

      assert links |> Enum.map(&Floki.text/1) |> Enum.map(&String.trim/1) ==
               ["First", "Second"]
    end

    test "active tab has selected styling" do
      html =
        render_component(&TabBar.pill_tabs/1, %{
          id: "test-tabs",
          active: "second",
          tab: [
            %{id: "first", patch: "/first", inner_block: fn _, _ -> "First" end},
            %{
              id: "second",
              patch: "/second",
              inner_block: fn _, _ -> "Second" end
            }
          ]
        })

      parsed = Floki.parse_fragment!(html)

      [first, second] = Floki.find(parsed, "a")

      first_class = first |> Floki.attribute("class") |> hd()
      second_class = second |> Floki.attribute("class") |> hd()

      assert second_class =~ "bg-white"
      assert second_class =~ "text-indigo-600"

      refute first_class =~ "bg-white"
      assert first_class =~ "text-gray-500"
    end

    test "tabs link to their patch paths" do
      html =
        render_component(&TabBar.pill_tabs/1, %{
          id: "test-tabs",
          active: "first",
          tab: [
            %{
              id: "first",
              patch: "/path/one",
              inner_block: fn _, _ -> "One" end
            },
            %{
              id: "second",
              patch: "/path/two",
              inner_block: fn _, _ -> "Two" end
            }
          ]
        })

      parsed = Floki.parse_fragment!(html)

      assert Floki.find(parsed, "a[href='/path/one']") |> length() == 1
      assert Floki.find(parsed, "a[href='/path/two']") |> length() == 1
    end

    test "container has the correct id" do
      html =
        render_component(&TabBar.pill_tabs/1, %{
          id: "my-tabs",
          active: "a",
          tab: [
            %{id: "a", patch: "/a", inner_block: fn _, _ -> "A" end}
          ]
        })

      parsed = Floki.parse_fragment!(html)

      assert Floki.find(parsed, "#my-tabs") |> length() == 1
    end

    test "renders with three or more tabs" do
      tabs =
        for name <- ["alpha", "beta", "gamma"] do
          %{
            id: name,
            patch: "/#{name}",
            inner_block: fn _, _ -> String.capitalize(name) end
          }
        end

      html =
        render_component(&TabBar.pill_tabs/1, %{
          id: "multi-tabs",
          active: "beta",
          tab: tabs
        })

      parsed = Floki.parse_fragment!(html)

      links = Floki.find(parsed, "a")
      assert length(links) == 3

      [_, beta, _] = links
      beta_class = beta |> Floki.attribute("class") |> hd()
      assert beta_class =~ "bg-white"
      assert beta_class =~ "text-indigo-600"
    end
  end
end
