defmodule Lightning.InvocationReason do
  @moduledoc """
  Ecto model for InvocationReasons.

  """
  use Ecto.Schema
  import Ecto.Changeset
  alias Lightning.Invocation.{Run, Dataclip}
  alias Lightning.Workflows.Trigger
  alias Lightning.Accounts.User

  @source_types [:manual, :webhook, :cron, :retry]
  @type source_type :: unquote(Enum.reduce(@source_types, &{:|, [], [&1, &2]}))

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          type: source_type(),
          dataclip: Dataclip.t() | Ecto.Association.NotLoaded.t() | nil,
          run: Run.t() | Ecto.Association.NotLoaded.t() | nil,
          trigger: Trigger.t() | Ecto.Association.NotLoaded.t() | nil,
          user: User.t() | Ecto.Association.NotLoaded.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "invocation_reasons" do
    field :type, Ecto.Enum, values: @source_types
    belongs_to :run, Run
    belongs_to :user, User
    belongs_to :trigger, Trigger
    belongs_to :dataclip, Dataclip

    timestamps(type: :utc_datetime)
  end

  @spec new(attrs :: %{optional(atom()) => any()}) ::
          Ecto.Changeset.t(__MODULE__.t())
  def new(attrs \\ %{}) do
    change(%__MODULE__{}, %{id: Ecto.UUID.generate()})
    |> change(attrs)
    |> validate()
  end

  @doc false
  def changeset(reason, attrs) do
    reason
    |> cast(attrs, [:type, :run_id, :dataclip_id, :user_id, :trigger_id])
    |> validate_required([:type, :dataclip_id])
    |> validate()
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

      type when type in [:manual, :retry] ->
        changeset
        |> validate_required([:user_id])

      _ ->
        changeset
    end
  end

  defp validate(changeset) do
    changeset
    |> validate_inclusion(:type, @source_types)
    |> assoc_constraint(:run)
    |> assoc_constraint(:user)
    |> assoc_constraint(:dataclip)
    |> validate_by_trigger_type()
  end
end
