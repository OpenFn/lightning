defmodule Lightning.Accounts.UserTOTP do
  @moduledoc """
  User Time based OTPs schema
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users_totps" do
    field :secret, :binary, redact: true
    field :code, :string, virtual: true
    belongs_to :user, Lightning.Accounts.User

    timestamps()
  end

  def changeset(totp, attrs) do
    totp
    |> cast(attrs, [:code])
    |> validate_required([:code, :secret])
    |> validate_format(:code, ~r/^\d{6}$/, message: "should be a 6 digit number")
    |> maybe_validate_code()
  end

  defp maybe_validate_code(changeset) do
    code = get_field(changeset, :code)
    secret = get_field(changeset, :secret)

    if changeset.valid? and NimbleTOTP.valid?(secret, code) do
      changeset
    else
      add_error(changeset, :code, "invalid code")
    end
  end
end
