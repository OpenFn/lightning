defmodule Lightning.Channels.PersistencePolicy do
  @moduledoc """
  Decides whether channel request/event payload fields are persisted, based on
  the project's `retention_policy`. PII fields are dropped from the attrs map
  before insert when `persist_observations?` is false, and the resulting
  `ChannelRequest` is marked `is_wiped: true` so the UI can render the
  wiped-payload affordance.
  """

  alias Lightning.Projects

  @event_fields ~w(
    request_path request_query_string
    request_headers request_body_preview request_body_hash
    response_headers response_body_preview response_body_hash
  )a

  @request_fields [:client_identity]

  @spec persist_observations?(Ecto.UUID.t()) :: boolean()
  def persist_observations?(project_id), do: Projects.save_dataclips?(project_id)

  @spec wipe_request_attrs(map(), persist_observations: boolean()) :: map()
  def wipe_request_attrs(attrs, persist_observations: true), do: attrs

  def wipe_request_attrs(attrs, persist_observations: false) do
    attrs
    |> Map.drop(@request_fields)
    |> Map.put(:is_wiped, true)
  end

  @spec wipe_event_attrs(map(), persist_observations: boolean()) :: map()
  def wipe_event_attrs(attrs, persist_observations: true), do: attrs

  def wipe_event_attrs(attrs, persist_observations: false) do
    Map.drop(attrs, @event_fields)
  end
end
