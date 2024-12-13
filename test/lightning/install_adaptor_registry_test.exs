defmodule Lightning.InstallAdaptorRegistryTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Mix.Tasks.Lightning.InstallAdaptorRegistry

  describe "install_adaptor_registry mix task" do
    @describetag :tmp_dir
    setup do
      stub(:hackney)

      :ok
    end

    test "does not write file when no adaptors are found", %{tmp_dir: tmp_dir} do
      expect(:hackney, :request, fn
        :get,
        "https://registry.npmjs.org/-/user/openfn/package",
        [],
        "",
        [recv_timeout: 15_000, pool: :default] ->
          {:error, :nxdomain}
      end)

      file_path = Path.join([tmp_dir, "cache.json"])
      refute File.exists?(file_path)

      InstallAdaptorRegistry.run(["--path", file_path])

      refute File.exists?(file_path)
    end

    test "writes to specified file", %{tmp_dir: tmp_dir} do
      expect(:hackney, :request, fn
        :get,
        "https://registry.npmjs.org/-/user/openfn/package",
        [],
        "",
        [recv_timeout: 15_000, pool: :default] ->
          {:ok, 200, "headers", :client}
      end)

      expect(:hackney, :body, fn :client, _timeout ->
        {:ok, File.read!("test/fixtures/openfn-packages-npm.json")}
      end)

      stub(:hackney, :body, fn :adaptor, _timeout ->
        {:ok, File.read!("test/fixtures/language-common-npm.json")}
      end)

      stub(:hackney, :request, fn
        :get,
        "https://registry.npmjs.org/" <> _adaptor,
        [],
        "",
        [recv_timeout: 15_000, pool: :default] ->
          {:ok, 200, "headers", :adaptor}
      end)

      file_path = Path.join([tmp_dir, "cache.json"])
      refute File.exists?(file_path)

      InstallAdaptorRegistry.run(["--path", file_path])

      assert File.exists?(file_path)
    end
  end
end
