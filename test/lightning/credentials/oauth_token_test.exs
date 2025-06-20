defmodule Lightning.Credentials.OauthTokenTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Credentials.OauthToken
  alias Lightning.Credentials.OauthValidation

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

    test "changeset/1 with single argument calls changeset/2 with empty struct" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      attrs = %{
        body: %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "expires_in" => 3600
        },
        scopes: ["read"],
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset1 = OauthToken.changeset(attrs)
      changeset2 = OauthToken.changeset(%OauthToken{}, attrs)

      assert changeset1.data == changeset2.data
      assert changeset1.changes == changeset2.changes
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

    test "validates body with missing refresh_token for new connection", %{
      valid_attrs: valid_attrs
    } do
      invalid_attrs =
        put_in(valid_attrs, [:body], %{
          "access_token" => "access_token_123",
          "expires_in" => 3600,
          "scope" => "read write"
        })

      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?

      assert {"Missing refresh_token for new OAuth connection", []} =
               changeset.errors[:body]
    end

    test "validates body with missing expiration", %{valid_attrs: valid_attrs} do
      invalid_attrs =
        put_in(valid_attrs, [:body], %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "scope" => "read write"
        })

      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?

      assert {"Missing expiration field: either expires_in or expires_at is required",
              []} =
               changeset.errors[:body]
    end

    test "accepts expires_at instead of expires_in", %{valid_attrs: valid_attrs} do
      attrs_with_expires_at =
        put_in(valid_attrs, [:body], %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "expires_at" => "2024-12-31T23:59:59Z",
          "scope" => "read write"
        })

      changeset = OauthToken.changeset(%OauthToken{}, attrs_with_expires_at)
      assert changeset.valid?
    end

    test "validates OAuth body calls OauthValidation.validate_token_data", %{
      valid_attrs: valid_attrs
    } do
      changeset = OauthToken.changeset(%OauthToken{}, valid_attrs)
      assert changeset.valid?

      invalid_token_attrs =
        put_in(valid_attrs, [:body], %{
          "invalid" => "token"
        })

      invalid_changeset =
        OauthToken.changeset(%OauthToken{}, invalid_token_attrs)

      refute invalid_changeset.valid?
    end

    test "populates virtual error fields on validation failure", %{
      user: user,
      oauth_client: oauth_client
    } do
      insert(:oauth_token, %{
        user: user,
        oauth_client: oauth_client,
        scopes: ["read", "write"]
      })

      attrs = %{
        body: %{
          "access_token" => "access_token_456",
          "expires_in" => 3600,
          "scope" => "read write"
        },
        scopes: ["read", "write"],
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(%OauthToken{}, attrs)
      assert changeset.valid?
    end

    test "handles nil body gracefully", %{valid_attrs: valid_attrs} do
      attrs_with_nil_body = Map.put(valid_attrs, :body, nil)
      changeset = OauthToken.changeset(%OauthToken{}, attrs_with_nil_body)

      refute changeset.valid?
      errors = errors_on(changeset)
      assert "Invalid OAuth token body" in errors[:body]
      assert "can't be blank" in errors[:body]
    end

    test "handles invalid token format", %{valid_attrs: valid_attrs} do
      attrs_with_invalid_body = Map.put(valid_attrs, :body, [1, 2, 3])
      changeset = OauthToken.changeset(%OauthToken{}, attrs_with_invalid_body)

      refute changeset.valid?
      assert {"Invalid OAuth token body", []} = changeset.errors[:body]

      assert get_change(changeset, :oauth_error_type) == :invalid_token_format
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

    test "preserves existing refresh_token when new token doesn't have one", %{
      token: token
    } do
      new_token_data = %{
        "access_token" => "new_access_token",
        "expires_in" => 7200,
        "scope" => "read write execute"
      }

      changeset = OauthToken.update_token_changeset(token, new_token_data)

      assert changeset.valid?

      expected_body = %{
        # Preserved from original
        "refresh_token" => "refresh_token_123",
        "access_token" => "new_access_token",
        "expires_in" => 7200,
        "scope" => "read write execute"
      }

      assert changeset.changes.body == expected_body
      assert changeset.changes.scopes == ["read", "write", "execute"]
    end

    test "ensure_refresh_token only works with tokens that have refresh_token",
         %{token: token} do
      new_token_data = %{
        "access_token" => "new_access_token",
        "expires_in" => 7200,
        "scope" => "read write execute"
      }

      changeset = OauthToken.update_token_changeset(token, new_token_data)

      assert changeset.valid?

      expected_body =
        Map.merge(%{"refresh_token" => "refresh_token_123"}, new_token_data)

      assert changeset.changes.body == expected_body
    end

    test "function design requires refresh_token in original token" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      token_without_refresh =
        insert(:oauth_token, %{
          oauth_client: oauth_client,
          user: user,
          scopes: ["read"],
          body: %{
            "access_token" => "access_token_123",
            "expires_in" => 3600,
            "scope" => "read"
          }
        })

      new_token_data = %{
        "access_token" => "new_access_token",
        "expires_in" => 7200,
        "scope" => "read"
      }

      assert_raise FunctionClauseError, fn ->
        OauthToken.update_token_changeset(token_without_refresh, new_token_data)
      end
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

    test "validates updated token body", %{token: token} do
      invalid_token = %{
        "refresh_token" => "new_refresh_token",
        "scope" => "read write"
      }

      changeset = OauthToken.update_token_changeset(token, invalid_token)

      refute changeset.valid?

      assert {"Missing required OAuth field: access_token", []} =
               changeset.errors[:body]
    end

    test "handles empty map input", %{token: token} do
      changeset = OauthToken.update_token_changeset(token, %{})

      expected_body = %{"refresh_token" => "refresh_token_123"}
      assert get_change(changeset, :body) == expected_body
      assert get_change(changeset, :scopes) == nil
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

    test "handles empty scope string" do
      {:ok, scopes} = OauthToken.extract_scopes(%{"scope" => ""})
      assert scopes == [""]
    end

    test "handles single scope" do
      {:ok, scopes} = OauthToken.extract_scopes(%{"scope" => "read"})
      assert scopes == ["read"]
    end

    test "delegates to OauthValidation.extract_scopes" do
      test_data = %{"scope" => "test scope"}

      result1 = OauthToken.extract_scopes(test_data)
      result2 = OauthValidation.extract_scopes(test_data)

      assert result1 == result2
    end
  end

  describe "associations" do
    test "belongs to oauth_client" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client
        })

      loaded_token =
        OauthToken
        |> preload(:oauth_client)
        |> Repo.get!(token.id)

      assert loaded_token.oauth_client.id == oauth_client.id
    end

    test "belongs to user" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client
        })

      loaded_token =
        OauthToken
        |> preload(:user)
        |> Repo.get!(token.id)

      assert loaded_token.user.id == user.id
    end

    test "has many credentials" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client
        })

      credential =
        insert(:credential, %{
          user: user,
          oauth_token: token
        })

      loaded_token =
        OauthToken
        |> preload(:credentials)
        |> Repo.get!(token.id)

      assert length(loaded_token.credentials) == 1
      assert hd(loaded_token.credentials).id == credential.id
    end
  end

  describe "encryption" do
    test "encrypts token body at rest" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      body = %{
        "access_token" => "secret_access_token",
        "refresh_token" => "secret_refresh_token",
        "expires_in" => 3600
      }

      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client,
          body: body,
          scopes: ["read"]
        })

      assert token.body == body

      persisted_body =
        from(t in OauthToken,
          select: type(t.body, :string),
          where: t.id == ^token.id
        )
        |> Repo.one!()

      refute persisted_body == body
    end

    test "decrypts token body when loaded" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      body = %{
        "access_token" => "secret_token_123",
        "refresh_token" => "secret_refresh_123",
        "expires_in" => 7200,
        "scope" => "read write"
      }

      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client,
          body: body,
          scopes: ["read", "write"]
        })

      reloaded_token = Repo.get!(OauthToken, token.id)

      assert reloaded_token.body == body
    end
  end

  describe "virtual fields" do
    test "oauth_error_type and oauth_error_details are virtual" do
      token = %OauthToken{
        oauth_error_type: :missing_scopes,
        oauth_error_details: %{missing_scopes: ["write"]}
      }

      assert token.oauth_error_type == :missing_scopes
      assert token.oauth_error_details == %{missing_scopes: ["write"]}

      schema_fields = OauthToken.__schema__(:fields)
      refute :oauth_error_type in schema_fields
      refute :oauth_error_details in schema_fields
    end
  end

  describe "private functions" do
    test "get_fields extracts multiple fields from changeset" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      changeset =
        OauthToken.changeset(%{
          body: %{"access_token" => "test"},
          scopes: ["read"],
          oauth_client_id: oauth_client.id,
          user_id: user.id
        })

      refute changeset.valid?
    end

    test "add_oauth_error populates virtual fields" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      changeset =
        OauthToken.changeset(%{
          body: %{"invalid" => "data"},
          scopes: ["read"],
          oauth_client_id: oauth_client.id,
          user_id: user.id
        })

      refute changeset.valid?

      assert get_change(changeset, :oauth_error_type) != nil
    end
  end

  describe "edge cases" do
    test "handles very large token bodies" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      large_body = %{
        "access_token" => String.duplicate("a", 1000),
        "refresh_token" => String.duplicate("b", 1000),
        "expires_in" => 3600,
        "scope" => "read write",
        "extra_data" => String.duplicate("c", 5000)
      }

      attrs = %{
        body: large_body,
        scopes: ["read", "write"],
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(attrs)
      assert changeset.valid?
    end

    test "handles empty scopes array" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      attrs = %{
        body: %{
          "access_token" => "token_123",
          "refresh_token" => "refresh_123",
          "expires_in" => 3600,
          "scope" => ""
        },
        scopes: [],
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(attrs)

      assert changeset.valid?
    end

    test "handles token body with extra fields" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      body_with_extras = %{
        "access_token" => "token_123",
        "refresh_token" => "refresh_123",
        "expires_in" => 3600,
        "scope" => "read write",
        "token_type" => "Bearer",
        "custom_field" => "custom_value",
        "nested" => %{"data" => "value"}
      }

      attrs = %{
        body: body_with_extras,
        scopes: ["read", "write"],
        oauth_client_id: oauth_client.id,
        user_id: user.id
      }

      changeset = OauthToken.changeset(attrs)
      assert changeset.valid?
    end
  end
end
