defmodule Lightning.Credentials.Credential do
  @moduledoc """
  The Credential model.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "credentials" do
    field :body, :map
    field :name, :string

    timestamps()
  end

  @doc false
  def changeset(credential, attrs) do
    credential
    |> cast(attrs, [:name, :body])
    |> validate_required([:name, :body])
  end
end
