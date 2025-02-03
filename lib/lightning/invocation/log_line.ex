defmodule Lightning.Invocation.LogLine do
  @moduledoc """
  Ecto model for run logs.

  Every log line from a worker is stored using this model.

  Currently the `:message` field is a text field, however the worker sends
  messages in a JSON format. We will at some point consider changing this to
  a JSON field; but for now we coerce it into a string.

  See [`LogMessage`](`Lightning.LogMessage`) for more information.
  """
  use Lightning.Schema

  alias Lightning.Invocation.Step
  alias Lightning.LogMessage
  alias Lightning.Run
  alias Lightning.Scrubber
  alias Lightning.UnixDateTime

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          message: String.t(),
          timestamp: DateTime.t(),
          step: Step.t() | Ecto.Association.NotLoaded.t() | nil,
          run: Run.t() | Ecto.Association.NotLoaded.t() | nil
        }

  @derive {Jason.Encoder,
           only: [:id, :source, :level, :message, :timestamp, :step_id, :run_id]}

  @primary_key false
  schema "log_lines" do
    field :id, Ecto.UUID
    field :source, :string

    field :level, Ecto.Enum,
      values: [:success, :always, :info, :warn, :error, :debug],
      default: :info

    field :message, LogMessage, default: nil

    belongs_to :step, Step
    belongs_to :run, Run

    field :timestamp, UnixDateTime
  end

  def new(%Run{} = run, attrs \\ %{}, scrubber) do
    %__MODULE__{id: Ecto.UUID.generate()}
    |> cast(attrs, [:message, :timestamp, :step_id, :run_id, :level, :source],
      empty_values: [[], nil]
    )
    |> put_assoc(:run, run)
    |> validate(scrubber)
  end

  def validate(changeset, scrubber \\ nil) do
    changeset
    |> validate_required([:timestamp])
    |> validate_length(:source, max: 8)
    |> assoc_constraint(:step)
    |> assoc_constraint(:run)
    |> then(fn changeset ->
      fetch_field(changeset, :message)
      |> case do
        {:changes, message} when message in [nil, [nil]] ->
          add_error(changeset, :message, "can't be blank")

        {:data, message} when is_nil(message) ->
          add_error(changeset, :message, "can't be blank")

        _ ->
          changeset
      end
    end)
    |> scrub_message(scrubber)
  end

  defp scrub_message(%Ecto.Changeset{valid?: true} = changeset, scrubber)
       when scrubber != nil do
    case fetch_change(changeset, :message) do
      :error ->
        changeset

      {:ok, message} ->
        scrubbed_message = Scrubber.scrub(scrubber, message)
        put_change(changeset, :message, scrubbed_message)
    end
  end

  defp scrub_message(changeset, _scrubber), do: changeset
end
