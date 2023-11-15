defmodule Lightning.Invocation.LogLine do
  @moduledoc """
  Ecto model for run logs.

  Every log line from a worker is stored using this model.

  Currently the `:message` field is a text field, however the worker sends
  messages in a JSON format. We will at some point consider changing this to
  a JSON field; but for now we coerce it into a string.

  See [`LogMessage`](`Lightning.LogMessage`) for more information.
  """
  use Ecto.Schema
  import Ecto.Changeset

  import Lightning.Security, only: [redact_password: 2]

  alias Lightning.Attempt
  alias Lightning.Invocation.Run
  alias Lightning.LogMessage
  alias Lightning.UnixDateTime

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          message: String.t(),
          timestamp: DateTime.t(),
          run: Run.t() | Ecto.Association.NotLoaded.t() | nil,
          attempt: Attempt.t() | Ecto.Association.NotLoaded.t() | nil
        }

  @primary_key false
  @foreign_key_type :binary_id
  schema "log_lines" do
    field :id, Ecto.UUID
    field :source, :string

    field :level, Ecto.Enum,
      values: [:success, :always, :info, :warn, :error, :debug],
      default: :info

    field :message, LogMessage, default: ""

    belongs_to :run, Run
    belongs_to :attempt, Attempt

    field :timestamp, UnixDateTime
  end

  def new(%Attempt{} = attempt, attrs \\ %{}) do
    %__MODULE__{id: Ecto.UUID.generate()}
    |> cast(attrs, [:message, :timestamp, :run_id, :attempt_id, :level, :source])
    |> redact_password(:message)
    |> put_assoc(:attempt, attempt)
    |> validate()
  end

  @doc false
  def changeset(log_line, attrs) do
    log_line
    |> cast(attrs, [:message, :timestamp, :run_id, :attempt_id, :level, :source])
    |> validate()
  end

  def validate(changeset) do
    changeset
    |> validate_required([:message, :timestamp])
    |> validate_length(:source, max: 8)
    |> assoc_constraint(:run)
    |> assoc_constraint(:attempt)
    |> validate_change(:message, fn _, message ->
      if is_nil(message) do
        [message: "can't be nil"]
      else
        []
      end
    end)
  end
end
