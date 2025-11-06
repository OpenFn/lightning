defmodule LightningWeb.Plugs.DecompressBody do
  @moduledoc """
  A Plug body reader that decompresses gzipped request bodies.

  This plug checks for the `Content-Encoding: gzip` header and automatically
  decompresses the request body before it's passed to the JSON parser.

  ## Usage

  Add this as a body_reader option to Plug.Parsers:

      plug Plug.Parsers,
        parsers: [:json],
        body_reader: {LightningWeb.Plugs.DecompressBody, :read_body, []}

  """

  @doc """
  Reads and optionally decompresses the request body based on Content-Encoding header.

  If the `content-encoding` header is set to `gzip`, the body will be decompressed
  using `:zlib.gunzip/1`. Otherwise, the body is read normally without modification.

  ## Parameters

    * `conn` - The `Plug.Conn` struct
    * `opts` - Options passed to `Plug.Conn.read_body/2`

  ## Returns

    * `{:ok, body, conn}` - The decompressed (or original) body and updated connection
    * `{:more, partial_body, conn}` - For chunked requests (passed through from read_body)
    * `{:error, term}` - If reading fails

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
