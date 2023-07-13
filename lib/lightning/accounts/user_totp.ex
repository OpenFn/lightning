defmodule Lightning.Accounts.UserTOTP do
  @moduledoc """
  User Time OTPs schema
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users_totps" do
    field :secret, :binary
    belongs_to :user, Lightning.Accounts.User

    timestamps()
  end
end
