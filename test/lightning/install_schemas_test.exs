defmodule Lightning.InstallSchemasTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Mix.Tasks.Lightning.InstallSchemas

  describe "install_schemas mix task" do
    setup do
      stub(:hackney)

      :ok
    end

    test "run" do
      expect(:hackney, :request, fn
        :get,
        "https://registry.npmjs.org/-/user/openfn/package",
        [],
        "",
        [recv_timeout: 15_000, pool: :default] ->
          {:ok, 200, "headers", :client}
      end)

      expect(:hackney, :body, fn :client, _timeout ->
        {:ok,
         ~s({"@openfn/language-primero": "write","@openfn/language-asana": "write"})}
      end)

      expect(:hackney, :request, fn
        :get,
        "https://cdn.jsdelivr.net/npm/@openfn/language-asana/configuration-schema.json",
        [],
        "",
        [recv_timeout: 15_000, pool: :default] ->
          {:ok, 200, "headers", :client}
      end)

      expect(:hackney, :body, fn :client, _timeout ->
        {:ok, ~s({"name": "language-asana"})}
      end)

      expect(:hackney, :request, fn
        :get,
        "https://cdn.jsdelivr.net/npm/@openfn/language-primero/configuration-schema.json",
        [],
        "",
        [recv_timeout: 15_000, pool: :default] ->
          {:ok, 200, "headers", :client}
      end)

      expect(:hackney, :body, fn :client, _timeout ->
        {:ok, ~s({"name": "language-primero"})}
      end)

      File
      |> expect(:mkdir_p, fn _ -> nil end)
      |> expect(:open!, fn "priv/schemas/asana.json", [:write] -> nil end)
      |> expect(:open!, fn "priv/schemas/primero.json", [:write] -> nil end)
      |> expect(:close, fn _ -> nil end)

      InstallSchemas.run([])
    end
  end
end
