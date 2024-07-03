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
      assert html =~
               "M9 12.75L11.25 15 15 9.75M21 12c0 1.268-.63 2.39-1.593 3.068a3.745 3.745 0 01-1.043 3.296 3.745 3.745 0 01-3.296 1.043A3.745 3.745 0 0112 21c-1.268 0-2.39-.63-3.068-1.593a3.746 3.746 0 01-3.296-1.043 3.745 3.745 0 01-1.043-3.296A3.745 3.745 0 013 12c0-1.268.63-2.39 1.593-3.068a3.745 3.745 0 011.043-3.296 3.746 3.746 0 013.296-1.043A3.746 3.746 0 0112 3c1.268 0 2.39.63 3.068 1.593a3.746 3.746 0 013.296 1.043 3.746 3.746 0 011.043 3.296A3.745 3.745 0 0121 12z"
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
      assert html =~
               "M21 7.5l-9-5.25L3 7.5m18 0l-9 5.25m9-5.25v9l-9 5.25M3 7.5l9 5.25M3 7.5v9l9 5.25m0-9v9"
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
      assert html =~
               "M21 7.5l-9-5.25L3 7.5m18 0l-9 5.25m9-5.25v9l-9 5.25M3 7.5l9 5.25M3 7.5v9l9 5.25m0-9v9"
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
