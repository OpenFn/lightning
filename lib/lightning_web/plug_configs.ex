defmodule LightningWeb.PlugConfigs do
  @moduledoc """
  Dynamically initialize Plugs that don't accept dynamic configs in :prod ENV.
  """

  @spec plug_parsers() :: Keyword.t()
  def plug_parsers do
    [
      parsers: [
        :urlencoded,
        :multipart,
        {
          :json,
          length: Application.fetch_env!(:lightning, :max_dataclip_size_bytes)
        }
      ],
      pass: ["*/*"],
      body_reader: {__MODULE__, :decompress_body, []},
      json_decoder: Phoenix.json_library()
    ]
  end

  @doc """
  Custom body reader that decompresses gzipped request bodies.
  """
  def decompress_body(conn, opts) do
    case Plug.Conn.get_req_header(conn, "content-encoding") do
      ["gzip" | _] ->
        {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
        {:ok, :zlib.gunzip(body), conn}

      _ ->
        Plug.Conn.read_body(conn, opts)
    end
  end
end
