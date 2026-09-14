defmodule LightningWeb.Components.CommonTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "wrapper_tooltip/1 and HTML" do
    # The hook used to read aria-label off the DOM *property*, which undoes the
    # escaping HEEx applied to the attribute, and hand the result to tippy with
    # allowHTML on, so a workflow name holding markup became live elements for
    # anyone viewing the project (#4577). The content now goes in a <template>
    # that the browser parses, so no caller decides whether a name is markup.
    defp render_tooltip(assigns) do
      render_component(
        &LightningWeb.Components.Common.wrapper_tooltip/1,
        Keyword.merge(
          [
            inner_block: %{
              inner_block: fn _, _ -> "child" end,
              __slot__: :inner_block
            }
          ],
          assigns
        )
      )
    end

    test "the tooltip goes in a template rather than an HTML-bearing attribute" do
      html = render_tooltip(id: "t", tooltip: "plain text")

      assert html =~ ~s(<template data-tooltip-content>)
      refute html =~ "data-allow-html"
    end

    test "a name holding markup is escaped, not rendered" do
      html = render_tooltip(id: "t", tooltip: "<img src=x onerror=alert(1)>")

      refute html =~ "<img src=x"
      assert html =~ "&lt;img src=x onerror=alert(1)&gt;"
    end

    test "a subtitle is a second line, and is escaped too" do
      html =
        render_tooltip(
          id: "t",
          tooltip: "My Workflow",
          subtitle: "<b>Click to view</b>"
        )

      assert html =~ "My Workflow"
      refute html =~ "<b>Click to view</b>"
      assert html =~ "&lt;b&gt;Click to view&lt;/b&gt;"
    end

    test "no subtitle means no second line" do
      html = render_tooltip(id: "t", tooltip: "My Workflow")

      refute html =~ "text-xs text-gray-500"
    end
  end

  describe "version_chip on docker release" do
    setup do
      Mox.stub(LightningMock, :release, fn ->
        %{
          label: "v#{Application.spec(:lightning, :vsn)}",
          commit: "abcdef7",
          image_tag: "v#{Application.spec(:lightning, :vsn)}",
          branch: "main",
          vsn: Application.spec(:lightning, :vsn)
        }
      end)

      :ok
    end

    test "displays the version and a badge" do
      html = render_component(&LightningWeb.Components.Common.version_chip/1)

      assert html =~ "Build"
      assert html =~ "v#{Application.spec(:lightning, :vsn)}"
    end
  end

  describe "version_chip on docker edge" do
    test "displays the SHA and a cube" do
      Mox.stub(LightningMock, :release, fn ->
        %{
          label: "v#{Application.spec(:lightning, :vsn)}",
          commit: "abcdef7",
          image_tag: "edge",
          branch: "main",
          vsn: Application.spec(:lightning, :vsn)
        }
      end)

      html = render_component(&LightningWeb.Components.Common.version_chip/1)

      assert html =~ "Unreleased build"
      assert html =~ "abcdef7"

      # Check for the cube icon
      assert html |> Floki.parse_fragment!() |> Floki.find("span.hero-cube")
    end
  end

  describe "version_chip all other cases" do
    test "displays the Lightning version without an icon" do
      Mox.stub(LightningMock, :release, fn ->
        %{
          label: "v#{Application.spec(:lightning, :vsn)}",
          commit: "abcdef7",
          image_tag: nil,
          branch: "main",
          vsn: Application.spec(:lightning, :vsn)
        }
      end)

      html = render_component(&LightningWeb.Components.Common.version_chip/1)

      assert html =~ "v#{Application.spec(:lightning, :vsn)}"
      assert html =~ "No image tag found."
    end
  end
end
