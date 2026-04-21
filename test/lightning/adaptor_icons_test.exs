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

  describe "fetch_icon_bytes/2 local-first" do
    setup do
      repo_dir =
        Path.join(
          System.tmp_dir!(),
          "icons_local_test_#{System.unique_integer([:positive])}"
        )

      File.mkdir_p!(repo_dir)

      previous_config =
        Application.get_env(:lightning, Lightning.AdaptorRegistry)

      Application.put_env(
        :lightning,
        Lightning.AdaptorRegistry,
        Keyword.put(previous_config || [], :local_adaptors_repo, repo_dir)
      )

      stub(Lightning.MockConfig, :adaptor_registry, fn ->
        [local_adaptors_repo: repo_dir]
      end)

      on_exit(fn ->
        Application.put_env(
          :lightning,
          Lightning.AdaptorRegistry,
          previous_config || []
        )

        File.rm_rf(repo_dir)
      end)

      %{repo_dir: repo_dir}
    end

    test "reads PNG from local repo when the file exists", %{repo_dir: repo_dir} do
      png = <<137, 80, 78, 71, 0, 1, 2, 3>>
      assets_dir = Path.join([repo_dir, "packages", "localadaptor", "assets"])
      File.mkdir_p!(assets_dir)
      File.write!(Path.join(assets_dir, "square.png"), png)

      # No Tesla mock needed — must NOT make an HTTP call
      assert {:ok, ^png} =
               Lightning.AdaptorIcons.fetch_icon_bytes("localadaptor", "square")
    end

    test "falls back to GitHub when local file is missing", %{
      repo_dir: _repo_dir
    } do
      png = <<1, 2, 3, 4>>

      Mox.expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        assert env.url =~ "raw.githubusercontent.com/OpenFn/adaptors"
        {:ok, %Tesla.Env{status: 200, body: png}}
      end)

      assert {:ok, ^png} =
               Lightning.AdaptorIcons.fetch_icon_bytes("remoteadaptor", "square")
    end
  end

  describe "fetch_icon_bytes/2 non-local mode" do
    test "always hits GitHub" do
      png = <<5, 6, 7>>

      Mox.expect(Lightning.Tesla.Mock, :call, fn env, _opts ->
        assert env.url =~ "raw.githubusercontent.com/OpenFn/adaptors"
        {:ok, %Tesla.Env{status: 200, body: png}}
      end)

      assert {:ok, ^png} =
               Lightning.AdaptorIcons.fetch_icon_bytes("anything", "square")
    end

    test "returns {:http, status} on non-200" do
      Mox.expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:ok, %Tesla.Env{status: 404, body: ""}}
      end)

      assert {:error, {:http, 404}} =
               Lightning.AdaptorIcons.fetch_icon_bytes("missing", "square")
    end

    test "propagates transport errors" do
      Mox.expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:error, :timeout}
      end)

      assert {:error, :timeout} =
               Lightning.AdaptorIcons.fetch_icon_bytes("unreachable", "square")
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
