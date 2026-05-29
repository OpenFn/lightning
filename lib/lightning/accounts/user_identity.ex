defmodule Lightning.Accounts.UserIdentity do
  @moduledoc """
  Schema for tracking SSO provider identities linked to user accounts.

  A user may have multiple identities (one per SSO provider). The combination
  of provider and uid is globally unique.
  """
  use Lightning.Schema

  alias Lightning.Accounts.User

  schema "user_identities" do
    field :provider, :string
    field :uid, :string
    belongs_to :user, User
    timestamps()
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [:provider, :uid, :user_id])
    |> validate_required([:provider, :uid, :user_id])
    |> unique_constraint([:provider, :uid])
  end
end
