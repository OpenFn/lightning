defmodule Lightning.Workflows.WebhookAuthMethodTest do
  use Lightning.DataCase, async: true

  alias Lightning.Workflows.WebhookAuthMethod

  import Lightning.Factories

  describe "changeset/2" do
    setup do
      user = insert(:user)
      project = insert(:project)

      %{
        valid_attrs: %{
          name: "some name",
          auth_type: :basic,
          username: "some username",
          password: "somepassword",
          creator_id: user.id,
          project_id: project.id
        },
        user: user,
        project: project
      }
    end

    test "generates a valid changeset for basic auth", %{
      valid_attrs: valid_attrs
    } do
      changeset =
        WebhookAuthMethod.changeset(
          %WebhookAuthMethod{},
          Map.put(valid_attrs, :auth_type, :basic)
        )

      assert changeset.valid?
    end

    test "generates a valid changeset for api auth", %{valid_attrs: valid_attrs} do
      changeset =
        WebhookAuthMethod.changeset(
          %WebhookAuthMethod{},
          Map.put(valid_attrs, :auth_type, :api)
        )

      assert changeset.valid?
    end

    test "invalid without required fields", %{valid_attrs: _valid_attrs} do
      changeset = WebhookAuthMethod.changeset(%WebhookAuthMethod{}, %{})
      refute changeset.valid?
    end

    test "validates auth_type", %{valid_attrs: valid_attrs} do
      changeset =
        WebhookAuthMethod.changeset(
          %WebhookAuthMethod{},
          Map.put(valid_attrs, :auth_type, :auth_type)
        )

      assert %{auth_type: ["is invalid"]} == errors_on(changeset)
    end

    test "validates password length", %{valid_attrs: valid_attrs} do
      changeset =
        WebhookAuthMethod.changeset(
          %WebhookAuthMethod{},
          %{valid_attrs | password: "short"}
        )

      assert %{password: ["should be at least 8 character(s)"]} ==
               errors_on(changeset)
    end
  end

  describe "unique_constraints/1" do
    setup do
      user = insert(:user)
      project = insert(:project)

      insert(:webhook_auth_method,
        name: "unique_name",
        username: "unique_username",
        project: project,
        creator: user
      )

      %{
        user: user,
        project: project
      }
    end

    defp assert_unique_constraint_error(changeset, field, error_message) do
      assert {:error, changeset} = changeset |> Repo.insert()
      assert %{field => [error_message]} == errors_on(changeset)
    end

    test "validates unique name", %{
      user: user,
      project: project
    } do
      changeset =
        WebhookAuthMethod.changeset(%WebhookAuthMethod{}, %{
          name: "unique_name",
          auth_type: :api,
          project_id: project.id,
          creator_id: user.id
        })

      assert_unique_constraint_error(
        changeset,
        :name,
        "must be unique within the project"
      )
    end

    test "validates unique username", %{
      user: user,
      project: project
    } do
      changeset =
        WebhookAuthMethod.changeset(%WebhookAuthMethod{}, %{
          name: "a name",
          username: "unique_username",
          password: "password",
          creator_id: user.id,
          project_id: project.id
        })

      assert_unique_constraint_error(
        changeset,
        :username,
        "must be unique within the project"
      )
    end
  end

  describe "valid_password?/2" do
    test "returns true for valid password" do
      password = "somepassword"
      hashed_password = Bcrypt.hash_pwd_salt(password)
      webhook_auth_method = %WebhookAuthMethod{hashed_password: hashed_password}
      assert WebhookAuthMethod.valid_password?(webhook_auth_method, password)
    end

    test "returns false for invalid password" do
      password = "somepassword"
      hashed_password = Bcrypt.hash_pwd_salt(password)
      webhook_auth_method = %WebhookAuthMethod{hashed_password: hashed_password}

      refute WebhookAuthMethod.valid_password?(
               webhook_auth_method,
               "wrongpassword"
             )
    end

    test "returns false for no password" do
      webhook_auth_method = %WebhookAuthMethod{}

      refute WebhookAuthMethod.valid_password?(
               webhook_auth_method,
               "anypassword"
             )
    end
  end
end
