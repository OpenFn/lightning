# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Lightning.Repo.insert!(%Lightning.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

Lightning.Accounts.register_admin(%{
  email: "admin@openfn.org",
  password: "123456789abc",
  password_confirmation: "123456789abc"
})

Lightning.Accounts.register_user(%{
  email: "user1@openfn.org",
  password: "123456789abc",
  password_confirmation: "123456789abc"
})

Lightning.Accounts.register_user(%{
  email: "user2@openfn.org",
  password: "123456789abc",
  password_confirmation: "123456789abc"
})
