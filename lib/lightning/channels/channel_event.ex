defmodule Lightning.Channels.ChannelEvent do
  use Lightning.Schema

  alias Lightning.Channels.ChannelRequest

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          channel_request_id: Ecto.UUID.t(),
          type: :source_received | :sink_request | :sink_response | :error,
          request_method: String.t() | nil,
          request_path: String.t() | nil,
          request_headers: String.t() | nil,
          request_body_preview: String.t() | nil,
          request_body_hash: String.t() | nil,
          response_status: integer() | nil,
          response_headers: String.t() | nil,
          response_body_preview: String.t() | nil,
          response_body_hash: String.t() | nil,
          latency_ms: integer() | nil,
          error_message: String.t() | nil,
          inserted_at: DateTime.t()
        }

  schema "channel_events" do
    field :type, Ecto.Enum,
      values: [:source_received, :sink_request, :sink_response, :error]

    field :request_method, :string
    field :request_path, :string
    field :request_headers, :string
    field :request_body_preview, :string
    field :request_body_hash, :string

    field :response_status, :integer
    field :response_headers, :string
    field :response_body_preview, :string
    field :response_body_hash, :string

    field :latency_ms, :integer
    field :error_message, :string

    belongs_to :channel_request, ChannelRequest

    timestamps(updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :channel_request_id,
      :type,
      :request_method,
      :request_path,
      :request_headers,
      :request_body_preview,
      :request_body_hash,
      :response_status,
      :response_headers,
      :response_body_preview,
      :response_body_hash,
      :latency_ms,
      :error_message
    ])
    |> validate_required([:channel_request_id, :type])
    |> assoc_constraint(:channel_request)
  end
end
