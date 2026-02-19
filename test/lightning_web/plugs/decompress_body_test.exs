defmodule LightningWeb.Plugs.DecompressBodyTest do
  use LightningWeb.ConnCase, async: true

  alias LightningWeb.Plugs.DecompressBody

  describe "read_body/2" do
    test "decompresses gzipped request body", %{conn: conn} do
      json_data = %{"traitors" => ["alan"], "faithfuls" => ["david"]}
      json_string = Jason.encode!(json_data)

      # Compress the JSON string
      gzipped_body = :zlib.gzip(json_string)

      # Simulate a connection with gzipped body
      conn =
        conn
        |> put_req_header("content-encoding", "gzip")
        |> Map.put(:body_params, %{})

      # Mock the body reading by setting adapter data
      conn = %{
        conn
        | adapter: {Plug.Adapters.Test.Conn, %{chunks: [gzipped_body]}}
      }

      # Call the decompress function
      {:ok, decompressed_body, _conn} = DecompressBody.read_body(conn, [])

      assert decompressed_body == json_string
    end

    test "passes through non-gzipped request body", %{conn: conn} do
      json_data = %{"traitors" => ["alan"], "faithfuls" => ["david"]}
      json_string = Jason.encode!(json_data)

      # Simulate a connection without compression
      conn =
        conn
        |> Map.put(:body_params, %{})

      # Mock the body reading
      conn = %{
        conn
        | adapter: {Plug.Adapters.Test.Conn, %{chunks: [json_string]}}
      }

      # Call the read_body function (should just read normally)
      {:ok, body, _conn} = DecompressBody.read_body(conn, [])

      assert body == json_string
    end

    test "handles multiple content-encoding headers", %{conn: conn} do
      json_string = Jason.encode!(%{"test" => "data"})
      gzipped_body = :zlib.gzip(json_string)

      # Multiple headers with gzip first
      conn =
        conn
        |> put_req_header("content-encoding", "gzip")
        |> put_req_header("content-encoding", "identity")
        |> Map.put(:body_params, %{})

      conn = %{
        conn
        | adapter: {Plug.Adapters.Test.Conn, %{chunks: [gzipped_body]}}
      }

      {:ok, decompressed_body, _conn} = DecompressBody.read_body(conn, [])

      assert decompressed_body == json_string
    end
  end
end
