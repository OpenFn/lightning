defmodule Lightning.Accounts.UserIdentity do
  @moduledoc """
  Schema for tracking SSO provider identities linked to user accounts.

  A user has at most one identity per provider, and the combination of provider
  and uid is globally unique (an identity can't be claimed by two users).
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
    |> unique_constraint([:user_id, :provider],
      message: "is already linked to a different account for this provider"
    )
  end
end
