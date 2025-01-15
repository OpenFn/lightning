defmodule LightningWeb.Plugs.MetricsAuth do
  import Plug.Conn

  def call(conn, _opts) do
    if metrics_path?(conn) && authorization_required?() do
      if valid_token?(
        Plug.Conn.get_req_header(conn, "authorization"),
        Lightning.Config.promex_metrics_endpoint_token
      ) &&
        valid_scheme?(
          Atom.to_string(conn.scheme),
          Lightning.Config.promex_metrics_endpoint_scheme
        ) do
        conn
      else
        conn
        |> put_resp_header("www-authenticate", "Bearer")
        |> send_resp(401, "Unauthorized")
        |> halt()
      end
    else
      conn
    end
  end

  defp metrics_path?(conn) do
    conn.path_info == ["metrics"]
  end

  defp authorization_required? do
    Lightning.Config.promex_metrics_endpoint_authorization_required?
  end

  defp valid_token?(["Bearer " <> provided_token], expected_token) do
    Plug.Crypto.secure_compare(provided_token, expected_token)
  end

  defp valid_token?(_auth_header, _expected_token) do
    false
  end

  defp valid_scheme?(provided_scheme, expected_scheme) do
    provided_scheme == expected_scheme
  end
end
