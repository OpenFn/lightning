defmodule Lightning.Accounts.UserTest do
  use Lightning.DataCase, async: true

  alias Lightning.Accounts.User

  describe "changeset/2" do
    setup do
      attrs = %{
        "email" => "john@test.com",
        "first_name" => "John",
        "last_name" => "Doe",
        "password" => "abc123456789"
      }

      %{attrs: attrs}
    end

    test "validates password if the struct is a new record", %{attrs: attrs} do
      attrs_sans_password = Map.delete(attrs, "password")

      %{valid?: valid?, errors: errors} =
        User.changeset(%User{}, attrs_sans_password)

      refute valid?
      assert {:password, {"can't be blank", [validation: :required]}} in errors
    end

    test "does not require password to be present if user has an id", %{
      attrs: attrs
    } do
      attrs_sans_password = Map.delete(attrs, "password")

      assert %{valid?: true} =
               User.changeset(
                 %User{id: Ecto.UUID.generate()},
                 attrs_sans_password
               )
    end

    test "does validate password for an existing user if provided", %{
      attrs: attrs
    } do
      attrs_password_too_short = Map.put(attrs, "password", "abc123")

      %{valid?: valid?, errors: errors} =
        User.changeset(%User{id: Ecto.UUID.generate()}, attrs_password_too_short)

      refute valid?

      assert {:password,
              {"should be at least %{count} character(s)",
               [count: 12, validation: :length, kind: :min, type: :string]}} in errors
    end
  end

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

    test "validates password if the struct is a new record", %{attrs: attrs} do
      attrs_sans_password = Map.delete(attrs, "password")

      %{valid?: valid?, errors: errors} =
        User.details_changeset(%User{}, attrs_sans_password)

      refute valid?
      assert {:password, {"can't be blank", [validation: :required]}} in errors
    end

    test "does not require password to be present if user has an id", %{
      attrs: attrs
    } do
      attrs_sans_password = Map.delete(attrs, "password")

      assert %{valid?: true} =
               User.details_changeset(
                 %User{id: Ecto.UUID.generate()},
                 attrs_sans_password
               )
    end

    test "does validate password for an existing user if provided", %{
      attrs: attrs
    } do
      attrs_password_too_short = Map.put(attrs, "password", "abc123")

      %{valid?: valid?, errors: errors} =
        User.details_changeset(
          %User{id: Ecto.UUID.generate()},
          attrs_password_too_short
        )

      refute valid?

      assert {:password,
              {"should be at least %{count} character(s)",
               [count: 12, validation: :length, kind: :min, type: :string]}} in errors
    end

    test "is valid if the attributes are valid", %{attrs: attrs} do
      changeset = User.details_changeset(%User{}, attrs)

      assert %{
               changes: %{
                 first_name: "John",
                 last_name: "Doe",
                 email: "johndoe@test.com",
                 role: :superuser,
                 disabled: true,
                 scheduled_deletion: ~U[2024-12-29 01:02:03Z]
               },
               valid?: true
             } = changeset
    end

    test "hashes and removes the plain text password", %{attrs: attrs} do
      %{changes: %{hashed_password: hashed_password} = changes} =
        User.details_changeset(%User{}, attrs)

      assert Bcrypt.verify_pass("123456789abc", hashed_password)

      refute Map.values(changes) |> Enum.member?(attrs.password)
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
      assert errors_on(changeset).email == ["must have the @ sign and no spaces"]
    end

    test "is invalid if the email contains whitespace", %{attrs: attrs} do
      attrs = Map.put(attrs, :email, "johndoe@ test.com")

      changeset = User.details_changeset(%User{}, attrs)

      refute changeset.valid?
      assert errors_on(changeset).email == ["must have the @ sign and no spaces"]
    end

    test "is invalid if the length of the email exceeds 160 characters", %{
      attrs: attrs
    } do
      attrs = Map.put(attrs, :email, String.duplicate("@", 160))

      changeset = User.details_changeset(%User{}, attrs)

      assert changeset.valid?

      attrs = Map.put(attrs, :email, String.duplicate("@", 161))

      changeset = User.details_changeset(%User{}, attrs)

      refute changeset.valid?
      assert errors_on(changeset).email == ["should be at most 160 character(s)"]
    end

    test "downcases the email", %{attrs: attrs} do
      attrs = Map.put(attrs, :email, "joHnDoE@teSt.cOm")

      assert %{
               changes: %{
                 email: "johndoe@test.com"
               },
               valid?: true
             } =
               User.details_changeset(%User{}, attrs)
    end

    test "is invalid if a user with the given email address already exists", %{
      attrs: attrs
    } do
      _other_user_1 = insert(:user, email: "not" <> attrs.email)

      assert %{valid?: true} = User.details_changeset(%User{}, attrs)

      _other_user_2 = insert(:user, email: attrs.email)

      changeset = User.details_changeset(%User{}, attrs)

      refute changeset.valid?
      assert errors_on(changeset).email == ["has already been taken"]
    end

    test "is invalid if the password is not provided", %{attrs: attrs} do
      attrs = Map.put(attrs, :password, "")

      changeset = User.details_changeset(%User{}, attrs)

      refute changeset.valid?
      assert errors_on(changeset).password == ["can't be blank"]
    end

    test "is invalid if the password is less than 12 or more than 72 chars", %{
      attrs: attrs
    } do
      attrs = Map.put(attrs, :password, String.duplicate("a", 11))

      changeset = User.details_changeset(%User{}, attrs)

      refute changeset.valid?

      assert errors_on(changeset).password ==
               ["should be at least 12 character(s)"]

      attrs = Map.put(attrs, :password, String.duplicate("a", 12))

      assert %{valid?: true} = User.details_changeset(%User{}, attrs)

      attrs = Map.put(attrs, :password, String.duplicate("a", 72))

      assert %{valid?: true} = User.details_changeset(%User{}, attrs)

      attrs = Map.put(attrs, :password, String.duplicate("a", 73))

      changeset = User.details_changeset(%User{}, attrs)

      refute changeset.valid?

      assert errors_on(changeset).password ==
               ["should be at most 72 character(s)"]
    end

    test "is invalid if password is more than 72 bytes in length", %{
      attrs: attrs
    } do
      attrs =
        Map.put(attrs, :password, String.duplicate("a", 71) <> "°")

      changeset = User.details_changeset(%User{}, attrs)

      refute changeset.valid?
      assert errors_on(changeset).password == ["should be at most 72 byte(s)"]
    end

    test "is invalid if the first name is blank", %{attrs: attrs} do
      attrs = Map.put(attrs, :first_name, "")

      changeset = User.details_changeset(%User{}, attrs)

      refute changeset.valid?
      assert errors_on(changeset).first_name == ["can't be blank"]
    end

    test "trims whitespace from the first name", %{attrs: attrs} do
      attrs = Map.put(attrs, :first_name, " John ")

      assert %{
               changes: %{
                 first_name: "John"
               },
               valid?: true
             } = User.details_changeset(%User{}, attrs)
    end

    test "is invalid if the last name is blank", %{attrs: attrs} do
      attrs = Map.put(attrs, :last_name, "")

      changeset = User.details_changeset(%User{}, attrs)

      refute changeset.valid?
      assert errors_on(changeset).last_name == ["can't be blank"]
    end

    test "trims whitespace from the last name", %{attrs: attrs} do
      attrs = Map.put(attrs, :last_name, " Doe ")

      assert %{
               changes: %{
                 last_name: "Doe"
               },
               valid?: true
             } = User.details_changeset(%User{}, attrs)
    end

    test "is invalid if the role is not amongst the allowed roles", %{
      attrs: attrs
    } do
      attrs = Map.put(attrs, :role, :user)

      assert %{valid?: true} = User.details_changeset(%User{}, attrs)

      attrs = Map.put(attrs, :role, :superuser)

      assert %{valid?: true} = User.details_changeset(%User{}, attrs)

      attrs = Map.put(attrs, :role, :invalid_role)

      changeset = User.details_changeset(%User{}, attrs)

      refute changeset.valid?
      assert errors_on(changeset).role == ["is invalid"]
    end
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

    test "user being deleted is a superuser" do
      user = %User{email: "real@email.com", role: :superuser}

      errors =
        User.scheduled_deletion_changeset(user, %{
          "id" => "86201fff-a699-4eca-bb53-8736228ff187",
          "scheduled_deletion_email" => "real@email.com"
        })
        |> errors_on()

      assert errors[:scheduled_deletion_email] == [
               "You can't delete a superuser account."
             ]
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
