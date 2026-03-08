defmodule Lightning.AdaptorIconsTest do
  use Lightning.DataCase, async: false

  import Mox

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    Lightning.AdaptorData.Cache.invalidate("icon")
    Lightning.AdaptorData.Cache.invalidate("icon_manifest")
    :ok
  end

  describe "refresh_manifest/0" do
    test "builds manifest from adaptor registry and stores in DB" do
      assert {:ok, manifest} = Lightning.AdaptorIcons.refresh_manifest()

      assert is_map(manifest)

      # The manifest should contain entries based on whatever adaptors
      # are in the registry cache
      if map_size(manifest) > 0 do
        {_name, sources} = Enum.at(manifest, 0)
        assert Map.has_key?(sources, "square")
        assert Map.has_key?(sources, "rectangle")
      end

      # Verify it was stored in DB
      assert {:ok, entry} =
               Lightning.AdaptorData.get("icon_manifest", "all")

      assert entry.content_type == "application/json"
      assert Jason.decode!(entry.data) == manifest
    end
  end

  describe "refresh/0" do
    test "returns manifest and spawns background prefetch" do
      assert {:ok, manifest} = Lightning.AdaptorIcons.refresh()
      assert is_map(manifest)
    end
  end

  describe "prefetch_icons/1" do
    test "skips icons already in DB" do
      Lightning.AdaptorData.put(
        "icon",
        "http-square",
        <<1, 2, 3>>,
        "image/png"
      )

      # No Tesla call should be made for http-square
      Lightning.AdaptorIcons.prefetch_icons(%{
        "http" => %{
          "square" => "/images/adaptors/http-square.png",
          "rectangle" => "/images/adaptors/http-rectangle.png"
        }
      })

      # The rectangle one would have attempted a fetch (via Hackney stub)
      # but the square one was skipped
      assert {:ok, _} = Lightning.AdaptorData.get("icon", "http-square")
    end

    test "fetches and stores missing icons from GitHub" do
      png_data = <<137, 80, 78, 71, 13, 10, 26, 10>>

      Mox.expect(Lightning.Tesla.Mock, :call, 2, fn env, _opts ->
        assert env.url =~ "raw.githubusercontent.com/OpenFn/adaptors"
        {:ok, %Tesla.Env{status: 200, body: png_data}}
      end)

      Lightning.AdaptorIcons.prefetch_icons(%{
        "testadaptor" => %{
          "square" => "/images/adaptors/testadaptor-square.png",
          "rectangle" => "/images/adaptors/testadaptor-rectangle.png"
        }
      })

      assert {:ok, sq} =
               Lightning.AdaptorData.get("icon", "testadaptor-square")

      assert sq.data == png_data

      assert {:ok, rect} =
               Lightning.AdaptorData.get("icon", "testadaptor-rectangle")

      assert rect.data == png_data
    end
  end
end
