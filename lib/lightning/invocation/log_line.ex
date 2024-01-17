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

  alias Lightning.Attempt
  alias Lightning.Invocation.Run
  alias Lightning.LogMessage
  alias Lightning.Scrubber
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

  def new(%Attempt{} = attempt, attrs \\ %{}, scrubber) do
    %__MODULE__{id: Ecto.UUID.generate()}
    |> cast(attrs, [:message, :timestamp, :run_id, :attempt_id, :level, :source])
    |> put_assoc(:attempt, attempt)
    |> validate(scrubber)
  end

  def validate(changeset, scrubber \\ nil) do
    changeset
    |> validate_required([:message, :timestamp])
    |> validate_length(:source, max: 8)
    |> assoc_constraint(:run)
    |> assoc_constraint(:attempt)
    |> validate_change(:message, fn _, message ->
      # cast converts [nil] into "null"
      if message == "null" do
        [message: "This field can't be blank."]
      else
        []
      end
    end)
    |> maybe_scrub(scrubber)
  end

  defp maybe_scrub(%Ecto.Changeset{valid?: true} = changeset, scrubber)
       when scrubber != nil do
    {:ok, message} = fetch_change(changeset, :message)
    scrubbed = Scrubber.scrub(scrubber, message)
    put_change(changeset, :message, scrubbed)
  end

  defp maybe_scrub(changeset, _scrubber), do: changeset
end
