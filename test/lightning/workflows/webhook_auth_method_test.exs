defmodule Lightning.Workflows.WebhookAuthMethodTest do
  use Lightning.DataCase, async: true

  alias Lightning.Workflows.WebhookAuthMethod

  import Lightning.Factories

  describe "changeset/2" do
    setup do
      project = insert(:project)

      %{
        valid_attrs: %{
          name: "some name",
          auth_type: :basic,
          username: "some username",
          password: "somepassword",
          project_id: project.id
        },
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
      project = insert(:project)

      insert(:webhook_auth_method,
        name: "unique_name",
        project: project
      )

      %{
        project: project
      }
    end

    defp assert_unique_constraint_error(changeset, field, error_message) do
      assert {:error, changeset} = changeset |> Repo.insert()
      assert %{field => [error_message]} == errors_on(changeset)
    end

    test "validates unique name", %{
      project: project
    } do
      changeset =
        WebhookAuthMethod.changeset(%WebhookAuthMethod{}, %{
          name: "unique_name",
          auth_type: :api,
          project_id: project.id
        })

      assert_unique_constraint_error(
        changeset,
        :name,
        "must be unique within the project"
      )
    end
  end

  defp setup_auth_method(value, key) do
    hashed_value = Bcrypt.hash_pwd_salt(value)
    Map.put(%WebhookAuthMethod{}, key, hashed_value)
  end

  defp test_validity(assert_or_refute, function, webhook_auth_method, value) do
    assert_or_refute.(function.(webhook_auth_method, value))
  end

  describe "valid_password?/2" do
    setup do
      webhook_auth_method = setup_auth_method("somepassword", :hashed_password)
      {:ok, webhook_auth_method: webhook_auth_method}
    end

    test "returns true for valid password", %{
      webhook_auth_method: webhook_auth_method
    } do
      test_validity(
        &assert/1,
        &WebhookAuthMethod.valid_password?/2,
        webhook_auth_method,
        "somepassword"
      )
    end

    test "returns false for invalid password", %{
      webhook_auth_method: webhook_auth_method
    } do
      test_validity(
        &refute/1,
        &WebhookAuthMethod.valid_password?/2,
        webhook_auth_method,
        "wrongpassword"
      )
    end

    test "returns false for no password" do
      webhook_auth_method = %WebhookAuthMethod{}

      test_validity(
        &refute/1,
        &WebhookAuthMethod.valid_password?/2,
        webhook_auth_method,
        "somepassword"
      )
    end
  end

  describe "valid_api_key?/2" do
    setup do
      webhook_auth_method = setup_auth_method("somerandomapikey", :api_key)
      {:ok, webhook_auth_method: webhook_auth_method}
    end

    test "returns true for valid api_key", %{
      webhook_auth_method: webhook_auth_method
    } do
      test_validity(
        &assert/1,
        &WebhookAuthMethod.valid_api_key?/2,
        webhook_auth_method,
        "somerandomapikey"
      )
    end

    test "returns false for invalid api_key", %{
      webhook_auth_method: webhook_auth_method
    } do
      test_validity(
        &refute/1,
        &WebhookAuthMethod.valid_api_key?/2,
        webhook_auth_method,
        "wrongapikey"
      )
    end

    test "returns false for no api_key" do
      webhook_auth_method = %WebhookAuthMethod{}

      test_validity(
        &refute/1,
        &WebhookAuthMethod.valid_api_key?/2,
        webhook_auth_method,
        "somerandomapikey"
      )
    end
  end
end
