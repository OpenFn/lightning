defmodule Lightning.DownloadAdaptorRegistryCacheTest do
  use ExUnit.Case, async: false

  import Mox
  import Tesla.Test

  setup :set_mox_from_context
  setup :verify_on_exit!

  alias Mix.Tasks.Lightning.DownloadAdaptorRegistryCache

  describe "download_adaptor_registry_cache mix task" do
    @describetag :tmp_dir
    test "does not write file when no adaptors are found", %{tmp_dir: tmp_dir} do
      expect_tesla_call(
        times: 1,
        returns: fn env, [] ->
          case env.url do
            "https://registry.npmjs.org/-/user/openfn/package" ->
              {:ok, json(%Tesla.Env{status: 200}, [])}

            "https://registry.npmjs.org/@openfn/language-asana" ->
              {:ok, json(%Tesla.Env{status: 200}, [])}
          end
        end
      )

      file_path = Path.join([tmp_dir, "cache.json"])
      refute File.exists?(file_path)

      DownloadAdaptorRegistryCache.run(["--path", file_path])

      refute File.exists?(file_path)
    end

    test "writes to specified file", %{tmp_dir: tmp_dir} do
      language_common_response =
        File.read!("test/fixtures/language-common-npm.json") |> Jason.decode!()

      expect_tesla_call(
        times: 7,
        returns: fn env, [] ->
          case env.url do
            "https://registry.npmjs.org/-/user/openfn/package" ->
              {:ok,
               json(
                 %Tesla.Env{status: 200},
                 File.read!("test/fixtures/openfn-packages-npm.json")
                 |> Jason.decode!()
               )}

            "https://registry.npmjs.org/@openfn/" <> _adaptor ->
              {:ok, json(%Tesla.Env{status: 200}, language_common_response)}
          end
        end
      )

      file_path = Path.join([tmp_dir, "cache.json"])
      refute File.exists?(file_path)

      DownloadAdaptorRegistryCache.run(["--path", file_path])

      assert File.exists?(file_path)
    end
  end
end
