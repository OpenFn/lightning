defmodule Lightning.Channels.ChannelEvent do
  @moduledoc """
  Schema for a ChannelEvent — a detailed log entry recording HTTP
  request/response data for a channel request.

  ## Event Types

  - `:destination_response` — emitted by `Handler.persist_completion/2` on
    successful upstream proxy completion. Carries all fields
    (request/response details, latency, ttfb).
  - `:error` — emitted by `Handler.persist_completion/2` on upstream proxy
    error, or by `ChannelProxyPlug.record_credential_error/2` when destination
    credential resolution fails before proxying. Carries request fields and
    `error_message`; response fields may be nil.
  """
  use Lightning.Schema

  alias Lightning.Channels.ChannelRequest

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          channel_request_id: Ecto.UUID.t(),
          type: :destination_response | :error,
          request_method: String.t() | nil,
          request_path: String.t() | nil,
          request_query_string: String.t() | nil,
          request_headers: list() | nil,
          request_body_preview: String.t() | nil,
          request_body_hash: String.t() | nil,
          request_body_size: integer() | nil,
          response_status: integer() | nil,
          response_headers: list() | nil,
          response_body_preview: String.t() | nil,
          response_body_hash: String.t() | nil,
          response_body_size: integer() | nil,
          latency_us: integer() | nil,
          ttfb_us: integer() | nil,
          request_send_us: integer() | nil,
          response_duration_us: integer() | nil,
          queue_us: integer() | nil,
          connect_us: integer() | nil,
          reused_connection: boolean() | nil,
          error_message: String.t() | nil,
          inserted_at: DateTime.t()
        }

  schema "channel_events" do
    field :type, Ecto.Enum, values: [:destination_response, :error]

    field :request_method, :string
    field :request_path, :string
    field :request_query_string, :string
    field :request_headers, {:array, {:array, :string}}
    field :request_body_preview, :string
    field :request_body_hash, :string
    field :request_body_size, :integer

    field :response_status, :integer
    field :response_headers, {:array, {:array, :string}}
    field :response_body_preview, :string
    field :response_body_hash, :string
    field :response_body_size, :integer

    field :latency_us, :integer
    field :ttfb_us, :integer
    field :request_send_us, :integer
    field :response_duration_us, :integer
    field :queue_us, :integer
    field :connect_us, :integer
    field :reused_connection, :boolean
    field :error_message, :string

    belongs_to :channel_request, ChannelRequest

    timestamps(updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(
      attrs,
      [
        :channel_request_id,
        :type,
        :request_method,
        :request_path,
        :request_query_string,
        :request_headers,
        :request_body_preview,
        :request_body_hash,
        :request_body_size,
        :response_status,
        :response_headers,
        :response_body_preview,
        :response_body_hash,
        :response_body_size,
        :latency_us,
        :ttfb_us,
        :request_send_us,
        :response_duration_us,
        :queue_us,
        :connect_us,
        :reused_connection,
        :error_message
      ],
      empty_values: []
    )
    |> validate_required([:channel_request_id, :type])
    |> assoc_constraint(:channel_request)
  end
end
