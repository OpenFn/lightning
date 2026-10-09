defmodule LightningWeb.Components.UI.BadgeTest do
  @moduledoc false
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias LightningWeb.Components.UI.Badge

  defp render_badge(assigns) do
    %{inner_block: [%{inner_block: fn _, _ -> "main" end}]}
    |> Map.merge(assigns)
    |> then(fn assigns -> render_component(&Badge.badge/1, assigns) end)
    |> Floki.parse_fragment!()
  end

  defp classes(element) do
    element |> Floki.attribute("class") |> hd() |> String.split()
  end

  describe "badge/1" do
    test "renders a neutral span with the text by default" do
      assert [{"span", _, _} = span] = render_badge(%{})
      assert classes(span) == ~w(ui-badge ui-badge--neutral)
      assert span |> Floki.text() |> String.trim() == "main"
    end

    test "each colour adds its modifier class" do
      for color <- ~w(neutral success warning danger info brand orange dark) do
        [span] = render_badge(%{color: color})
        assert classes(span) == ["ui-badge", "ui-badge--#{color}"]
      end
    end

    test "a nil colour falls back to neutral" do
      [span] = render_badge(%{color: nil})
      assert classes(span) == ~w(ui-badge ui-badge--neutral)
    end

    test "size, mono, dot and class add their classes" do
      [span] =
        render_badge(%{size: "small", mono: true, dot: true, class: "max-w-32"})

      assert classes(span) ==
               ~w(ui-badge ui-badge--neutral ui-badge--small ui-badge--mono ui-badge--dot max-w-32)
    end

    test "dot renders a dot, and pulse adds the ping ring inside it" do
      [span] = render_badge(%{dot: true})
      assert [dot] = Floki.find(span, ".ui-badge__dot")
      assert Floki.find(dot, ".ui-badge__pulse") == []

      [span] = render_badge(%{dot: true, pulse: true})
      assert [_] = Floki.find(span, ".ui-badge__dot .ui-badge__pulse")
    end

    test "icon renders before the text" do
      [span] = render_badge(%{icon: "hero-bolt"})

      assert {"span", _, [{"span", icon_attrs, _} | _]} = span
      assert Map.new(icon_attrs)["class"] =~ "hero-bolt ui-badge__icon"
      assert Map.new(icon_attrs)["aria-hidden"] == "true"
    end

    test "rest attrs land on the span" do
      [span] =
        render_badge(%{
          id: "env-badge-1",
          title: "Main",
          "aria-label": "Environment",
          "phx-hook": "Tooltip",
          "data-placement": "bottom",
          tabindex: "0"
        })

      assert Floki.attribute(span, "id") == ["env-badge-1"]
      assert Floki.attribute(span, "title") == ["Main"]
      assert Floki.attribute(span, "aria-label") == ["Environment"]
      assert Floki.attribute(span, "phx-hook") == ["Tooltip"]
      assert Floki.attribute(span, "data-placement") == ["bottom"]
      assert Floki.attribute(span, "tabindex") == ["0"]
    end

    test "the remove slot renders a named button and passes its attrs on" do
      [span] =
        render_badge(%{
          remove: [
            %{
              __slot__: :remove,
              inner_block: nil,
              label: "Remove Project A",
              id: "remove-project-a",
              "phx-click": "remove_selected_project",
              "phx-value-project_id": "a",
              "data-confirm": "Are you sure?"
            }
          ]
        })

      assert [button] = Floki.find(span, "button")
      assert classes(button) == ["ui-badge__remove"]
      assert Floki.attribute(button, "type") == ["button"]
      assert Floki.attribute(button, "aria-label") == ["Remove Project A"]
      assert Floki.attribute(button, "id") == ["remove-project-a"]

      assert Floki.attribute(button, "phx-click") == [
               "remove_selected_project"
             ]

      assert Floki.attribute(button, "phx-value-project_id") == ["a"]
      assert Floki.attribute(button, "data-confirm") == ["Are you sure?"]
      assert Floki.attribute(button, "label") == []
    end

    test "the remove slot raises without a label" do
      assert_raise ArgumentError, ~r/label/, fn ->
        render_badge(%{remove: [%{__slot__: :remove, inner_block: nil}]})
      end
    end
  end

  describe "badge_class/1" do
    test "returns the class list for real buttons and links" do
      assert Badge.badge_class([]) == ~w(ui-badge ui-badge--neutral)

      assert Badge.badge_class(
               color: "brand",
               size: "small",
               mono: true,
               interactive: true
             ) ==
               ~w(ui-badge ui-badge--brand ui-badge--small ui-badge--mono ui-badge--interactive)
    end
  end
end
