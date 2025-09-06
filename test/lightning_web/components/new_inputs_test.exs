defmodule LightningWeb.Components.NewInputsTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias LightningWeb.Components.NewInputs

  describe "input type=color" do
    test "renders default color swatch + readout when no value is given" do
      html =
        render_component(&NewInputs.input/1, %{
          type: "color",
          id: "c1",
          name: "project[color]",
          label: "Color",
          swatch_style: ""
        })

      # native color input wiring
      assert html =~ ~s(id="c1-native")
      assert html =~ ~s(for="c1-native")

      # pretty label & swatch
      assert html =~ ~s(data-swatch)
      assert html =~ "background-color: #79B2D6"
      assert html =~ ~r/>\s*#79B2D6\s*</

      # default shape = "rounded"
      assert html =~ "rounded-md"
    end

    test "normalizes short lowercase hex to 6-digit uppercase" do
      html =
        render_component(&NewInputs.input/1, %{
          type: "color",
          id: "c2",
          name: "project[color]",
          value: "#abc",
          swatch_style: ""
        })

      assert html =~ "background-color: #AABBCC"
      assert html =~ ~r/>\s*#AABBCC\s*</
      assert html =~ ~s(value="#AABBCC")
    end

    test "applies shape variants" do
      html_square =
        render_component(&NewInputs.input/1, %{
          type: "color",
          id: "c3",
          name: "project[color]",
          value: "#123456",
          shape: "square",
          swatch_style: ""
        })

      assert html_square =~ "rounded-none"

      html_circle =
        render_component(&NewInputs.input/1, %{
          type: "color",
          id: "c4",
          name: "project[color]",
          value: "#123456",
          shape: "circle",
          swatch_style: ""
        })

      assert html_circle =~ "rounded-full"
    end

    test "honors disabled and custom classes/styles" do
      html =
        render_component(&NewInputs.input/1, %{
          type: "color",
          id: "c5",
          name: "project[color]",
          value: "#336699",
          disabled: true,
          wrapper_class: "mt-2",
          swatch_class: "ring-1 ring-offset-1",
          swatch_style:
            "--ring: #336699; box-shadow: 0 0 0 1px var(--ring) inset, 0 0 0 2px white inset; border-color: var(--ring);"
        })

      # native input is present, hidden, and receives `disabled`
      assert html =~ ~s(<input type="color" id="c5-native")
      assert html =~ ~s(class="sr-only")
      assert html =~ ~s(disabled)

      # disabled styling applied on pretty label
      assert html =~ "opacity-50"

      # custom wrapper/swatch classes & styles make it through
      assert html =~ "mt-2"
      assert html =~ "ring-1"
      assert html =~ "--ring: #336699"
    end

    test "required star and ColorPicker wiring are present" do
      html =
        render_component(&NewInputs.input/1, %{
          type: "color",
          id: "wired",
          name: "project[color]",
          label: "Color",
          required: true,
          swatch_style: ""
        })

      # required star + label text
      assert html =~ ~r/>\s*Color\b/
      assert html =~ ~s(<span class="text-red-500"> *</span>)

      # wiring between pretty label and native input
      assert html =~ ~s(id="wired-pretty")
      assert html =~ ~s(for="wired-native")
      assert html =~ ~s(phx-hook="ColorPicker")
      assert html =~ ~s(data-input-id="#wired-native")
    end

    test "applies extra class to pretty label and shows disabled cursor" do
      html =
        render_component(&NewInputs.input/1, %{
          type: "color",
          id: "c6",
          name: "project[color]",
          value: "#336699",
          class: "my-pretty-class",
          disabled: true,
          swatch_style: ""
        })

      # pretty label gets extra classes and disabled styling
      assert html =~ ~s(id="c6-pretty")
      assert html =~ "my-pretty-class"
      assert html =~ "cursor-not-allowed"
      assert html =~ "opacity-50"
    end

    test "normalizes 6-digit lowercase hex to uppercase" do
      html =
        render_component(&NewInputs.input/1, %{
          type: "color",
          id: "c7",
          name: "project[color]",
          value: "#ff00aa",
          swatch_style: ""
        })

      assert html =~ "background-color: #FF00AA"
      assert html =~ ~r/>\s*#FF00AA\s*</
      assert html =~ ~s(value="#FF00AA")
    end
  end
end
