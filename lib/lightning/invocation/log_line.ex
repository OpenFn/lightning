defmodule Lightning.Invocation.LogLine do
  @moduledoc """
  Ecto model for run logs.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Lightning.Invocation.Run
  alias Lightning.Attempt
  alias Lightning.UnixDateTime

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          message: String.t(),
          timestamp: DateTime.t(),
          run: Run.t() | Ecto.Association.NotLoaded.t() | nil,
          attempt: Attempt.t() | Ecto.Association.NotLoaded.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "log_lines" do
    field :name, :string

    field :level, Ecto.Enum,
      values: [:info, :warn, :error, :debug],
      default: :info

    field :message, :string, default: ""

    belongs_to :run, Run
    belongs_to :attempt, Attempt

    field :timestamp, UnixDateTime
  end

  def new(%Attempt{} = attempt, attrs \\ %{}) do
    %__MODULE__{id: Ecto.UUID.generate()}
    |> cast(attrs, [:message, :timestamp, :run_id, :attempt_id, :level, :name])
    |> put_assoc(:attempt, attempt)
    |> validate()
  end

  @doc false
  def changeset(log_line, attrs) do
    log_line
    |> cast(attrs, [:message, :timestamp, :run_id, :attempt_id, :level, :name])
    |> validate()
  end

  def validate(changeset) do
    changeset
    |> validate_required([:message, :timestamp])
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
