defmodule Lightning.WebhookAuthMethodsTest do
  alias Lightning.Workflows.WebhookAuthMethod
  use Lightning.DataCase, async: true
  alias Lightning.WebhookAuthMethods
  import Lightning.Factories

  describe "create_webhook_auth_method/1" do
    setup do
      user = insert(:user)
      project = insert(:project)

      valid_attrs = %{
        name: "some_name",
        auth_type: "basic",
        username: "username",
        password: "password",
        creator_id: user.id,
        project_id: project.id
      }

      invalid_attrs = %{
        invalid: "attributes"
      }

      {:ok,
       valid_attrs: valid_attrs,
       invalid_attrs: invalid_attrs,
       user: user,
       project: project}
    end

    test "creates a webhook auth method with valid attributes", %{
      valid_attrs: valid_attrs
    } do
      assert_creation_with(
        valid_attrs,
        :basic,
        "some_name",
        "username",
        "password"
      )

      Map.merge(valid_attrs, %{
        name: "some_other_name",
        auth_type: "api"
      })
      |> assert_creation_with(:api, "some_other_name", nil, nil)
    end

    test "returns error when attributes are invalid", %{
      invalid_attrs: invalid_attrs
    } do
      assert {:error, _} =
               WebhookAuthMethods.create_webhook_auth_method(invalid_attrs)
    end

    defp assert_creation_with(attrs, auth_type, name, username, password) do
      assert {:ok, auth_method} =
               WebhookAuthMethods.create_webhook_auth_method(attrs)

      assert auth_method.name == name
      assert auth_method.auth_type == auth_type
      assert auth_method.username == username

      if password do
        assert auth_method |> WebhookAuthMethod.valid_password?(password)

        refute auth_method
               |> WebhookAuthMethod.valid_password?("another_password")
      else
        refute auth_method |> WebhookAuthMethod.valid_password?("password")
      end

      if auth_type == :api do
        refute auth_method.api_key == nil
      else
        assert auth_method.api_key == nil
      end
    end
  end

  describe "update_webhook_auth_method/2" do
    setup do
      auth_method = insert(:webhook_auth_method)
      {:ok, auth_method: auth_method}
    end

    test "updates the webhook auth method with valid attributes", %{
      auth_method: auth_method
    } do
      assert {:ok, new_auth_method} =
               WebhookAuthMethods.update_webhook_auth_method(auth_method, %{
                 name: "new_name"
               })

      assert new_auth_method.name == "new_name"
    end

    test "returns error when attributes are invalid", %{auth_method: auth_method} do
      assert {:error, _} =
               WebhookAuthMethods.update_webhook_auth_method(auth_method, %{
                 name: nil
               })
    end
  end

  describe "list_auth_methods/1" do
    test "lists all webhook auth methods for a given project" do
      project = insert(:project)
      insert_list(3, :webhook_auth_method, project: project)

      assert 3 = length(WebhookAuthMethods.list_auth_methods(project))
    end

    test "returns an empty list if there are no auth methods for a given project" do
      project = insert(:project)
      assert [] = WebhookAuthMethods.list_auth_methods(project)
    end
  end

  describe "get_auth_method_by_api_key/2" do
    test "retrieves the auth method by api_key and project_id" do
      auth_method = insert(:webhook_auth_method, api_key: "some_api_key")

      assert WebhookAuthMethods.get_auth_method_by_api_key(
               "some_api_key",
               auth_method.project
             ) ==
               auth_method
               |> Map.update!(:password, fn _ -> nil end)
               |> unload_relations([:creator, :project])
    end

    test "returns nil if there is no matching auth method" do
      project = insert(:project)

      assert is_nil(
               WebhookAuthMethods.get_auth_method_by_api_key(
                 "non_existing_api_key",
                 project
               )
             )
    end
  end

  describe "get_auth_method_by_username/2" do
    test "retrieves the auth method by username and project_id" do
      auth_method = insert(:webhook_auth_method, username: "some_username")

      assert WebhookAuthMethods.get_auth_method_by_username(
               "some_username",
               auth_method.project
             ) ==
               auth_method
               |> Map.update!(:password, fn _ -> nil end)
               |> unload_relations([:creator, :project])
    end

    test "returns nil if there is no matching auth method" do
      project = insert(:project)

      assert is_nil(
               WebhookAuthMethods.get_auth_method_by_username(
                 "non_existing_username",
                 project
               )
             )
    end
  end

  describe "get_auth_method_by_username_and_password/3" do
    setup do
      project = insert(:project)
      creator = insert(:user)

      {:ok, auth_method} =
        WebhookAuthMethods.create_webhook_auth_method(%{
          name: "my_webhook_auth_method",
          username: "some_username",
          password: "hello password",
          creator_id: creator.id,
          project_id: project.id
        })

      {:ok, auth_method: auth_method, project: project}
    end

    test "retrieves the auth method if the username and password are valid", %{
      auth_method: auth_method,
      project: project
    } do
      assert WebhookAuthMethods.get_auth_method_by_username_and_password(
               "some_username",
               "hello password",
               project
             ) == auth_method
    end

    test "returns nil if the password is invalid", %{
      project: project
    } do
      assert is_nil(
               WebhookAuthMethods.get_auth_method_by_username_and_password(
                 "some_username",
                 "invalid_password",
                 project
               )
             )
    end
  end

  describe "get_auth_method!/2" do
    test "retrieves the auth method by id and project_id" do
      auth_method = insert(:webhook_auth_method)

      assert WebhookAuthMethods.get_auth_method!(
               auth_method.id,
               auth_method.project
             ) ==
               auth_method
               |> Map.update!(:password, fn _ -> nil end)
               |> unload_relations([:creator, :project])
    end

    test "raises an error if there is no matching auth method" do
      project = insert(:project)

      assert_raise Ecto.NoResultsError, fn ->
        WebhookAuthMethods.get_auth_method!(Ecto.UUID.generate(), project)
      end
    end
  end

  describe "delete_auth_method/1" do
    test "deletes a Webhook Auth Method" do
      auth_method = insert(:webhook_auth_method)

      assert {:ok, _} = WebhookAuthMethods.delete_auth_method(auth_method)

      assert is_nil(
               Repo.get(Lightning.Workflows.WebhookAuthMethod, auth_method.id)
             )
    end
  end
end
