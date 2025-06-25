defmodule Lightning.Credentials.OauthTokenTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Credentials.OauthToken

  describe "changeset/2" do
    setup do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      valid_attrs = %{
        body: %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "read write"
        },
        scopes: ["read", "write"],
        oauth_client_id: oauth_client.id,
        user_id: user.id,
        last_refreshed: DateTime.utc_now()
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
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "read"
        },
        scopes: ["read"],
        oauth_client_id: oauth_client.id,
        user_id: user.id,
        last_refreshed: DateTime.utc_now()
      }

      changeset1 = OauthToken.changeset(attrs)
      changeset2 = OauthToken.changeset(%OauthToken{}, attrs)

      assert changeset1.data == changeset2.data
      assert changeset1.changes == changeset2.changes
    end

    test "requires body, oauth_client_id, user_id, scopes, and last_refreshed" do
      changeset = OauthToken.changeset(%OauthToken{}, %{})

      refute changeset.valid?

      # Check errors directly from the changeset
      assert {:body, {"can't be blank", [validation: :required]}} in changeset.errors

      assert {:oauth_client_id, {"can't be blank", [validation: :required]}} in changeset.errors

      assert {:user_id, {"can't be blank", [validation: :required]}} in changeset.errors

      assert {:scopes, {"can't be blank", [validation: :required]}} in changeset.errors

      assert {:last_refreshed, {"can't be blank", [validation: :required]}} in changeset.errors
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

    test "validates OAuth body format - non-map body", %{
      valid_attrs: valid_attrs
    } do
      invalid_attrs = Map.put(valid_attrs, :body, "not a map")
      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?

      assert {"is invalid", [type: Lightning.Encrypted.Map, validation: :cast]} =
               changeset.errors[:body]
    end

    test "validates OAuth body format - nil body", %{valid_attrs: valid_attrs} do
      invalid_attrs = Map.put(valid_attrs, :body, nil)
      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?

      assert {:body, {"can't be blank", [validation: :required]}} in changeset.errors
    end

    test "validates all required OAuth fields", %{valid_attrs: valid_attrs} do
      invalid_attrs =
        put_in(valid_attrs, [:body], %{
          "refresh_token" => "refresh_token_123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "read write"
        })

      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?

      assert {"Missing required OAuth field: access_token", _} =
               changeset.errors[:body]

      invalid_attrs =
        put_in(valid_attrs, [:body], %{
          "access_token" => "access_token_123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "read write"
        })

      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?

      assert {"Missing required OAuth field: refresh_token", _} =
               changeset.errors[:body]

      invalid_attrs =
        put_in(valid_attrs, [:body], %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "expires_in" => 3600,
          "scope" => "read write"
        })

      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?

      assert {"Missing required OAuth field: token_type", _} =
               changeset.errors[:body]
    end

    test "validates token_type is Bearer", %{valid_attrs: valid_attrs} do
      invalid_attrs = put_in(valid_attrs, [:body, "token_type"], "Basic")
      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?

      assert {"Unsupported token type: 'Basic'. Expected 'Bearer'", _} =
               changeset.errors[:body]
    end

    test "validates empty token fields", %{valid_attrs: valid_attrs} do
      invalid_attrs = put_in(valid_attrs, [:body, "access_token"], "")
      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?
      assert {"access_token cannot be empty", _} = changeset.errors[:body]

      invalid_attrs = put_in(valid_attrs, [:body, "scope"], "")
      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?
      assert {"scope field cannot be empty", _} = changeset.errors[:body]
    end

    test "validates expires_in bounds", %{valid_attrs: valid_attrs} do
      invalid_attrs = put_in(valid_attrs, [:body, "expires_in"], 0)
      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?

      assert {"expires_in must be greater than 0 seconds, got: 0", _} =
               changeset.errors[:body]

      invalid_attrs = put_in(valid_attrs, [:body, "expires_in"], -300)
      changeset = OauthToken.changeset(%OauthToken{}, invalid_attrs)
      refute changeset.valid?

      assert {"expires_in must be greater than 0 seconds, got: -300", _} =
               changeset.errors[:body]
    end

    test "accepts expires_at instead of expires_in", %{valid_attrs: valid_attrs} do
      future_time = System.system_time(:second) + 3600

      attrs_with_expires_at =
        put_in(valid_attrs, [:body], %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "token_type" => "Bearer",
          "expires_at" => future_time,
          "scope" => "read write"
        })

      changeset = OauthToken.changeset(%OauthToken{}, attrs_with_expires_at)
      assert changeset.valid?
    end

    test "accepts expires_in as string", %{valid_attrs: valid_attrs} do
      attrs_with_string_expires_in =
        put_in(valid_attrs, [:body, "expires_in"], "3600")

      changeset =
        OauthToken.changeset(%OauthToken{}, attrs_with_string_expires_in)

      assert changeset.valid?
    end

    test "casts last_refreshed field", %{valid_attrs: valid_attrs} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      attrs_with_last_refreshed = Map.put(valid_attrs, :last_refreshed, now)

      changeset = OauthToken.changeset(%OauthToken{}, attrs_with_last_refreshed)
      assert changeset.valid?
      assert get_change(changeset, :last_refreshed) == now
    end
  end

  describe "update_changeset/2" do
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
            "token_type" => "Bearer",
            "expires_in" => 3600,
            "scope" => "read write"
          },
          last_refreshed: DateTime.utc_now()
        )

      {:ok, token: token}
    end

    test "updates token body and scopes", %{token: token} do
      new_attrs = %{
        body: %{
          "access_token" => "new_access_token",
          "refresh_token" => "new_refresh_token",
          "token_type" => "Bearer",
          "expires_in" => 7200,
          "scope" => "read write execute"
        },
        scopes: ["read", "write", "execute"],
        last_refreshed: DateTime.utc_now()
      }

      changeset = OauthToken.update_changeset(token, new_attrs)

      assert changeset.valid?
      assert changeset.changes.body == new_attrs.body
      assert changeset.changes.scopes == ["read", "write", "execute"]
    end

    test "requires body, scopes, and last_refreshed", %{token: token} do
      changeset =
        OauthToken.update_changeset(token, %{
          body: nil,
          scopes: nil,
          last_refreshed: nil
        })

      refute changeset.valid?

      assert {:body, {"can't be blank", [validation: :required]}} in changeset.errors

      assert {:scopes, {"can't be blank", [validation: :required]}} in changeset.errors

      assert {:last_refreshed, {"can't be blank", [validation: :required]}} in changeset.errors
    end

    test "updates last_refreshed timestamp", %{token: token} do
      new_time = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        body: token.body,
        scopes: token.scopes,
        last_refreshed: new_time
      }

      changeset = OauthToken.update_changeset(token, attrs)
      assert changeset.valid?
      assert get_change(changeset, :last_refreshed) == new_time
    end
  end

  describe "still_fresh?/2" do
    test "returns true for token with future expires_at timestamp" do
      future_time = System.system_time(:second) + 3600

      token = %OauthToken{
        body: %{"expires_at" => future_time},
        last_refreshed: DateTime.utc_now()
      }

      assert OauthToken.still_fresh?(token)
    end

    test "returns false for token with past expires_at timestamp" do
      past_time = System.system_time(:second) - 3600

      token = %OauthToken{
        body: %{"expires_at" => past_time},
        last_refreshed: DateTime.utc_now()
      }

      refute OauthToken.still_fresh?(token)
    end

    test "handles expires_at as string" do
      future_time = System.system_time(:second) + 3600

      token = %OauthToken{
        body: %{"expires_at" => Integer.to_string(future_time)},
        last_refreshed: DateTime.utc_now()
      }

      assert OauthToken.still_fresh?(token)
    end

    test "returns true for token with valid expires_in" do
      token = %OauthToken{
        body: %{"expires_in" => 3600},
        last_refreshed: DateTime.utc_now()
      }

      assert OauthToken.still_fresh?(token)
    end

    test "returns false for token with expired expires_in" do
      token = %OauthToken{
        body: %{"expires_in" => 3600},
        last_refreshed: DateTime.add(DateTime.utc_now(), -7200, :second)
      }

      refute OauthToken.still_fresh?(token)
    end

    test "handles expires_in as string" do
      token = %OauthToken{
        body: %{"expires_in" => "3600"},
        last_refreshed: DateTime.utc_now()
      }

      assert OauthToken.still_fresh?(token)
    end

    test "returns false for token without expiration data" do
      token = %OauthToken{
        body: %{"access_token" => "token"},
        last_refreshed: DateTime.utc_now()
      }

      refute OauthToken.still_fresh?(token)
    end

    test "returns false for token with nil last_refreshed when using expires_in" do
      token = %OauthToken{
        body: %{"expires_in" => 3600},
        last_refreshed: nil
      }

      refute OauthToken.still_fresh?(token)
    end

    test "handles malformed expires_at gracefully" do
      token = %OauthToken{
        body: %{"expires_at" => "not_a_number"},
        last_refreshed: DateTime.utc_now()
      }

      refute OauthToken.still_fresh?(token)
    end

    test "handles malformed expires_in gracefully" do
      token = %OauthToken{
        body: %{"expires_in" => "not_a_number"},
        last_refreshed: DateTime.utc_now()
      }

      refute OauthToken.still_fresh?(token)
    end

    test "respects buffer_minutes parameter" do
      expires_at = System.system_time(:second) + 600

      token = %OauthToken{
        body: %{"expires_at" => expires_at},
        last_refreshed: DateTime.utc_now()
      }

      assert OauthToken.still_fresh?(token)

      refute OauthToken.still_fresh?(token, 15)
    end

    test "handles edge case where token expires within buffer" do
      expires_at = System.system_time(:second) + 300

      token = %OauthToken{
        body: %{"expires_at" => expires_at},
        last_refreshed: DateTime.utc_now()
      }

      refute OauthToken.still_fresh?(token)

      assert OauthToken.still_fresh?(token, 3)
    end

    test "prefers expires_at over expires_in when both present" do
      past_expires_at = System.system_time(:second) - 1800

      token = %OauthToken{
        body: %{
          "expires_in" => 7200,
          "expires_at" => past_expires_at
        },
        last_refreshed: DateTime.utc_now()
      }

      refute OauthToken.still_fresh?(token)
    end

    test "uses default buffer of 5 minutes when not specified" do
      expires_at = System.system_time(:second) + 300

      token = %OauthToken{
        body: %{"expires_at" => expires_at},
        last_refreshed: DateTime.utc_now()
      }

      refute OauthToken.still_fresh?(token)
      assert OauthToken.still_fresh?(token, 4)
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

      loaded_token = OauthToken |> preload(:oauth_client) |> Repo.get!(token.id)
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

      loaded_token = OauthToken |> preload(:user) |> Repo.get!(token.id)
      assert loaded_token.user.id == user.id
    end

    test "has one credential" do
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

      loaded_token = OauthToken |> preload(:credential) |> Repo.get!(token.id)
      assert loaded_token.credential.id == credential.id
    end

    test "can load all associations together" do
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
        |> preload([:user, :oauth_client, :credential])
        |> Repo.get!(token.id)

      assert loaded_token.user.id == user.id
      assert loaded_token.oauth_client.id == oauth_client.id
      assert loaded_token.credential.id == credential.id
    end

    test "handles token without credential" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client
        })

      loaded_token = OauthToken |> preload(:credential) |> Repo.get!(token.id)
      assert loaded_token.credential == nil
    end

    test "association constraints work correctly" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      valid_attrs = %{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "read"
        },
        scopes: ["read"],
        oauth_client_id: oauth_client.id,
        user_id: user.id,
        last_refreshed: DateTime.utc_now()
      }

      changeset = OauthToken.changeset(valid_attrs)
      assert {:ok, _token} = Repo.insert(changeset)

      invalid_client_attrs = %{
        valid_attrs
        | oauth_client_id: Ecto.UUID.generate()
      }

      changeset = OauthToken.changeset(invalid_client_attrs)
      assert {:error, changeset} = Repo.insert(changeset)
      assert {"does not exist", _} = changeset.errors[:oauth_client]

      invalid_user_attrs = %{valid_attrs | user_id: Ecto.UUID.generate()}
      changeset = OauthToken.changeset(invalid_user_attrs)
      assert {:error, changeset} = Repo.insert(changeset)
      assert {"does not exist", _} = changeset.errors[:user]
    end

    test "can query tokens by user" do
      user1 = insert(:user)
      user2 = insert(:user)
      oauth_client = insert(:oauth_client)

      _token1 = insert(:oauth_token, %{user: user1, oauth_client: oauth_client})
      token2 = insert(:oauth_token, %{user: user2, oauth_client: oauth_client})
      _token3 = insert(:oauth_token, %{user: user1, oauth_client: oauth_client})

      user1_tokens = OauthToken |> where(user_id: ^user1.id) |> Repo.all()
      user2_tokens = OauthToken |> where(user_id: ^user2.id) |> Repo.all()

      assert length(user1_tokens) == 2
      assert length(user2_tokens) == 1
      assert hd(user2_tokens).id == token2.id
    end

    test "can query tokens by oauth_client" do
      user = insert(:user)
      oauth_client1 = insert(:oauth_client)
      oauth_client2 = insert(:oauth_client)

      token1 = insert(:oauth_token, %{user: user, oauth_client: oauth_client1})
      _token2 = insert(:oauth_token, %{user: user, oauth_client: oauth_client2})
      token3 = insert(:oauth_token, %{user: user, oauth_client: oauth_client1})

      client1_tokens =
        OauthToken |> where(oauth_client_id: ^oauth_client1.id) |> Repo.all()

      client2_tokens =
        OauthToken |> where(oauth_client_id: ^oauth_client2.id) |> Repo.all()

      assert length(client1_tokens) == 2
      assert length(client2_tokens) == 1

      client1_token_ids = Enum.map(client1_tokens, & &1.id) |> Enum.sort()
      expected_ids = [token1.id, token3.id] |> Enum.sort()
      assert client1_token_ids == expected_ids
    end
  end

  describe "encryption" do
    test "encrypts token body at rest" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      body = %{
        "access_token" => "secret_access_token",
        "refresh_token" => "secret_refresh_token",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read"
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
        "token_type" => "Bearer",
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

    test "encrypts complex nested body structures" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      complex_body = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read write",
        "user_info" => %{
          "id" => "user123",
          "name" => "Test User",
          "email" => "test@example.com"
        },
        "provider_data" => %{
          "provider" => "google",
          "account_id" => "google_account_123",
          "additional_fields" => ["field1", "field2"]
        }
      }

      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client,
          body: complex_body,
          scopes: ["read", "write"]
        })

      persisted_body =
        from(t in OauthToken,
          select: type(t.body, :string),
          where: t.id == ^token.id
        )
        |> Repo.one!()

      refute persisted_body == complex_body

      reloaded_token = Repo.get!(OauthToken, token.id)
      assert reloaded_token.body == complex_body
    end

    test "handles empty body maps" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      empty_body = %{}

      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client,
          body: empty_body,
          scopes: []
        })

      reloaded_token = Repo.get!(OauthToken, token.id)
      assert reloaded_token.body == empty_body
    end

    test "encrypts sensitive data in token fields" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      sensitive_body = %{
        "access_token" => "very_secret_access_token_that_should_be_encrypted",
        "refresh_token" => "very_secret_refresh_token_that_should_be_encrypted",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read write admin",
        "client_secret" => "super_secret_client_secret"
      }

      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client,
          body: sensitive_body,
          scopes: ["read", "write", "admin"]
        })

      persisted_body =
        from(t in OauthToken,
          select: type(t.body, :string),
          where: t.id == ^token.id
        )
        |> Repo.one!()

      refute String.contains?(persisted_body, "very_secret_access_token")
      refute String.contains?(persisted_body, "very_secret_refresh_token")
      refute String.contains?(persisted_body, "super_secret_client_secret")

      reloaded_token = Repo.get!(OauthToken, token.id)
      assert reloaded_token.body == sensitive_body
    end

    test "encryption works with very large token bodies" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      large_body = %{
        "access_token" => String.duplicate("a", 1000),
        "refresh_token" => String.duplicate("b", 1000),
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read write",
        "large_data" => String.duplicate("x", 5000),
        "metadata" => %{
          "nested_large_field" => String.duplicate("y", 2000)
        }
      }

      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client,
          body: large_body,
          scopes: ["read", "write"]
        })

      reloaded_token = Repo.get!(OauthToken, token.id)
      assert reloaded_token.body == large_body
    end

    test "multiple tokens encrypt independently" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      body1 = %{
        "access_token" => "token1_access",
        "refresh_token" => "token1_refresh",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read"
      }

      body2 = %{
        "access_token" => "token2_access",
        "refresh_token" => "token2_refresh",
        "token_type" => "Bearer",
        "expires_in" => 7200,
        "scope" => "write admin"
      }

      token1 =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client,
          body: body1,
          scopes: ["read"]
        })

      token2 =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client,
          body: body2,
          scopes: ["write", "admin"]
        })

      reloaded_token1 = Repo.get!(OauthToken, token1.id)
      reloaded_token2 = Repo.get!(OauthToken, token2.id)

      assert reloaded_token1.body == body1
      assert reloaded_token2.body == body2
      refute reloaded_token1.body == reloaded_token2.body
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

    test "virtual fields are not persisted to database" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client,
          body: %{
            "access_token" => "token123",
            "refresh_token" => "refresh123",
            "token_type" => "Bearer",
            "expires_in" => 3600,
            "scope" => "read"
          },
          scopes: ["read"]
        })

      token_with_errors = %{
        token
        | oauth_error_type: :invalid_token_format,
          oauth_error_details: %{reason: "test error"}
      }

      assert token_with_errors.oauth_error_type == :invalid_token_format
      assert token_with_errors.oauth_error_details == %{reason: "test error"}

      reloaded_token = Repo.get!(OauthToken, token.id)
      assert reloaded_token.oauth_error_type == nil
      assert reloaded_token.oauth_error_details == nil
    end

    test "virtual fields maintain type information" do
      token = %OauthToken{
        oauth_error_type: :missing_refresh_token,
        oauth_error_details: %{
          expected_fields: ["refresh_token"],
          provided_fields: ["access_token", "expires_in"]
        }
      }

      assert is_atom(token.oauth_error_type)

      assert is_map(token.oauth_error_details)
      assert token.oauth_error_details.expected_fields == ["refresh_token"]

      assert token.oauth_error_details.provided_fields == [
               "access_token",
               "expires_in"
             ]
    end

    test "virtual fields can hold various error types" do
      error_scenarios = [
        {:missing_scopes, %{missing_scopes: ["write", "admin"]}},
        {:invalid_token_format,
         %{received_type: "string", expected_type: "map"}},
        {:missing_access_token, %{field: "access_token"}},
        {:unsupported_token_type, %{received: "Basic", expected: "Bearer"}}
      ]

      for {error_type, error_details} <- error_scenarios do
        token = %OauthToken{
          oauth_error_type: error_type,
          oauth_error_details: error_details
        }

        assert token.oauth_error_type == error_type
        assert token.oauth_error_details == error_details
      end
    end

    test "virtual fields can be nil" do
      token = %OauthToken{
        oauth_error_type: nil,
        oauth_error_details: nil
      }

      assert token.oauth_error_type == nil
      assert token.oauth_error_details == nil
    end

    test "struct can be created without virtual fields" do
      token = %OauthToken{
        body: %{"access_token" => "token123"},
        scopes: ["read"]
      }

      assert token.oauth_error_type == nil
      assert token.oauth_error_details == nil
    end
  end

  describe "edge cases" do
    test "handles very large token bodies" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      large_body = %{
        "access_token" => String.duplicate("a", 1000),
        "refresh_token" => String.duplicate("b", 1000),
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read write",
        "extra_data" => String.duplicate("c", 5000)
      }

      attrs = %{
        body: large_body,
        scopes: ["read", "write"],
        oauth_client_id: oauth_client.id,
        user_id: user.id,
        last_refreshed: DateTime.utc_now()
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
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read write",
        "custom_field" => "custom_value",
        "nested" => %{"data" => "value"},
        "provider_specific" => %{
          "google_data" => "some_value",
          "metadata" => ["item1", "item2"]
        }
      }

      attrs = %{
        body: body_with_extras,
        scopes: ["read", "write"],
        oauth_client_id: oauth_client.id,
        user_id: user.id,
        last_refreshed: DateTime.utc_now()
      }

      changeset = OauthToken.changeset(attrs)
      assert changeset.valid?
    end

    test "handles token with deeply nested structures" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      deeply_nested_body = %{
        "access_token" => "token123",
        "refresh_token" => "refresh123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read",
        "user_data" => %{
          "profile" => %{
            "personal" => %{
              "name" => "Test User",
              "details" => %{
                "preferences" => %{
                  "theme" => "dark",
                  "notifications" => %{
                    "email" => true,
                    "push" => false
                  }
                }
              }
            }
          }
        }
      }

      attrs = %{
        body: deeply_nested_body,
        scopes: ["read"],
        oauth_client_id: oauth_client.id,
        user_id: user.id,
        last_refreshed: DateTime.utc_now()
      }

      changeset = OauthToken.changeset(attrs)
      assert changeset.valid?
    end

    test "handles token with array values in body" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      body_with_arrays = %{
        "access_token" => "token123",
        "refresh_token" => "refresh123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scopes" => ["read", "write", "admin"],
        "permissions" => ["user:read", "user:write"],
        "features" => ["feature1", "feature2", "feature3"],
        "metadata" => %{
          "tags" => ["tag1", "tag2"],
          "categories" => ["cat1", "cat2"]
        }
      }

      attrs = %{
        body: body_with_arrays,
        scopes: ["read", "write", "admin"],
        oauth_client_id: oauth_client.id,
        user_id: user.id,
        last_refreshed: DateTime.utc_now()
      }

      changeset = OauthToken.changeset(attrs)
      assert changeset.valid?
    end

    test "handles token with numeric values as strings" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      body_with_string_numbers = %{
        "access_token" => "token123",
        "refresh_token" => "refresh123",
        "token_type" => "Bearer",
        "expires_in" => "3600",
        "scope" => "read",
        "user_id" => "12345",
        "timestamp" => "1234567890"
      }

      attrs = %{
        body: body_with_string_numbers,
        scopes: ["read"],
        oauth_client_id: oauth_client.id,
        user_id: user.id,
        last_refreshed: DateTime.utc_now()
      }

      changeset = OauthToken.changeset(attrs)
      assert changeset.valid?
    end

    test "handles tokens with zero or negative expiration times" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      attrs_zero = %{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_in" => 0,
          "scope" => "read"
        },
        scopes: ["read"],
        oauth_client_id: oauth_client.id,
        user_id: user.id,
        last_refreshed: DateTime.utc_now()
      }

      changeset = OauthToken.changeset(attrs_zero)
      refute changeset.valid?

      attrs_negative = %{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_in" => -300,
          "scope" => "read"
        },
        scopes: ["read"],
        oauth_client_id: oauth_client.id,
        user_id: user.id,
        last_refreshed: DateTime.utc_now()
      }

      changeset = OauthToken.changeset(attrs_negative)
      refute changeset.valid?
    end

    test "handles tokens with boolean and null values" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      body_with_mixed_types = %{
        "access_token" => "token123",
        "refresh_token" => "refresh123",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read",
        "is_active" => true,
        "is_expired" => false,
        "optional_field" => nil,
        "metadata" => %{
          "has_refresh" => true,
          "null_field" => nil
        }
      }

      attrs = %{
        body: body_with_mixed_types,
        scopes: ["read"],
        oauth_client_id: oauth_client.id,
        user_id: user.id,
        last_refreshed: DateTime.utc_now()
      }

      changeset = OauthToken.changeset(attrs)
      assert changeset.valid?
    end

    test "handles tokens with unicode and special characters" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      unicode_body = %{
        "access_token" => "tøken123_ñoñó",
        "refresh_token" => "refrësh123_测试",
        "token_type" => "Bearer",
        "expires_in" => 3600,
        "scope" => "read write",
        "user_name" => "Test Üser 测试用户",
        "description" => "Token with émojis 🔐🔑"
      }

      attrs = %{
        body: unicode_body,
        scopes: ["read", "write"],
        oauth_client_id: oauth_client.id,
        user_id: user.id,
        last_refreshed: DateTime.utc_now()
      }

      changeset = OauthToken.changeset(attrs)
      assert changeset.valid?
    end
  end

  describe "integration with OauthValidation" do
    test "validates complete OAuth 2.0 compliance" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      valid_attrs = %{
        body: %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "read write"
        },
        scopes: ["read", "write"],
        oauth_client_id: oauth_client.id,
        user_id: user.id,
        last_refreshed: DateTime.utc_now()
      }

      changeset = OauthToken.changeset(valid_attrs)
      assert changeset.valid?

      invalid_attrs = %{
        body: %{
          "access_token" => "token123"
        },
        scopes: [],
        oauth_client_id: oauth_client.id,
        user_id: user.id,
        last_refreshed: DateTime.utc_now()
      }

      changeset = OauthToken.changeset(invalid_attrs)
      refute changeset.valid?
    end

    test "delegates all validation to OauthValidation module" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      validation_scenarios = [
        {
          %{
            "access_token" => "token",
            "refresh_token" => "refresh",
            "token_type" => "Bearer",
            "expires_in" => 3600,
            "scope" => "read"
          },
          true,
          "Valid complete token"
        },
        {
          %{
            "refresh_token" => "refresh",
            "token_type" => "Bearer",
            "expires_in" => 3600,
            "scope" => "read"
          },
          false,
          "Missing access_token"
        },
        {
          %{
            "access_token" => "token",
            "token_type" => "Bearer",
            "expires_in" => 3600,
            "scope" => "read"
          },
          false,
          "Missing refresh_token"
        },
        {
          %{
            "access_token" => "token",
            "refresh_token" => "refresh",
            "expires_in" => 3600,
            "scope" => "read"
          },
          false,
          "Missing token_type"
        },
        {
          %{
            "access_token" => "token",
            "refresh_token" => "refresh",
            "token_type" => "Basic",
            "expires_in" => 3600,
            "scope" => "read"
          },
          false,
          "Invalid token_type"
        },
        {
          %{
            "access_token" => "",
            "refresh_token" => "refresh",
            "token_type" => "Bearer",
            "expires_in" => 3600,
            "scope" => "read"
          },
          false,
          "Empty access_token"
        },
        {
          %{
            "access_token" => "token",
            "refresh_token" => "refresh",
            "token_type" => "Bearer",
            "expires_in" => 0,
            "scope" => "read"
          },
          false,
          "Zero expires_in"
        },
        {
          %{
            "access_token" => "token",
            "refresh_token" => "refresh",
            "token_type" => "Bearer",
            "scope" => ""
          },
          false,
          "Empty scope"
        }
      ]

      for {body, should_be_valid, description} <- validation_scenarios do
        attrs = %{
          body: body,
          scopes: ["read"],
          oauth_client_id: oauth_client.id,
          user_id: user.id,
          last_refreshed: DateTime.utc_now()
        }

        changeset = OauthToken.changeset(attrs)

        if should_be_valid do
          assert changeset.valid?, "#{description} should be valid"
        else
          refute changeset.valid?, "#{description} should be invalid"
        end
      end
    end
  end

  describe "last_refreshed functionality" do
    test "can manually set last_refreshed in changeset" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      specific_time =
        DateTime.add(DateTime.utc_now(), -2, :hour) |> DateTime.truncate(:second)

      attrs = %{
        body: %{
          "access_token" => "token123",
          "refresh_token" => "refresh123",
          "token_type" => "Bearer",
          "expires_in" => 3600,
          "scope" => "read"
        },
        scopes: ["read"],
        oauth_client_id: oauth_client.id,
        user_id: user.id,
        last_refreshed: specific_time
      }

      changeset = OauthToken.changeset(attrs)
      assert changeset.valid?
      assert get_change(changeset, :last_refreshed) == specific_time
    end

    test "last_refreshed is used for expiry calculations with expires_in" do
      last_refreshed = DateTime.add(DateTime.utc_now(), -1800, :second)

      token = %OauthToken{
        body: %{"expires_in" => 3600},
        last_refreshed: last_refreshed
      }

      assert OauthToken.still_fresh?(token)

      refute OauthToken.still_fresh?(token, 35)
    end
  end
end
