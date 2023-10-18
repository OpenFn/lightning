defmodule Lightning.Accounts.UserTOTP do
  @moduledoc """
  User Time based OTPs schema
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          secret: String.t() | nil,
          code: String.t() | nil,
          user:
            Lightning.Accounts.User.t() | Ecto.Association.NotLoaded.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_totps" do
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
    |> maybe_validate_code(totp)
  end

  defp maybe_validate_code(changeset, totp) do
    code = get_field(changeset, :code)

    if changeset.valid? and valid_totp?(totp, code) do
      changeset
    else
      add_error(changeset, :code, "invalid code")
    end
  end

  def valid_totp?(totp, code) do
    is_struct(totp, __MODULE__) and is_binary(code) and byte_size(code) == 6 and
      NimbleTOTP.valid?(totp.secret, code)
  end
end
