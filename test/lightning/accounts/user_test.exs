defmodule Lightning.Accounts.UserTest do
  use Lightning.DataCase, async: true

  alias Lightning.Accounts.User

  describe "password validation" do
    test "it allows passwords between 12 and 72 characters" do
      changeset =
        User.password_changeset(%User{}, %{password: "12345678"})

      refute changeset.valid?

      assert {:password,
              {"should be at least %{count} character(s)",
               [count: 12, validation: :length, kind: :min, type: :string]}} in changeset.errors

      changeset =
        User.password_changeset(%User{}, %{password: "123456789abc"})

      assert changeset.valid?

      changeset =
        User.password_changeset(%User{}, %{
          password: String.duplicate(".", 72) <> "💣"
        })

      refute changeset.valid?

      assert {:password,
              {"should be at most %{count} character(s)",
               [count: 72, validation: :length, kind: :max, type: :string]}} in changeset.errors
    end
  end

  describe "scheduled deletion changeset" do
    test "email doesn't match current users email" do
      errors =
        User.scheduled_deletion_changeset(%User{email: "real@email.com"}, %{
          "id" => "86201fff-a699-4eca-bb53-8736228ff187",
          "scheduled_deletion_email" => "user@gmail.com"
        })
        |> errors_on()

      assert errors[:scheduled_deletion_email] == [
               "This email doesn't match your current email"
             ]
    end

    test "email does match current users email" do
      errors =
        User.scheduled_deletion_changeset(%User{email: "real@email.com"}, %{
          "id" => "86201fff-a699-4eca-bb53-8736228ff187",
          "scheduled_deletion_email" => "real@email.com"
        })
        |> errors_on()

      assert errors[:scheduled_deletion_email] == nil
    end
  end

  describe "superuser_registration_changeset/1" do
    test "puts role change in changeset" do
      assert User.superuser_registration_changeset(%{})
             |> Ecto.Changeset.get_change(:role) ==
               :superuser
    end
  end
end
