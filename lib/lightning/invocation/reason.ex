defmodule Lightning.InvocationReason do
  @moduledoc """
  Ecto model for InvocationReasons.


  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Lightning.Invocation.{Run, Dataclip}
  alias Lightning.Jobs.Trigger
  alias Lightning.Accounts.User

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          type: atom(),
          dataclip: Dataclip.t() | Ecto.Association.NotLoaded.t() | nil,
          run: Run.t() | Ecto.Association.NotLoaded.t() | nil,
          trigger: Trigger.t() | Ecto.Association.NotLoaded.t() | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil
        }

  @source_types [:webhook, :cron, :flow, :retry]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "invocation_reasons" do
    field :type, Ecto.Enum, values: @source_types
    belongs_to :run, Run
    belongs_to :user, User
    belongs_to :trigger, Trigger
    belongs_to :dataclip, Dataclip

    timestamps()
  end

  @doc false
  def changeset(reason, attrs) do
    reason
    |> cast(attrs, [:type, :run_id, :dataclip_id, :user_id, :trigger_id])
    |> validate_required([:type, :dataclip_id])
    |> validate_inclusion(:type, @source_types)
    |> assoc_constraint(:run)
    |> assoc_constraint(:user)
    |> assoc_constraint(:dataclip)
    |> validate_by_trigger_type()
  end

  # - `:cron` must have an associated trigger.
  # - `:webhook` must have an associated trigger.

  def validate_by_trigger_type(changeset) do
    changeset
    |> fetch_field!(:type)
    |> case do
      type when type in [:webhook, :cron] ->
        changeset
        |> validate_required([:trigger_id])
        |> assoc_constraint(:trigger)

      _ ->
        changeset
    end
  end
end
