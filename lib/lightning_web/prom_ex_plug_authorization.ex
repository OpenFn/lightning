defmodule LightningWeb.PromExPlugAuthorization do
  @moduledoc """
  Implement custom authorization for PromEx metrics endpoint as per
  https://hexdocs.pm/prom_ex/1.1.1/PromEx.Plug.html
  """
  @behaviour Unplug.Predicate

  require Logger

  @impl true
  def call(conn, _vars) do
    config = Application.get_env(:lightning, Lightning.PromEx)

    filter_logger(conn, "ip: #{Enum.join(Tuple.to_list(conn.remote_ip), ".")}")
    filter_logger(conn, "token: #{Plug.Conn.get_req_header(conn, "authorization")}")
    filter_logger(conn, "scheme: #{conn.scheme}")
    if config[:metrics_endpoint_authorization_required] do
      valid_token?(
        Plug.Conn.get_req_header(conn, "authorization"),
        config[:metrics_endpoint_token]
      ) &&
        valid_scheme?(
          Atom.to_string(conn.scheme),
          config[:metrics_endpoint_scheme]
        )
    else
      true
    end
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

  defp filter_logger(conn, message) do
    if conn.request_path == "/metrics" do
      Logger.error("ENDPOINT #{message}")
    end
  end
end
