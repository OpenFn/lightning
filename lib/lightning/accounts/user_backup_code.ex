defmodule Lightning.Accounts.UserBackupCode do
  @moduledoc """
  User backup codes schema
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_backup_codes" do
    field :code, Lightning.Encrypted.Binary,
      redact: true,
      autogenerate: {__MODULE__, :generate_backup_code, []}

    field :used_at, :utc_datetime_usec
    belongs_to :user, Lightning.Accounts.User

    timestamps()
  end

  def changeset(backup_code, attrs) do
    backup_code
    |> cast(attrs, [:used_at])
    |> unique_constraint([:user_id, :code])
  end

  def generate_backup_code do
    # We replace the letter O by X to avoid confusion with zero.
    :crypto.strong_rand_bytes(9)
    |> Base.encode32()
    |> binary_part(0, 9)
    |> String.replace("O", "X")
  end
end
