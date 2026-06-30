defmodule Lightning.Repo.Migrations.EnforceOneIdentityPerProvider do
  use Ecto.Migration

  # A user may link at most one identity per provider. The composite unique
  # index also serves lookups by `user_id` (leftmost prefix), so the standalone
  # `user_id` index becomes redundant.
  def change do
    drop index(:user_identities, [:user_id])

    create unique_index(:user_identities, [:user_id, :provider])
  end
end
