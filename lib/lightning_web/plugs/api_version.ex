defmodule LightningWeb.Plugs.ApiVersion do
  @moduledoc """
  Resolves the API version for a request from the `x-api-version` header and
  stores it in `conn.assigns[:api_version]`.

  Missing header or `"1"` resolves to `:v1`. `"2"` resolves to `:v2`. Any other
  value is rejected with a 400 Bad Request so that unsupported versions fail
  loudly instead of silently falling back.
  """
  use Phoenix.Controller
  import Plug.Conn

  @supported ~w(1 2)

  @type version :: :v1 | :v2

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case get_req_header(conn, "x-api-version") do
      [] -> assign(conn, :api_version, :v1)
      ["1"] -> assign(conn, :api_version, :v1)
      ["2"] -> assign(conn, :api_version, :v2)
      [value] -> reject(conn, value)
      _many -> reject(conn, "multiple")
    end
  end

  defp reject(conn, value) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error:
        "Unsupported API version: #{inspect(value)}. Supported versions: #{Enum.join(@supported, ", ")}."
    })
    |> halt()
  end
end
