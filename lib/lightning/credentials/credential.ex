defmodule Lightning.Credentials.Credential do
  @moduledoc """
  The Credential model.
  """
  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          body: nil | %{}
        }

  use Ecto.Schema
  alias Lightning.Accounts.User
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "credentials" do
    field :body, :map
    field :name, :string
    belongs_to :user, User

    timestamps()
  end

  @doc false
  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:name, :body, :user_id])
    |> validate_required([:name, :body, :user_id])
    |> assoc_constraint(:user)
  end
end
