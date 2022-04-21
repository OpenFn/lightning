defmodule Lightning.Invocation.Dataclip do
  @moduledoc """
  Ecto model for Dataclips.

  Dataclips represent some data that arrived in the system, and records both
  the data and the source of the data.

  ## Types

  * `:http_request`
    The data arrived via a webhook.
  * `:global`
    Was created manually, and is intended to be used multiple times.
    When repetitive static data is needed to be maintained, instead of hard-coding
    into a Job - a more convenient solution is to create a `:global` Dataclip
    and access it inside the Job.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Lightning.Invocation.Run

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          body: %{} | nil,
          run_id: Ecto.UUID.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "dataclips" do
    field :body, :map
    field :type, Ecto.Enum, values: [:http_request, :global, :run_result]
    belongs_to :run, Run

    timestamps(usec: true)
  end

  @doc false
  def changeset(dataclip, attrs) do
    dataclip
    |> cast(attrs, [:body, :type, :run_id])
    |> validate_required([:body, :type])
    |> validate_by_type()
  end

  @doc """
  Append validations based on the type of the Dataclip.

  - `:run_result` must have an associated Run model.
  """
  def validate_by_type(changeset) do
    changeset
    |> fetch_field!(:type)
    |> case do
      :run_result ->
        changeset
        |> validate_required(:run_id)
        |> assoc_constraint(:run)

      _ ->
        changeset
    end
  end
end
