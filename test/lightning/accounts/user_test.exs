defmodule Lightning.Accounts.UserTest do
  use Lightning.DataCase, async: true

  alias Lightning.Accounts.User

  describe "details_changeset/2" do
    setup do
      attrs = %{
        first_name: "John",
        last_name: "Doe",
        email: "johndoe@test.com",
        password: "123456789abc",
        role: :superuser,
        disabled: true,
        scheduled_deletion: "2024-12-29 01:02:03"
      }

      %{attrs: attrs}
    end

    test "is valid if the attributes are valid", %{attrs: attrs} do
      changeset = User.details_changeset(%User{}, attrs)

      assert %{
        changes: %{
          first_name: "John",
          last_name: "Doe",
          email: "johndoe@test.com",
          password: "123456789abc",
          role: :superuser,
          disabled: true,
          scheduled_deletion: ~U[2024-12-29 01:02:03Z],
        },
        valid?: true
      } = changeset
    end

    test "is invalid if the email is blank", %{attrs: attrs} do
      attrs = Map.put(attrs, :email, "")

      changeset = User.details_changeset(%User{}, attrs)

      refute changeset.valid?
      assert errors_on(changeset).email == ["can't be blank"]
    end

    test "is invalid if the email does not contain an `@`", %{attrs: attrs} do
      attrs = Map.put(attrs, :email, "johndoetest.com")

      changeset = User.details_changeset(%User{}, attrs)

      refute changeset.valid?
      assert errors_on(changeset).email == ["can't be blank"]
    end
    # test "is invalid if the  email does not contain an @", %{attrs: attrs} do
    #
    # end
  end

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
