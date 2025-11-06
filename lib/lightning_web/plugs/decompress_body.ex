defmodule LightningWeb.Plugs.DecompressBody do
  @moduledoc """
  A Plug body reader that decompresses gzipped request bodies. Checks for the `Content-Encoding: gzip` header and automatically
  decompresses the request body before it's passed to the JSON parser.
  """
  def read_body(conn, opts) do
    case Plug.Conn.get_req_header(conn, "content-encoding") do
      ["gzip" | _] ->
        case Plug.Conn.read_body(conn, opts) do
          {:ok, body, conn} ->
            {:ok, :zlib.gunzip(body), conn}

          other ->
            other
        end

      _ ->
        Plug.Conn.read_body(conn, opts)
    end
  end
end
