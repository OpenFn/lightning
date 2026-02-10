defmodule Lightning.Channels.ChannelRequest do
  use Lightning.Schema

  alias Lightning.Channels.Channel
  alias Lightning.Channels.ChannelEvent
  alias Lightning.Channels.ChannelSnapshot

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          channel_id: Ecto.UUID.t(),
          channel_snapshot_id: Ecto.UUID.t(),
          request_id: String.t(),
          client_identity: String.t() | nil,
          state: :pending | :success | :failed | :timeout | :error,
          started_at: DateTime.t(),
          completed_at: DateTime.t() | nil
        }

  schema "channel_requests" do
    field :request_id, :string
    field :client_identity, :string

    field :state, Ecto.Enum,
      values: [:pending, :success, :failed, :timeout, :error]

    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    belongs_to :channel, Channel
    belongs_to :channel_snapshot, ChannelSnapshot

    has_many :channel_events, ChannelEvent
  end

  def changeset(request, attrs) do
    request
    |> cast(attrs, [
      :channel_id,
      :channel_snapshot_id,
      :request_id,
      :client_identity,
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
