defmodule LightningWeb.Components.CommonTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "wrapper_tooltip/1 and HTML" do
    # The Tooltip hook reads aria-label off the DOM *property*, which undoes
    # the escaping HEEx applied to the attribute, and hands the result to
    # tippy's setContent. With allowHTML on, a workflow name holding markup
    # became live elements for anyone viewing the project (#4577).
    #
    # This is the only security-relevant change in the branch and it had no
    # test: flipping data-allow-html back to a hardcoded "true" left the whole
    # suite green.
    test "HTML is off by default" do
      html =
        render_component(&LightningWeb.Components.Common.wrapper_tooltip/1,
          id: "t",
          tooltip: "plain text",
          inner_block: %{
            inner_block: fn _, _ -> "child" end,
            __slot__: :inner_block
          }
        )

      assert html =~ ~s(data-allow-html="false")
      refute html =~ ~s(data-allow-html="true")
    end

    test "HTML is on only when a caller asks for it" do
      html =
        render_component(&LightningWeb.Components.Common.wrapper_tooltip/1,
          id: "t",
          tooltip: "a<br/>b",
          allow_html: true,
          inner_block: %{
            inner_block: fn _, _ -> "child" end,
            __slot__: :inner_block
          }
        )

      assert html =~ ~s(data-allow-html="true")
    end

    test "a name holding markup is inert in the default case" do
      html =
        render_component(&LightningWeb.Components.Common.wrapper_tooltip/1,
          id: "t",
          tooltip: "<img src=x onerror=alert(1)>",
          inner_block: %{
            inner_block: fn _, _ -> "child" end,
            __slot__: :inner_block
          }
        )

      assert html =~ ~s(data-allow-html="false")
      refute html =~ "<img src=x"
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
