defmodule LightningWeb.Plugs.MetricsAuth do
  @moduledoc """
  Implements Bearer token authorization for /metrics endpoint that is managed by
  PromEx.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if metrics_path?(conn) && authorization_required?() do
      if valid_token?(auth_header(conn)) && valid_scheme?(conn) do
        conn
      else
        halt_as_unauthorized(conn)
      end
    else
      conn
    end
  end

  defp metrics_path?(conn) do
    conn.path_info == ["metrics"]
  end

  defp authorization_required? do
    Lightning.Config.promex_metrics_endpoint_authorization_required?()
  end

  defp auth_header(conn) do
    Plug.Conn.get_req_header(conn, "authorization")
  end

  defp valid_token?(["Bearer " <> provided_token]) do
    expected_token = Lightning.Config.promex_metrics_endpoint_token()
    Plug.Crypto.secure_compare(provided_token, expected_token)
  end

  defp valid_token?(_auth_header) do
    false
  end

  defp valid_scheme?(conn) do
    provided_scheme = Atom.to_string(conn.scheme)
    expected_scheme = Lightning.Config.promex_metrics_endpoint_scheme()
    provided_scheme == expected_scheme
  end

  defp halt_as_unauthorized(conn) do
    conn
    |> put_resp_header("www-authenticate", "Bearer")
    |> send_resp(401, "Unauthorized")
    |> halt()
  end
end
