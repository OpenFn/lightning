defmodule Lightning.Accounts.Notification do
  @moduledoc """
  Model for storing notifications
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Lightning.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "notifications" do
    field :event, :string
    field :metadata, :map
    belongs_to :user, User

    timestamps(updated_at: false)
  end

  @doc false
  def changeset(%__MODULE__{} = audit, attrs) do
    audit
    |> cast(attrs, [:event, :user_id, :metadata])
    |> validate_required([:event, :user_id])
  end
end
