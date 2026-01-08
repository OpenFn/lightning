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

  describe "sensitive_values_for/1" do
    test "returns password but not username for basic auth" do
      auth_method = %WebhookAuthMethod{
        auth_type: :basic,
        username: "myuser",
        password: "secret123"
      }

      assert WebhookAuthMethod.sensitive_values_for(auth_method) == [
               "secret123"
             ]
    end

    test "returns api_key for api auth" do
      auth_method = %WebhookAuthMethod{
        auth_type: :api,
        api_key: "my-api-key-12345"
      }

      assert WebhookAuthMethod.sensitive_values_for(auth_method) == [
               "my-api-key-12345"
             ]
    end

    test "returns empty list for nil" do
      assert WebhookAuthMethod.sensitive_values_for(nil) == []
    end

    test "handles nil values in basic auth" do
      auth_method = %WebhookAuthMethod{
        auth_type: :basic,
        username: nil,
        password: "super-secret"
      }

      assert WebhookAuthMethod.sensitive_values_for(auth_method) == [
               "super-secret"
             ]
    end

    test "handles nil api_key" do
      auth_method = %WebhookAuthMethod{
        auth_type: :api,
        api_key: nil
      }

      assert WebhookAuthMethod.sensitive_values_for(auth_method) == []
    end
  end

  describe "basic_auth_for/1" do
    test "returns base64-encoded username:password for basic auth" do
      auth_method = %WebhookAuthMethod{
        auth_type: :basic,
        username: "myuser",
        password: "secret123"
      }

      expected = Base.encode64("myuser:secret123")
      assert WebhookAuthMethod.basic_auth_for(auth_method) == [expected]
    end

    test "returns empty list for api auth" do
      auth_method = %WebhookAuthMethod{
        auth_type: :api,
        api_key: "my-api-key-12345"
      }

      assert WebhookAuthMethod.basic_auth_for(auth_method) == []
    end

    test "returns empty list for nil" do
      assert WebhookAuthMethod.basic_auth_for(nil) == []
    end

    test "returns empty list when password is nil" do
      auth_method = %WebhookAuthMethod{
        auth_type: :basic,
        username: "something",
        password: nil
      }

      assert WebhookAuthMethod.basic_auth_for(auth_method) == []
    end
  end
end
