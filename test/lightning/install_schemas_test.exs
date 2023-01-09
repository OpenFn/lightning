defmodule Lightning.InstallSchemasTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Mix.Tasks.Lightning.InstallSchemas

  @request_options [recv_timeout: 15_000, pool: :default]
  @ok_200 {:ok, 200, "headers", :client}
  @ok_400 {:ok, 400, "headers", :client}

  describe "install_schemas mix task" do
    setup do
      stub(:hackney)

      :ok
    end

    test "run success" do
      expect(:hackney, :request, fn
        :get,
        "https://registry.npmjs.org/-/user/openfn/package",
        [],
        "",
        @request_options ->
          @ok_200
      end)

      expect(:hackney, :body, fn :client, _timeout ->
        {:ok,
         ~s({"@openfn/language-primero": "write","@openfn/language-asana": "write", "@openfn/language-common": "write"})}
      end)

      expect(:hackney, :request, fn
        :get,
        "https://cdn.jsdelivr.net/npm/@openfn/language-asana/configuration-schema.json",
        [],
        "",
        @request_options ->
          @ok_200
      end)

      expect(:hackney, :body, fn :client, _timeout ->
        {:ok, ~s({"name": "language-asana"})}
      end)

      expect(:hackney, :request, fn
        :get,
        "https://cdn.jsdelivr.net/npm/@openfn/language-primero/configuration-schema.json",
        [],
        "",
        @request_options ->
          @ok_200
      end)

      expect(:hackney, :body, fn :client, _timeout ->
        {:ok, ~s({"name": "language-primero"})}
      end)

      File
      |> expect(:rm_rf, fn _ -> nil end)
      |> expect(:mkdir_p, fn _ -> nil end)
      |> expect(:open!, fn "priv/schemas/asana.json", [:write] -> nil end)
      |> expect(:open!, fn "priv/schemas/primero.json", [:write] -> nil end)
      |> expect(:close, 2, fn _ -> nil end)

      IO
      |> expect(:binwrite, fn _, ~s({"name": "language-asana"}) -> nil end)
      |> expect(:binwrite, fn _, ~s({"name": "language-primero"}) -> nil end)

      # |> expect(:binwrite, fn _, ~s({"name": "language-common"}) -> nil end)

      InstallSchemas.run([])
    end

    test "run fail" do
      expect(File, :rm_rf, fn _ -> {:error, "error occured"} end)
      expect(File, :mkdir_p, fn _ -> {:error, "error occured"} end)

      assert_raise RuntimeError,
                   "Couldn't create the schemas directory: priv/schemas/, got :error occured.",
                   fn ->
                     InstallSchemas.run([])
                   end
    end

    test "persist_schema fail 1" do
      expect(:hackney, :request, fn
        :get,
        "https://cdn.jsdelivr.net/npm/@openfn/language-asana/configuration-schema.json",
        [],
        "",
        @request_options ->
          @ok_200
      end)

      expect(:hackney, :body, fn :client, _timeout ->
        {:error, %HTTPoison.Error{}}
      end)

      assert_raise RuntimeError, "Unable to access @openfn/language-asana", fn ->
        InstallSchemas.persist_schema("@openfn/language-asana")
      end
    end

    test "persist_schema fail 2" do
      expect(:hackney, :request, fn
        :get,
        "https://cdn.jsdelivr.net/npm/@openfn/language-asana/configuration-schema.json",
        [],
        "",
        @request_options ->
          @ok_400
      end)

      expect(:hackney, :body, fn :client, _timeout ->
        {:ok, %HTTPoison.Response{status_code: 400}}
      end)

      assert_raise RuntimeError, fn ->
        InstallSchemas.persist_schema("@openfn/language-asana")
      end
    end

    test "fetch_schemas fail 1" do
      expect(:hackney, :request, fn
        :get,
        "https://registry.npmjs.org/-/user/openfn/package",
        [],
        "",
        @request_options ->
          @ok_200
      end)

      expect(:hackney, :body, fn :client, _timeout ->
        {:error, %HTTPoison.Error{}}
      end)

      assert_raise RuntimeError,
                   "Unable to connect to NPM; no adaptors fetched.",
                   fn ->
                     InstallSchemas.fetch_schemas([])
                   end
    end

    test "fetch_schemas fail 2" do
      expect(:hackney, :request, fn
        :get,
        "https://registry.npmjs.org/-/user/openfn/package",
        [],
        "",
        @request_options ->
          @ok_400
      end)

      expect(:hackney, :body, fn :client, _timeout ->
        {:ok, %HTTPoison.Response{status_code: 400}}
      end)

      assert_raise RuntimeError,
                   "Unable to access openfn user packages. status=400",
                   fn ->
                     InstallSchemas.fetch_schemas([])
                   end
    end

    test "parse_excluded" do
      assert ["pack1", "pack2", "language-common", "language-devtools"] ==
               InstallSchemas.parse_excluded(["--exclude", "pack1", "pack2"])

      assert ["language-common", "language-devtools"] ==
               InstallSchemas.parse_excluded([])
    end
  end
end
