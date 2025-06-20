defmodule Lightning.Credentials.OauthValidationTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Credentials.OauthValidation
  alias Lightning.Credentials.OauthValidation.Error
  alias Lightning.Credentials.OauthToken

  describe "Error struct" do
    test "creates error with type, message, and details" do
      error = Error.new(:missing_scopes, "Test message", %{test: "data"})

      assert error.type == :missing_scopes
      assert error.message == "Test message"
      assert error.details == %{test: "data"}
    end

    test "creates error without details" do
      error = Error.new(:invalid_token_format, "Test message")

      assert error.type == :invalid_token_format
      assert error.message == "Test message"
      assert error.details == nil
    end
  end

  describe "validate_token_data/4" do
    setup do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      %{
        user: user,
        oauth_client: oauth_client,
        valid_token_data: %{
          "access_token" => "access_token_123",
          "refresh_token" => "refresh_token_123",
          "expires_in" => 3600,
          "scope" => "read write"
        },
        scopes: ["read", "write"]
      }
    end

    test "validates complete valid token data", %{
      user: user,
      oauth_client: oauth_client,
      valid_token_data: token_data,
      scopes: scopes
    } do
      result =
        OauthValidation.validate_token_data(
          token_data,
          user.id,
          oauth_client.id,
          scopes
        )

      assert {:ok, ^token_data} = result
    end

    test "validates token with expires_at instead of expires_in", %{
      user: user,
      oauth_client: oauth_client,
      scopes: scopes
    } do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "expires_at" => "2024-12-31T23:59:59Z",
        "scope" => "read write"
      }

      result =
        OauthValidation.validate_token_data(
          token_data,
          user.id,
          oauth_client.id,
          scopes
        )

      assert {:ok, ^token_data} = result
    end

    test "validates token without refresh_token when existing token exists", %{
      user: user,
      oauth_client: oauth_client,
      scopes: scopes
    } do
      insert(:oauth_token, %{
        user: user,
        oauth_client: oauth_client,
        scopes: scopes
      })

      token_data = %{
        "access_token" => "access_token_456",
        "expires_in" => 3600,
        "scope" => "read write"
      }

      result =
        OauthValidation.validate_token_data(
          token_data,
          user.id,
          oauth_client.id,
          scopes
        )

      assert {:ok, ^token_data} = result
    end

    test "rejects invalid token format" do
      result =
        OauthValidation.validate_token_data(
          "invalid_token",
          "user_id",
          "client_id",
          ["read"]
        )

      assert {:error, %Error{type: :invalid_token_format}} = result
    end

    test "rejects token without access_token", %{
      user: user,
      oauth_client: oauth_client,
      scopes: scopes
    } do
      token_data = %{
        "refresh_token" => "refresh_token_123",
        "expires_in" => 3600
      }

      result =
        OauthValidation.validate_token_data(
          token_data,
          user.id,
          oauth_client.id,
          scopes
        )

      assert {:error, %Error{type: :missing_access_token}} = result
    end

    test "rejects token without refresh_token for new connection", %{
      user: user,
      oauth_client: oauth_client,
      scopes: scopes
    } do
      token_data = %{
        "access_token" => "access_token_123",
        "expires_in" => 3600
      }

      result =
        OauthValidation.validate_token_data(
          token_data,
          user.id,
          oauth_client.id,
          scopes
        )

      assert {:error, %Error{type: :missing_refresh_token, details: details}} =
               result

      assert details.existing_token_available == false
    end

    test "rejects token without expiration fields", %{
      user: user,
      oauth_client: oauth_client,
      scopes: scopes
    } do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123"
      }

      result =
        OauthValidation.validate_token_data(
          token_data,
          user.id,
          oauth_client.id,
          scopes
        )

      assert {:error, %Error{type: :missing_expiration}} = result
    end

    test "rejects when scopes are nil", %{
      user: user,
      oauth_client: oauth_client,
      valid_token_data: token_data
    } do
      result =
        OauthValidation.validate_token_data(
          token_data,
          user.id,
          oauth_client.id,
          nil
        )

      assert {:error, %Error{type: :invalid_oauth_response}} = result
    end
  end

  describe "validate_scope_grant/2" do
    test "succeeds when all expected scopes are granted" do
      token_data = %{"scope" => "read write admin"}
      expected_scopes = ["read", "write"]

      result = OauthValidation.validate_scope_grant(token_data, expected_scopes)

      assert :ok = result
    end

    test "succeeds with exact scope match" do
      token_data = %{"scope" => "read write"}
      expected_scopes = ["read", "write"]

      result = OauthValidation.validate_scope_grant(token_data, expected_scopes)

      assert :ok = result
    end

    test "fails when some scopes are missing" do
      token_data = %{"scope" => "read"}
      expected_scopes = ["read", "write", "admin"]

      result = OauthValidation.validate_scope_grant(token_data, expected_scopes)

      assert {:error, %Error{type: :missing_scopes, details: details}} = result
      assert details.missing_scopes == ["write", "admin"]
      assert details.granted_scopes == ["read"]
      assert details.expected_scopes == ["read", "write", "admin"]
    end

    test "fails when token has no scope data" do
      token_data = %{"access_token" => "token123"}
      expected_scopes = ["read"]

      result = OauthValidation.validate_scope_grant(token_data, expected_scopes)

      assert {:error, %Error{type: :invalid_oauth_response}} = result
    end

    test "handles empty scope string" do
      token_data = %{"scope" => ""}
      expected_scopes = ["read"]

      result = OauthValidation.validate_scope_grant(token_data, expected_scopes)

      assert {:error, %Error{type: :missing_scopes}} = result
    end

    test "handles scope string with extra whitespace" do
      token_data = %{"scope" => "  read   write  "}
      expected_scopes = ["read", "write"]

      result = OauthValidation.validate_scope_grant(token_data, expected_scopes)

      assert :ok = result
    end
  end

  describe "extract_scopes/1" do
    test "extracts from string scope with space delimiter" do
      token_data = %{"scope" => "read write admin"}

      result = OauthValidation.extract_scopes(token_data)

      assert {:ok, ["read", "write", "admin"]} = result
    end

    test "extracts from atom key scope" do
      token_data = %{scope: "read write"}

      result = OauthValidation.extract_scopes(token_data)

      assert {:ok, ["read", "write"]} = result
    end

    test "extracts from scopes array with string key" do
      token_data = %{"scopes" => ["read", "write"]}

      result = OauthValidation.extract_scopes(token_data)

      assert {:ok, ["read", "write"]} = result
    end

    test "extracts from scopes array with atom key" do
      token_data = %{scopes: ["read", "write"]}

      result = OauthValidation.extract_scopes(token_data)

      assert {:ok, ["read", "write"]} = result
    end

    test "returns error for invalid format" do
      token_data = %{"access_token" => "token123"}

      result = OauthValidation.extract_scopes(token_data)

      assert :error = result
    end

    test "handles single scope" do
      token_data = %{"scope" => "read"}

      result = OauthValidation.extract_scopes(token_data)

      assert {:ok, ["read"]} = result
    end

    test "handles empty scope string" do
      token_data = %{"scope" => ""}

      result = OauthValidation.extract_scopes(token_data)

      assert {:ok, [""]} = result
    end
  end

  describe "normalize_scopes/2" do
    test "normalizes nil to empty list" do
      result = OauthValidation.normalize_scopes(nil)

      assert [] = result
    end

    test "normalizes string with space delimiter" do
      result = OauthValidation.normalize_scopes("READ Write ADMIN")

      assert ["read", "write", "admin"] = result
    end

    test "normalizes string with custom delimiter" do
      result = OauthValidation.normalize_scopes("read,write,admin", ",")

      assert ["read", "write", "admin"] = result
    end

    test "normalizes OauthToken struct" do
      token = %OauthToken{body: %{"scope" => "READ Write"}}

      result = OauthValidation.normalize_scopes(token)

      assert ["read", "write"] = result
    end

    test "handles token without scope in body" do
      token = %OauthToken{body: %{"access_token" => "token123"}}

      result = OauthValidation.normalize_scopes(token)

      assert [] = result
    end

    test "removes empty strings and trims whitespace" do
      result = OauthValidation.normalize_scopes("  read   write  ")

      assert ["read", "write"] = result
    end

    test "handles empty string" do
      result = OauthValidation.normalize_scopes("")

      assert [] = result
    end
  end

  describe "find_best_matching_token_for_scopes/3" do
    setup do
      user = insert(:user)

      oauth_client =
        insert(:oauth_client, %{
          mandatory_scopes: "profile,email"
        })

      %{user: user, oauth_client: oauth_client}
    end

    test "returns nil for nil oauth_client_id", %{user: user} do
      result =
        OauthValidation.find_best_matching_token_for_scopes(
          user.id,
          nil,
          ["read"]
        )

      assert result == nil
    end

    test "returns nil when no client found", %{user: user} do
      nonexistent_uuid = Ecto.UUID.generate()

      result =
        OauthValidation.find_best_matching_token_for_scopes(
          user.id,
          nonexistent_uuid,
          ["read"]
        )

      assert result == nil
    end

    test "returns nil when no matching tokens exist", %{
      user: user,
      oauth_client: oauth_client
    } do
      result =
        OauthValidation.find_best_matching_token_for_scopes(
          user.id,
          oauth_client.id,
          ["read", "write"]
        )

      assert result == nil
    end

    test "returns exact matching token", %{
      user: user,
      oauth_client: oauth_client
    } do
      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client,
          scopes: ["profile", "email", "read"]
        })

      result =
        OauthValidation.find_best_matching_token_for_scopes(
          user.id,
          oauth_client.id,
          ["read"]
        )

      assert token.id == result.id
    end

    test "prefers token with fewer unrequested scopes", %{
      user: user,
      oauth_client: oauth_client
    } do
      exact_token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client,
          scopes: ["profile", "email", "read"]
        })

      other_client =
        insert(:oauth_client, %{
          client_id: "different_client_id",
          client_secret: oauth_client.client_secret,
          mandatory_scopes: oauth_client.mandatory_scopes
        })

      _extra_token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: other_client,
          scopes: ["profile", "email", "read", "write", "admin"]
        })

      result =
        OauthValidation.find_best_matching_token_for_scopes(
          user.id,
          oauth_client.id,
          ["read"]
        )

      assert exact_token.id == result.id
    end

    test "returns most recent token for mandatory-only requests", %{
      user: user,
      oauth_client: oauth_client
    } do
      older_token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client,
          scopes: ["profile", "email"],
          inserted_at: ~N[2023-01-01 00:00:00],
          updated_at: ~N[2023-01-01 00:00:00]
        })

      newer_client =
        insert(:oauth_client, %{
          client_id: "newer_client_id",
          client_secret: oauth_client.client_secret,
          mandatory_scopes: oauth_client.mandatory_scopes
        })

      _newer_token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: newer_client,
          scopes: ["profile", "email"],
          inserted_at: ~N[2023-01-02 00:00:00],
          updated_at: ~N[2023-01-02 00:00:00]
        })

      result =
        OauthValidation.find_best_matching_token_for_scopes(
          user.id,
          oauth_client.id,
          ["profile", "email"]
        )

      assert older_token.id == result.id
    end
  end

  describe "private validation functions" do
    test "token_exists? function works correctly" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)
      scopes = ["read", "write"]

      result =
        OauthValidation.find_best_matching_token_for_scopes(
          user.id,
          oauth_client.id,
          scopes
        )

      assert result == nil

      token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client,
          scopes: scopes
        })

      result =
        OauthValidation.find_best_matching_token_for_scopes(
          user.id,
          oauth_client.id,
          scopes
        )

      assert result.id == token.id
    end
  end

  describe "integration scenarios" do
    setup do
      user = insert(:user)

      oauth_client =
        insert(:oauth_client, %{
          mandatory_scopes: "profile,email"
        })

      %{user: user, oauth_client: oauth_client}
    end

    test "complete OAuth flow validation", %{
      user: user,
      oauth_client: oauth_client
    } do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "expires_in" => 3600,
        "scope" => "profile email read write"
      }

      requested_scopes = ["profile", "email", "read"]

      assert {:ok, ^token_data} =
               OauthValidation.validate_token_data(
                 token_data,
                 user.id,
                 oauth_client.id,
                 requested_scopes
               )

      assert :ok =
               OauthValidation.validate_scope_grant(token_data, requested_scopes)

      _oauth_token =
        insert(:oauth_token, %{
          user: user,
          oauth_client: oauth_client,
          scopes: requested_scopes,
          body: token_data
        })

      new_token_data = %{
        "access_token" => "access_token_456",
        "expires_in" => 3600,
        "scope" => "profile email read"
      }

      assert {:ok, ^new_token_data} =
               OauthValidation.validate_token_data(
                 new_token_data,
                 user.id,
                 oauth_client.id,
                 requested_scopes
               )
    end

    test "validation fails for insufficient scopes", %{
      user: user,
      oauth_client: oauth_client
    } do
      token_data = %{
        "access_token" => "access_token_123",
        "refresh_token" => "refresh_token_123",
        "expires_in" => 3600,
        "scope" => "profile email"
      }

      requested_scopes = ["profile", "email", "read"]

      assert {:ok, ^token_data} =
               OauthValidation.validate_token_data(
                 token_data,
                 user.id,
                 oauth_client.id,
                 requested_scopes
               )

      assert {:error, %Error{type: :missing_scopes, details: details}} =
               OauthValidation.validate_scope_grant(token_data, requested_scopes)

      assert details.missing_scopes == ["read"]
    end
  end

  describe "edge cases" do
    test "handles malformed scope strings gracefully" do
      token_data = %{"scope" => "   read    write   admin   "}
      expected_scopes = ["read", "write", "admin"]

      result = OauthValidation.validate_scope_grant(token_data, expected_scopes)

      assert :ok = result
    end

    test "handles duplicate scopes in grant" do
      token_data = %{"scope" => "read read write write"}
      expected_scopes = ["read", "write"]

      result = OauthValidation.validate_scope_grant(token_data, expected_scopes)

      assert :ok = result
    end

    test "validates with mixed case scopes" do
      result = OauthValidation.normalize_scopes("READ Write ADMIN")

      assert ["read", "write", "admin"] = result
    end

    test "handles very long scope strings" do
      long_scope = String.duplicate("scope", 1000)
      token_data = %{"scope" => long_scope}

      result = OauthValidation.extract_scopes(token_data)

      assert {:ok, [^long_scope]} = result
    end

    test "handles empty arrays gracefully" do
      result = OauthValidation.validate_scope_grant(%{"scope" => ""}, [])

      assert :ok = result
    end
  end
end
