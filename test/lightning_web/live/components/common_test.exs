defmodule LightningWeb.Components.CommonTest do
  use LightningWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "version_chip on docker release" do
    setup do
      prev = Application.get_env(:lightning, :image_info)

      Application.put_env(:lightning, :image_info,
        image_tag: "v#{Application.spec(:lightning, :vsn)}",
        branch: "main",
        commit: "abcdef7"
      )

      on_exit(fn ->
        Application.put_env(:lightning, :image_info, prev)
      end)
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
    setup do
      prev = Application.get_env(:lightning, :image_info)

      Application.put_env(:lightning, :image_info,
        image_tag: "edge",
        branch: "main",
        commit: "abcdef7"
      )

      on_exit(fn ->
        Application.put_env(:lightning, :image_info, prev)
      end)
    end

    test "displays the SHA and a cube" do
      html = render_component(&LightningWeb.Components.Common.version_chip/1)

      assert html =~ "Docker image tag found"
      assert html =~ "unreleased build"
      assert html =~ "abcdef7"

      # Check for the cube icon
      assert html =~
               "M21 7.5l-9-5.25L3 7.5m18 0l-9 5.25m9-5.25v9l-9 5.25M3 7.5l9 5.25M3 7.5v9l9 5.25m0-9v9"
    end
  end

  describe "version_chip on tag mismatch" do
    setup do
      prev = Application.get_env(:lightning, :image_info)

      Application.put_env(:lightning, :image_info,
        image_tag: "vX.Y.Z",
        branch: "main",
        commit: "abcdef7"
      )

      on_exit(fn ->
        Application.put_env(:lightning, :image_info, prev)
      end)
    end

    test "displays the version and a badge" do
      html = render_component(&LightningWeb.Components.Common.version_chip/1)


      assert html =~
               "Detected image tag that does not match application version"

      assert html =~ "v#{elem(:application.get_key(:lightning, :vsn), 1)}"

      # Check for the warning icon
      assert html =~
               "M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z"
    end
  end

  describe "version_chip on tag mismatch where image_tag == 'edge'" do
    setup do
      prev = Application.get_env(:lightning, :image_info)

      Application.put_env(:lightning, :image_info,
        image_tag: "edge",
        branch: "main",
        commit: "abcdef7"
      )

      on_exit(fn ->
        Application.put_env(:lightning, :image_info, prev)
      end)
    end

    test "displays the SHA and a cube" do
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
    setup do
      prev = Application.get_env(:lightning, :image_info)

      Application.put_env(:lightning, :image_info,
        image_tag: nil,
        branch: "main",
        commit: "abcdef7"
      )

      on_exit(fn ->
        Application.put_env(:lightning, :image_info, prev)
      end)
    end

    test "displays the Lightning version without an icon" do
      html = render_component(&LightningWeb.Components.Common.version_chip/1)

      assert html =~ "Lightning v2.0.5"
      assert html =~ "OpenFn/Lightning v2.0.5"
      refute html =~ "<svg"
    end
  end
end
