defmodule Lightning.Credentials.OauthTokenTest do
  use Lightning.DataCase, async: true

  alias Lightning.Credentials.OauthToken

  describe "changeset/2" do
    setup do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      valid_attrs = %{
        body: %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "expires_in" => 3600,
          "scope" => "read write"
        },
        scopes: ["read", "write"],
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      {:ok, user: user, oauth_client: oauth_client, valid_attrs: valid_attrs}
    end

    test "with valid attributes creates a valid changeset", %{
      valid_attrs: valid_attrs
    } do
      changeset = OauthToken.changeset(%OauthToken{}, valid_attrs)
      assert changeset.valid?
    end

    test "requires body, scopes, oauth_client_id and user_id", %{} do
      changeset = OauthToken.changeset(%OauthToken{}, %{})

      assert %{
               body: ["Invalid OAuth token body", "can't be blank"],
               scopes: ["can't be blank"],
               oauth_client_id: ["can't be blank"],
               user_id: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates associations exist", %{user: _user, valid_attrs: valid_attrs} do
      attrs_with_bad_client =
        Map.put(valid_attrs, :oauth_client_id, Ecto.UUID.generate())

      {:error, changeset} =
        %OauthToken{}
        |> OauthToken.changeset(attrs_with_bad_client)
        |> Lightning.Repo.insert()

      refute changeset.valid?
      assert {"does not exist", _} = changeset.errors[:oauth_client]

      attrs_with_bad_user = Map.put(valid_attrs, :user_id, Ecto.UUID.generate())

      {:error, changeset} =
        %OauthToken{}
        |> OauthToken.changeset(attrs_with_bad_user)
        |> Lightning.Repo.insert()

      refute changeset.valid?
      assert {"does not exist", _} = changeset.errors[:user]
    end

    test "validates OAuth body format", %{valid_attrs: valid_attrs} do
      # Test with invalid body type
      invalid_attrs = Map.put(valid_attrs, :body, "not a map")
      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?
      assert {"Invalid OAuth token body", []} = changeset.errors[:body]
    end
  end

  describe "update_token_changeset/2" do
    setup do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      {:ok, token} =
        OauthToken.find_or_create_for_scopes(
          user.id,
          oauth_client.id,
          ["read", "write"],
          %{
            "access_token" => "access_token_123",
            "refresh_token" => "refresh_token_123",
            "expires_in" => 3600,
            "scope" => "read write"
          }
        )

      {:ok, token: token}
    end

    test "updates token body", %{token: token} do
      new_token_data = %{
        "access_token" => "new_access_token",
        "refresh_token" => "new_refresh_token",
        "expires_in" => 7200,
        "scope" => "read write execute"
      }

      changeset =
        OauthToken.update_token_changeset(token, new_token_data)

      assert changeset.valid?
      assert changeset.changes.body == new_token_data
      assert changeset.changes.scopes == ["read", "write", "execute"]
    end

    test "handles token with different scope format", %{token: token} do
      new_token_data = %{
        "access_token" => "new_access_token",
        "refresh_token" => "new_refresh_token",
        "expires_in" => 7200,
        "scopes" => ["read", "write", "admin"]
      }

      changeset = OauthToken.update_token_changeset(token, new_token_data)
      assert changeset.valid?
      assert changeset.changes.body == new_token_data
      assert changeset.changes.scopes == ["read", "write", "admin"]
    end

    test "handles invalid token body", %{token: token} do
      changeset = OauthToken.update_token_changeset(token, "not a map")
      refute changeset.valid?
      assert {"is invalid", _} = changeset.errors[:body]
    end

    test "validates token with missing scope information", %{token: token} do
      invalid_token = %{
        "access_token" => "new_access_token",
        "refresh_token" => "new_refresh_token",
        "expires_in" => 7200
      }

      changeset =
        OauthToken.update_token_changeset(token, invalid_token)

      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:scopes]
    end
  end

  describe "find_or_create_for_scopes/4" do
    setup do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "expires_in" => 3600,
        "scope" => "read write"
      }

      {:ok, user: user, oauth_client: oauth_client, token_data: token_data}
    end

    test "creates a new token when none exists", %{
      user: user,
      oauth_client: oauth_client,
      token_data: token_data
    } do
      {:ok, token} =
        OauthToken.find_or_create_for_scopes(
          user.id,
          oauth_client.id,
          ["read", "write"],
          token_data
        )

      assert token.user_id == user.id
      assert token.oauth_client_id == oauth_client.id
      assert token.scopes == ["read", "write"]
      assert token.body == token_data
    end

    test "returns existing token with matching scopes", %{
      user: user,
      oauth_client: oauth_client,
      token_data: token_data
    } do
      {:ok, created_token} =
        OauthToken.find_or_create_for_scopes(
          user.id,
          oauth_client.id,
          ["read", "write"],
          token_data
        )

      {:ok, found_token} =
        OauthToken.find_or_create_for_scopes(
          user.id,
          oauth_client.id,
          ["read", "write"],
          %{"different" => "token"}
        )

      assert found_token.id == created_token.id
      assert found_token.body == token_data
    end

    test "scopes are matched regardless of order", %{
      user: user,
      oauth_client: oauth_client,
      token_data: token_data
    } do
      {:ok, created_token} =
        OauthToken.find_or_create_for_scopes(
          user.id,
          oauth_client.id,
          ["read", "write"],
          token_data
        )

      {:ok, found_token} =
        OauthToken.find_or_create_for_scopes(
          user.id,
          oauth_client.id,
          ["write", "read"],
          %{"different" => "token"}
        )

      assert found_token.id == created_token.id
    end
  end

  describe "find_by_scopes/3" do
    setup do
      user = insert(:user)

      # Create two clients with same client_id/secret
      client_attrs = %{
        name: "Shared Client",
        client_id: "shared_client_id",
        client_secret: "shared_client_secret",
        authorization_endpoint: "https://example.com/auth",
        token_endpoint: "https://example.com/token"
      }

      oauth_client1 = insert(:oauth_client, client_attrs)
      oauth_client2 = insert(:oauth_client, client_attrs)

      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "expires_in" => 3600,
        "scope" => "read write"
      }

      {:ok, token} =
        OauthToken.find_or_create_for_scopes(
          user.id,
          oauth_client1.id,
          ["read", "write"],
          token_data
        )

      {:ok,
       user: user,
       oauth_client1: oauth_client1,
       oauth_client2: oauth_client2,
       token: token}
    end

    test "finds token for same client by scopes", %{
      user: user,
      oauth_client1: client,
      token: token
    } do
      found_token =
        OauthToken.find_by_scopes(user.id, client.id, ["read", "write"])

      assert found_token.id == token.id
    end

    test "finds token for different client with same client_id/secret", %{
      user: user,
      oauth_client2: client,
      token: token
    } do
      found_token =
        OauthToken.find_by_scopes(user.id, client.id, ["read", "write"])

      assert found_token.id == token.id
    end

    test "scopes must match exactly", %{user: user, oauth_client1: client} do
      found_token =
        OauthToken.find_by_scopes(user.id, client.id, ["read", "write", "extra"])

      assert found_token == nil
    end

    test "returns nil when no matching token exists", %{user: user} do
      new_client = insert(:oauth_client)

      found_token =
        OauthToken.find_by_scopes(user.id, new_client.id, ["read", "write"])

      assert found_token == nil
    end
  end

  describe "extract_scopes/1" do
    test "extracts scopes from string with scope key" do
      {:ok, scopes} =
        OauthToken.extract_scopes(%{"scope" => "read write profile"})

      assert scopes == ["read", "write", "profile"]

      {:ok, scopes} = OauthToken.extract_scopes(%{scope: "admin user"})
      assert scopes == ["admin", "user"]
    end

    test "extracts scopes from list with scopes key" do
      {:ok, scopes} = OauthToken.extract_scopes(%{"scopes" => ["read", "write"]})
      assert scopes == ["read", "write"]

      {:ok, scopes} = OauthToken.extract_scopes(%{scopes: ["admin", "user"]})
      assert scopes == ["admin", "user"]
    end

    test "returns error for invalid format" do
      assert :error = OauthToken.extract_scopes(%{"invalid" => "format"})
      assert :error = OauthToken.extract_scopes(%{})
      assert :error = OauthToken.extract_scopes(nil)
    end
  end
end
