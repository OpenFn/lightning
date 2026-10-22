defmodule LightningWeb.ChannelRequestLive.Helpers do
  @moduledoc """
  What the channel request page's props need from the server: the event it
  shows, and the names of the auth method and credential the request used,
  which only the preloaded associations know.
  """

  @doc """
  Extracts the primary event from a channel request's events list.
  Prefers `:destination_response`, falls back to `:error`.
  """
  def primary_event(channel_request) do
    channel_request.channel_events
    |> Enum.find(&(&1.type == :destination_response)) ||
      Enum.find(channel_request.channel_events, &(&1.type == :error))
  end

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
end
