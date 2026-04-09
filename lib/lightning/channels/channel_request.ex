defmodule Lightning.Channels.ChannelRequest do
  @moduledoc """
  Schema for a ChannelRequest — tracks the lifecycle of a single proxied
  HTTP request through a channel.
  """
  use Lightning.Schema

  alias Lightning.Channels.Channel
  alias Lightning.Channels.ChannelEvent
  alias Lightning.Channels.ChannelSnapshot
  alias Lightning.Workflows.WebhookAuthMethod

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          channel_id: Ecto.UUID.t(),
          channel_snapshot_id: Ecto.UUID.t(),
          request_id: String.t(),
          client_identity: String.t() | nil,
          client_webhook_auth_method_id: Ecto.UUID.t() | nil,
          client_auth_type: String.t() | nil,
          state: :pending | :success | :failed | :timeout | :error,
          started_at: DateTime.t(),
          completed_at: DateTime.t() | nil
        }

  schema "channel_requests" do
    field :request_id, :string
    field :client_identity, :string
    field :client_auth_type, :string

    field :state, Ecto.Enum,
      values: [:pending, :success, :failed, :timeout, :error]

    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :channel, Channel
    belongs_to :channel_snapshot, ChannelSnapshot
    belongs_to :client_webhook_auth_method, WebhookAuthMethod

    has_many :channel_events, ChannelEvent
  end

  def changeset(request, attrs) do
    request
    |> cast(attrs, [
      :channel_id,
      :channel_snapshot_id,
      :request_id,
      :client_identity,
      :client_webhook_auth_method_id,
      :client_auth_type,
      :state,
      :started_at,
      :completed_at
    ])
    |> validate_required([
      :channel_id,
      :channel_snapshot_id,
      :request_id,
      :state,
      :started_at
    ])
    |> assoc_constraint(:channel)
    |> assoc_constraint(:channel_snapshot)
    |> unique_constraint(:request_id)
  end
end
