defmodule LightningWeb.ChannelRequestLive.Helpers do
  @moduledoc """
  Shared helper functions for the channel request detail page.

  Pure functions only — no templates. Provides error humanization,
  formatting utilities, and data extraction used across multiple
  component modules.
  """

  # --- Error humanization ---

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

  # --- Data extraction ---

  @doc """
  Extracts the primary event from a channel request's events list.
  Prefers `:destination_response`, falls back to `:error`.
  """
  def primary_event(channel_request) do
    channel_request.channel_events
    |> Enum.find(&(&1.type == :destination_response)) ||
      Enum.find(channel_request.channel_events, &(&1.type == :error))
  end

  # --- Formatting ---

  def format_auth_type(nil), do: "None"
  def format_auth_type("api"), do: "API key"
  def format_auth_type("basic"), do: "Basic auth"
  def format_auth_type(type), do: type

  @doc """
  Formats the client auth method used for a channel request for display.

  Returns `"<name> (<auth type>)"` when the matched method is present,
  `"(deleted) (<auth type>)"` when the id is set but the association is
  `nil` after preload (method deleted after the request ran), and the raw
  auth type / `"None"` when no client auth was configured for the request.
  """
  def format_client_auth(%{client_webhook_auth_method_id: nil} = channel_request) do
    format_auth_type(channel_request.client_auth_type)
  end

  def format_client_auth(
        %{client_webhook_auth_method: %{name: name}} = channel_request
      ) do
    "#{name} (#{format_auth_type(channel_request.client_auth_type)})"
  end

  def format_client_auth(channel_request) do
    "(deleted) (#{format_auth_type(channel_request.client_auth_type)})"
  end

  @doc """
  Formats the destination credential used for a channel request for display.

  Returns the credential name when present, `"(deleted)"` when the id is
  still set but the credential has been deleted, and `"None"` when no
  destination credential was configured.
  """
  def format_destination_auth(%{destination_credential_id: nil}), do: "None"

  def format_destination_auth(%{
        destination_credential: %{credential: %{name: name}}
      }),
      do: name

  def format_destination_auth(_channel_request), do: "(deleted)"

  def format_bytes(nil), do: "—"

  def format_bytes(bytes) when bytes < 1024,
    do: "#{bytes} B"

  def format_bytes(bytes) when bytes < 1_048_576,
    do: "#{Float.round(bytes / 1024, 1)} KB"

  def format_bytes(bytes),
    do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  def format_us(nil), do: "—"

  def format_us(us) when is_number(us) do
    ms = us / 1000

    if ms == Float.round(ms),
      do: trunc(ms) |> to_string(),
      else: Float.round(ms, 1) |> to_string()
  end

  # --- Content type utilities ---

  def extract_content_type(nil), do: nil

  def extract_content_type(headers) do
    headers
    |> Enum.find(fn [name, _] -> String.downcase(name) == "content-type" end)
    |> case do
      [_, value] -> value
      nil -> nil
    end
  end

  def text_content_type?(ct) do
    String.contains?(ct, "text/") or
      String.contains?(ct, "json") or
      String.contains?(ct, "xml") or
      String.contains?(ct, "javascript") or
      String.contains?(ct, "html")
  end

  def format_content_type_label(ct) when is_binary(ct) do
    cond do
      String.contains?(ct, "json") -> "JSON"
      String.contains?(ct, "xml") -> "XML"
      String.contains?(ct, "html") -> "HTML"
      String.contains?(ct, "text/") -> "TEXT"
      true -> ct
    end
  end

  def format_content_type_label(_), do: nil
end
