defmodule LightningWeb.ChannelRequestLive.Helpers do
  @moduledoc """
  Error humanization for channel request detail page.

  Provides `humanize_error/1` to convert classified error codes into
  human-readable descriptions, and `error_category/1` to classify errors
  as `:transport` or `:credential`.
  """

  @transport_errors %{
    "nxdomain" =>
      "DNS lookup failed — the destination hostname could not be resolved",
    "econnrefused" =>
      "Connection refused — the destination server is not accepting connections on this port",
    "ehostunreach" => "Host unreachable — no route to the destination server",
    "enetunreach" => "Network unreachable — no network path to the destination",
    "closed" => "Connection closed unexpectedly by the destination",
    "econnreset" => "Connection reset — the destination dropped the connection",
    "econnaborted" => "Connection aborted by the destination",
    "epipe" =>
      "Broken pipe — the destination closed the connection while data was being sent",
    "connect_timeout" =>
      "Connection timed out — the destination server did not respond to the connection attempt",
    "response_timeout" =>
      "Response timed out — the destination accepted the connection but did not send a response in time",
    "timeout" => "Request timed out"
  }

  @credential_errors %{
    "credential_missing_auth_fields" =>
      "The configured credential is missing required authentication fields",
    "credential_environment_not_found" =>
      "The credential environment could not be found",
    "oauth_refresh_failed" =>
      "OAuth token refresh failed — the destination credential could not be renewed",
    "oauth_reauthorization_required" =>
      "OAuth credential needs to be re-authorized by a user"
  }

  @doc """
  Converts a classified error code into a human-readable description.
  Unknown codes pass through unchanged.
  """
  @spec humanize_error(String.t()) :: String.t()
  def humanize_error(code) when is_binary(code) do
    cond do
      Map.has_key?(@transport_errors, code) ->
        Map.fetch!(@transport_errors, code)

      Map.has_key?(@credential_errors, code) ->
        Map.fetch!(@credential_errors, code)

      String.starts_with?(code, "unsupported_credential_schema:") ->
        name = String.replace_prefix(code, "unsupported_credential_schema:", "")

        "Unsupported credential type \"#{name}\" — this credential schema cannot be used for destination auth"

      true ->
        code
    end
  end

  @doc """
  Classifies an error code as `:transport`, `:credential`, or `nil` (unknown).
  """
  @spec error_category(String.t()) :: :transport | :credential | nil
  def error_category(code) when is_binary(code) do
    cond do
      Map.has_key?(@transport_errors, code) ->
        :transport

      Map.has_key?(@credential_errors, code) ->
        :credential

      String.starts_with?(code, "unsupported_credential_schema:") ->
        :credential

      true ->
        nil
    end
  end
end
