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
      invalid_attrs = Map.put(valid_attrs, :body, "not a map")
      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?
      assert {"Invalid OAuth token body", []} = changeset.errors[:body]
    end

    test "validates missing required OAuth body parts", %{
      valid_attrs: valid_attrs
    } do
      invalid_attrs =
        Map.put(valid_attrs, :body, %{
          "expires_in" => 3600,
          "scope" => "read write"
        })

      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?

      assert {"Missing required OAuth field: access_token", []} =
               changeset.errors[:body]
    end
  end

  describe "update_token_changeset/2" do
    setup do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      token =
        insert(:oauth_token,
          oauth_client: oauth_client,
          user: user,
          scopes: ["read", "write"],
          body: %{
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
