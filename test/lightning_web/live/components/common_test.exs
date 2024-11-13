defmodule LightningWeb.Components.CommonTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

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

      assert html =~ "Docker image tag found"
      assert html =~ "tagged release build"
      assert html =~ "v#{Application.spec(:lightning, :vsn)}"

      # Check for the badge icon
      assert html
             |> Floki.parse_fragment!()
             |> Floki.find("span.hero-check-badge")
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

      assert html =~ "Docker image tag found"
      assert html =~ "unreleased build"
      assert html =~ "abcdef7"

      # Check for the cube icon
      assert html |> Floki.parse_fragment!() |> Floki.find("span.hero-cube")
    end
  end

  describe "version_chip on tag mismatch where image_tag == 'edge'" do
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

      assert html =~ "Docker image tag found"
      assert html =~ "unreleased build"
      assert html =~ "abcdef7"

      # Check for the cube icon
      assert html
             |> Floki.parse_fragment!()
             |> Floki.find("span.hero-exclamation-triangle")
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

      assert html =~ "Lightning v#{Application.spec(:lightning, :vsn)}"
      assert html =~ "OpenFn/Lightning v#{Application.spec(:lightning, :vsn)}"
      refute html =~ "<svg"
    end
  end
end
