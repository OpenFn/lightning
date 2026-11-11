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

[admin | others] =
  for {email, first_name, last_name} <- [
        {"admin@openfn.org", "Admin", "User"},
        {"user1@openfn.org", "First", "User"},
        {"user2@openfn.org", "Second", "User"}
      ] do
    {:ok, user} =
      Lightning.Accounts.register_user(%{
        email: email,
        first_name: first_name,
        last_name: last_name,
        password: "123456789abc",
        password_confirmation: "123456789abc"
      })

    user
  end

# An organization for them to belong to: the migration that makes one runs
# before there's anyone to put in it.
{:ok, _organization} =
  Lightning.Organizations.create_organization(
    %{name: "Default organization"},
    [
      %{user: admin, role: :admin}
      | Enum.map(others, &%{user: &1, role: :member})
    ],
    admin
  )
