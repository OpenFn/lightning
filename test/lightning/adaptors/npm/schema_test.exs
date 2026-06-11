defmodule Lightning.Adaptors.NPM.SchemaTest do
  use ExUnit.Case, async: false

  alias Lightning.Adaptors.NPM.Schema

  @package "@openfn/language-http"
  @version "2.1.0"
  @path "/npm/#{@package}@#{@version}/configuration-schema.json"

  setup do
    bypass = Bypass.open()

    Application.put_env(:lightning, Lightning.Adaptors.NPM,
      jsdelivr_url: "http://localhost:#{bypass.port}",
      http_timeout: 1_000
    )

    prev_adapter = Application.get_env(:tesla, :adapter)

    Application.put_env(
      :tesla,
      :adapter,
      {Tesla.Adapter.Finch, name: Lightning.Finch}
    )

    on_exit(fn ->
      Application.delete_env(:lightning, Lightning.Adaptors.NPM)

      if prev_adapter do
        Application.put_env(:tesla, :adapter, prev_adapter)
      else
        Application.delete_env(:tesla, :adapter)
      end
    end)

    %{bypass: bypass}
  end

  describe "schema/2" do
    test "returns the decoded schema and a hex sha256 on 200", %{bypass: bypass} do
      schema = %{"type" => "object", "properties" => %{"baseUrl" => %{}}}
      body = Jason.encode!(schema)

      expected_sha =
        :sha256
        |> :crypto.hash(body)
        |> Base.encode16(case: :lower)

      Bypass.expect(bypass, "GET", @path, fn conn ->
        assert conn.request_path == @path
        Plug.Conn.resp(conn, 200, body)
      end)

      assert {^schema, ^expected_sha} = Schema.schema(@package, @version)
    end

    test "returns {nil, nil} on 404", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", @path, fn conn ->
        Plug.Conn.resp(conn, 404, "")
      end)

      assert {nil, nil} = Schema.schema(@package, @version)
    end

    test "returns {nil, nil} on 5xx", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", @path, fn conn ->
        Plug.Conn.resp(conn, 500, "")
      end)

      assert {nil, nil} = Schema.schema(@package, @version)
    end

    test "returns {nil, nil} on invalid JSON body", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", @path, fn conn ->
        Plug.Conn.resp(conn, 200, "this is not json {")
      end)

      assert {nil, nil} = Schema.schema(@package, @version)
    end

    test "returns {nil, nil} on connection refused", %{bypass: bypass} do
      Bypass.down(bypass)
      assert {nil, nil} = Schema.schema(@package, @version)
    end
  end
end
