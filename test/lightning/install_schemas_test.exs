defmodule Lightning.InstallSchemasTest do
  use ExUnit.Case, async: false

  import Mock

  alias Mix.Tasks.Lightning.InstallSchemas

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "install_schemas_test_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp_dir)

    previous = Application.get_env(:lightning, :schemas_path)
    Application.put_env(:lightning, :schemas_path, tmp_dir)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:lightning, :schemas_path, previous),
        else: Application.delete_env(:lightning, :schemas_path)

      File.rm_rf(tmp_dir)
    end)

    Mix.shell(Mix.Shell.Process)

    %{schemas_path: tmp_dir}
  end

  describe "run/1" do
    test "installs schemas and prints count", %{schemas_path: schemas_path} do
      packages =
        Jason.encode!(%{
          "@openfn/language-http" => "read",
          "@openfn/language-salesforce" => "read",
          "@openfn/language-common" => "read"
        })

      schema_body = Jason.encode!(%{"type" => "object"})

      with_mock HTTPoison,
        start: fn -> {:ok, self()} end,
        get: fn url, _headers, _opts ->
          cond do
            String.contains?(url, "registry.npmjs.org") ->
              {:ok, %HTTPoison.Response{status_code: 200, body: packages}}

            String.contains?(url, "cdn.jsdelivr.net") ->
              {:ok, %HTTPoison.Response{status_code: 200, body: schema_body}}

            true ->
              {:ok, %HTTPoison.Response{status_code: 404, body: ""}}
          end
        end do
        InstallSchemas.run([])

        assert_receive {:mix_shell, :info, [msg]}
        assert msg =~ "Schemas installation has finished. 2 installed"

        assert File.exists?(Path.join(schemas_path, "http.json"))
        assert File.exists?(Path.join(schemas_path, "salesforce.json"))
        refute File.exists?(Path.join(schemas_path, "common.json"))
      end
    end

    test "raises on failure" do
      with_mock HTTPoison,
        start: fn -> {:ok, self()} end,
        get: fn _url, _headers, _opts ->
          {:error, %HTTPoison.Error{reason: :econnrefused}}
        end do
        assert_raise Mix.Error, ~r/Schema installation failed/, fn ->
          InstallSchemas.run([])
        end
      end
    end

    test "passes --exclude args through" do
      packages =
        Jason.encode!(%{
          "@openfn/language-http" => "read",
          "@openfn/language-salesforce" => "read"
        })

      schema_body = Jason.encode!(%{"type" => "object"})

      with_mock HTTPoison,
        start: fn -> {:ok, self()} end,
        get: fn url, _headers, _opts ->
          cond do
            String.contains?(url, "registry.npmjs.org") ->
              {:ok, %HTTPoison.Response{status_code: 200, body: packages}}

            String.contains?(url, "cdn.jsdelivr.net") ->
              {:ok, %HTTPoison.Response{status_code: 200, body: schema_body}}

            true ->
              {:ok, %HTTPoison.Response{status_code: 404, body: ""}}
          end
        end do
        InstallSchemas.run(["--exclude", "language-http"])

        assert_receive {:mix_shell, :info, [msg]}
        assert msg =~ "1 installed"
      end
    end
  end

  describe "parse_excluded/1 delegates to CredentialSchemas" do
    test "with --exclude args" do
      assert [
               "pack1",
               "pack2",
               "language-common",
               "language-devtools",
               "language-divoc"
             ] ==
               Lightning.CredentialSchemas.parse_excluded([
                 "--exclude",
                 "pack1",
                 "pack2"
               ])
    end

    test "without args returns defaults" do
      assert ["language-common", "language-devtools", "language-divoc"] ==
               Lightning.CredentialSchemas.parse_excluded([])
    end
  end
end
